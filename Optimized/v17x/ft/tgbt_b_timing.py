"""tgbt_b_timing.py -- T-GBT-b compiled & vectorized tree-inference benchmark.
(Descriptive, added after seeing T-GBT scikit-learn overhead.)

Benchmarks the exact fit-1 trees (r1b_model.joblib / r1b_trees.mat) across 3 runtimes:
  (a) ONNX Runtime (TreeEnsembleClassifier, single-threaded ORT_SEQUENTIAL)
  (b) Vectorized NumPy tree traversal of exported trees (trees_export)
  (c) Treelite GTIL (compiled C++ tree inference, nthread=1)

Protocol (identical to A3c):
  - Single-threaded (OMP=1, MKL=1, OPENBLAS=1, ORT intra=inter=1, Treelite nthread=1)
  - HIGH_PRIORITY_CLASS
  - Empty-loop timer noise floor subtracted
  - Equivalence checked on 10,000 calibration feature rows x all candidate MCS values
    (GBT-res-ACK: 30,000 rows; GBT-full-ACK: 70,000 rows) -> max |dp| <= 1e-6 and 100% MCS match
  - Timed for N in {10, 50, 100} users per TTI (all N users x K candidates per TTI)
  - Appends section 'T-GBT-b (descriptive, added after T-GBT)' to tgbt_timing.txt
"""
import os
import sys

os.environ["OMP_NUM_THREADS"] = "1"
os.environ["OPENBLAS_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"
os.environ["VECLIB_MAXIMUM_THREADS"] = "1"
os.environ["NUMEXPR_NUM_THREADS"] = "1"

import time
import joblib
import psutil
import h5py
import numpy as np
import scipy.io as sio
import onnx
from onnx import helper, TensorProto
import onnxruntime as ort
import treelite

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
DATASET_DIR = os.path.join(REPO_ROOT, "Optimized", "v17x", "Dataset")
TGBT_TXT = os.path.join(DATASET_DIR, "ft", "tgbt_timing.txt")


def construct_s_now_1frame(ref_in, prevRef_in, obs_in, prev_obs_in, obs_4_in, off_in,
                           nk_in, H_pend_in, H_nret_in, r_ema_in, sl_in, busy_cnt_in, ctx_in, N, Dm=10.0):
    """Build the 19-feature current-frame matrix (N x 19)."""
    dRef = np.clip(ref_in - prevRef_in, -3, 3)
    dS = obs_in - prev_obs_in
    slope4 = (obs_in - obs_4_in) * 0.25
    r_max = np.max(r_ema_in)
    r_norm = r_ema_in / r_max if r_max > 1e-6 else np.zeros_like(r_ema_in)

    s_now = np.empty((N, 19), dtype=np.float32)
    s_now[:, 0] = ref_in / 15.0
    s_now[:, 1] = dRef / 5.0
    s_now[:, 2] = obs_in / 30.0
    s_now[:, 3] = dS / 5.0
    s_now[:, 4] = off_in / 5.0
    s_now[:, 5] = slope4 / 5.0
    s_now[:, 6] = nk_in
    s_now[:, 7] = H_pend_in
    s_now[:, 8] = H_nret_in / 3.0
    s_now[:, 9] = r_norm
    s_now[:, 10] = np.minimum(sl_in, Dm) / Dm
    s_now[:, 11] = 1.0
    s_now[:, 12] = 0.0
    s_now[:, 13] = busy_cnt_in / 8.0
    s_now[:, 14] = 0.0
    s_now[:, 15] = 0.0
    s_now[:, 16:19] = ctx_in
    return s_now


def build_onnx_from_hgbt(clf):
    """Build ONNX TreeEnsembleClassifier directly from HistGradientBoostingClassifier._predictors."""
    nodes_treeids = []
    nodes_nodeids = []
    nodes_featureids = []
    nodes_values = []
    nodes_hitrates = []
    nodes_modes = []
    nodes_truenodeids = []
    nodes_falsenodeids = []
    nodes_missing = []

    target_treeids = []
    target_nodeids = []
    target_ids = []
    target_weights = []

    for tid, pred in enumerate(clf._predictors):
        nodes = pred[0].nodes
        n_nodes = len(nodes)
        for nid in range(n_nodes):
            nd = nodes[nid]
            nodes_treeids.append(tid)
            nodes_nodeids.append(nid)
            nodes_hitrates.append(1.0)
            if nd['is_leaf']:
                nodes_featureids.append(0)
                nodes_values.append(0.0)
                nodes_modes.append('LEAF')
                nodes_truenodeids.append(0)
                nodes_falsenodeids.append(0)
                nodes_missing.append(0)
                target_treeids.append(tid)
                target_nodeids.append(nid)
                target_ids.append(0)
                target_weights.append(float(nd['value']))
            else:
                nodes_featureids.append(int(nd['feature_idx']))
                nodes_values.append(float(nd['num_threshold']))
                nodes_modes.append('BRANCH_LEQ')
                nodes_truenodeids.append(int(nd['left']))
                nodes_falsenodeids.append(int(nd['right']))
                nodes_missing.append(1 if bool(nd['missing_go_to_left']) else 0)

    base_val = float(np.ravel(clf._baseline_prediction)[0])
    node = helper.make_node(
        'TreeEnsembleClassifier',
        inputs=['X'],
        outputs=['label', 'probabilities'],
        domain='ai.onnx.ml',
        base_values=[base_val],
        class_ids=target_ids,
        class_nodeids=target_nodeids,
        class_treeids=target_treeids,
        class_weights=target_weights,
        classlabels_int64s=[0, 1],
        nodes_falsenodeids=nodes_falsenodeids,
        nodes_featureids=nodes_featureids,
        nodes_hitrates=nodes_hitrates,
        nodes_missing_value_tracks_true=nodes_missing,
        nodes_modes=nodes_modes,
        nodes_nodeids=nodes_nodeids,
        nodes_treeids=nodes_treeids,
        nodes_truenodeids=nodes_truenodeids,
        nodes_values=nodes_values,
        post_transform='LOGISTIC',
    )
    graph = helper.make_graph(
        [node],
        'hgbt_r1b',
        [helper.make_tensor_value_info('X', TensorProto.FLOAT, [None, 20])],
        [
            helper.make_tensor_value_info('label', TensorProto.INT64, [None]),
            helper.make_tensor_value_info('probabilities', TensorProto.FLOAT, [None, 2]),
        ],
    )
    model = helper.make_model(
        graph,
        ir_version=9,
        opset_imports=[
            helper.make_opsetid('', 13),
            helper.make_opsetid('ai.onnx.ml', 1),
        ],
    )
    onnx.checker.check_model(model)
    return model.SerializeToString()


class VectorizedNumpyTrees:
    """Vectorized NumPy tree traversal of exported trees (trees_export from r1b_trees.mat)."""
    def __init__(self, trees_mat_path):
        m = sio.loadmat(trees_mat_path)
        te = m['trees_export'][0, 0]
        self.baseline = float(te['baseline'][0, 0])
        trees_raw = te['trees'][0]
        self.n_trees = len(trees_raw)
        max_nodes = max(len(t['is_leaf'][0, 0].ravel()) for t in trees_raw)

        self.feat = np.zeros((self.n_trees, max_nodes), dtype=np.int32)
        self.th = np.zeros((self.n_trees, max_nodes), dtype=np.float64)
        self.left = np.zeros((self.n_trees, max_nodes), dtype=np.int32)
        self.right = np.zeros((self.n_trees, max_nodes), dtype=np.int32)
        self.val = np.zeros((self.n_trees, max_nodes), dtype=np.float64)
        self.is_leaf = np.ones((self.n_trees, max_nodes), dtype=bool)
        self.max_depth = 0

        for ti, tr_obj in enumerate(trees_raw):
            tr = tr_obj[0, 0]
            isl = tr['is_leaf'].ravel().astype(bool)
            n = len(isl)
            self.is_leaf[ti, :n] = isl
            self.feat[ti, :n] = np.clip(tr['feat'].ravel().astype(np.int32) - 1, 0, 19)
            self.th[ti, :n] = tr['th'].ravel().astype(np.float64)
            lf = tr['left'].ravel().astype(np.int32) - 1
            rt = tr['right'].ravel().astype(np.int32) - 1
            # For leaves, self-loop so vectorized traversal stays at leaf
            arange_n = np.arange(n, dtype=np.int32)
            self.left[ti, :n] = np.where(isl, arange_n, lf)
            self.right[ti, :n] = np.where(isl, arange_n, rt)
            self.val[ti, :n] = tr['val'].ravel().astype(np.float64)

        self.tree_idx = np.arange(self.n_trees, dtype=np.int32)[None, :]  # (1, T)
        # Compute exact max depth
        self.max_depth = 31  # max_leaf_nodes=31 => worst-case depth <= 30

    def predict_proba_1(self, X):
        # X: (M, 20)
        M = X.shape[0]
        idx = np.zeros((M, self.n_trees), dtype=np.int32)
        row_idx = np.arange(M, dtype=np.int32)[:, None]
        for _ in range(self.max_depth):
            isl = self.is_leaf[self.tree_idx, idx]
            if np.all(isl):
                break
            f = self.feat[self.tree_idx, idx]
            go_left = X[row_idx, f] <= self.th[self.tree_idx, idx]
            idx = np.where(isl, idx, np.where(go_left, self.left[self.tree_idx, idx], self.right[self.tree_idx, idx]))
        raw = self.baseline + self.val[self.tree_idx, idx].sum(axis=1)
        return 1.0 / (1.0 + np.exp(-raw))


def run_decision(score_fn, s_now, ref_in, bits_rem, offsets, tbs_lut, dtype=np.float32):
    N = len(ref_in)
    K = len(offsets)
    cand_cqi = np.clip(ref_in[:, None] + offsets[None, :], 1, 15)
    cand_mcs = np.clip(cand_cqi - 1, 0, 14)

    X_cand = np.empty((N * K, 20), dtype=dtype)
    X_cand[:, :19] = np.repeat(s_now, K, axis=0)
    X_cand[:, 19] = cand_mcs.ravel()

    p_hat = score_fn(X_cand).reshape(N, K)
    tb = tbs_lut[cand_mcs]
    ub = np.minimum(tb, bits_rem[:, None])
    q = p_hat * ub
    best_k = np.argmax(q, axis=1)
    return cand_mcs[np.arange(N), best_k], p_hat


def main():
    try:
        psutil.Process().nice(psutil.HIGH_PRIORITY_CLASS)
        prio_str = "HIGH_PRIORITY_CLASS (128)"
    except Exception as e:
        prio_str = f"Default ({e})"

    clf = joblib.load(os.path.join(DATASET_DIR, "r1b_model.joblib"))
    trees_mat = os.path.join(DATASET_DIR, "ckpt", "r1b_ack", "r1b_trees.mat")

    # 1. Build ONNX Runtime session
    onx_bytes = build_onnx_from_hgbt(clf)
    sess_opts = ort.SessionOptions()
    sess_opts.intra_op_num_threads = 1
    sess_opts.inter_op_num_threads = 1
    sess_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    ort_sess = ort.InferenceSession(onx_bytes, sess_opts, providers=['CPUExecutionProvider'])
    score_onnx = lambda X: ort_sess.run(None, {'X': X})[1][:, 1]

    # 2. Vectorized NumPy tree traversal
    np_trees = VectorizedNumpyTrees(trees_mat)
    score_numpy = lambda X: np_trees.predict_proba_1(X)

    # 3. Treelite GTIL
    tl_model = treelite.sklearn.import_model(clf)
    score_treelite = lambda X: treelite.gtil.predict(tl_model, X, nthread=1, pred_margin=False).ravel()

    # Load 10,000 calibration rows from calib_log_r1b.mat for equivalence verification
    calib_mat = os.path.join(DATASET_DIR, "ckpt", "r1b_ack", "calib_log_r1b.mat")
    try:
        cmat = sio.loadmat(calib_mat)
    except Exception:
        with h5py.File(calib_mat, 'r') as f:
            cmat = {k: np.array(f[k]) for k in f.keys()}

    X_feat = np.asarray(cmat['X_feat'], dtype=np.float64)
    if X_feat.shape[1] != 19 and X_feat.shape[0] == 19:
        X_feat = X_feat.T
    X_10k = X_feat[:10000]
    ref_10k = np.clip(np.round(X_10k[:, 0] * 15.0).astype(np.int32), 1, 15)
    bits_10k = np.full(10000, 5000.0, dtype=np.float64)
    tbs_lut = np.array([1376, 1736, 2216, 2856, 3624, 4392, 5160, 6200, 7224,
                        8248, 9528, 10680, 12216, 13536, 15264], dtype=np.float64)

    res_offsets = np.array([-3, -2, -1], dtype=np.int32)
    full_offsets = np.array([-4, -3, -2, -1, 0, 1, 2], dtype=np.int32)

    # Equivalence checks on 10,000 calibration rows x all candidate MCS values
    eq_lines = []
    eq_lines.append("Equivalence Check on 10,000 calibration feature rows x all candidate MCS values:")
    for mode_name, offs in [("GBT-res-ACK (30k rows)", res_offsets), ("GBT-full-ACK (70k rows)", full_offsets)]:
        mcs_sk, p_sk = run_decision(lambda X: clf.predict_proba(X)[:, 1], X_10k, ref_10k, bits_10k, offs, tbs_lut, dtype=np.float64)
        for rt_name, fn, dt in [
            ("ONNX Runtime", score_onnx, np.float32),
            ("Vectorized NumPy", score_numpy, np.float64),
            ("Treelite GTIL", score_treelite, np.float32),
        ]:
            mcs_rt, p_rt = run_decision(fn, X_10k.astype(dt), ref_10k, bits_10k, offs, tbs_lut, dtype=dt)
            max_dp = float(np.max(np.abs(p_sk - p_rt)))
            match_pct = 100.0 * float(np.mean(mcs_sk == mcs_rt))
            eq_lines.append(f"  {mode_name:25s} | {rt_name:18s} | max |dp| = {max_dp:.3e} | MCS match = {match_pct:.2f}%")
            assert max_dp <= 1e-6, f"Equivalence failed for {rt_name} on {mode_name}: {max_dp}"
            assert match_pct == 100.0, f"MCS mismatch for {rt_name} on {mode_name}: {match_pct}%"

    # Timer noise floor (10,000 iterations, 500 warm-up)
    n_warm = 500
    n_ttis = 10000
    for _ in range(n_warm):
        t0 = time.perf_counter_ns()
        _ = (time.perf_counter_ns() - t0)
    t_noise = np.empty(n_ttis, dtype=np.float64)
    for it in range(n_ttis):
        t0 = time.perf_counter_ns()
        t_noise[it] = (time.perf_counter_ns() - t0) / 1000.0
    noise_med = float(np.median(t_noise))
    noise_p999 = float(np.percentile(t_noise, 99.9))

    out = []
    out.append("")
    out.append("=" * 88)
    out.append("T-GBT-b (descriptive, added after T-GBT)")
    out.append("=" * 88)
    out.append(f"Process Priority : {prio_str} | Threading: Single-Threaded (all libs=1)")
    out.append(f"Sample Count     : {n_ttis:,} TTIs per condition ({n_warm:,} warm-up excluded)")
    out.append(f"Noise Floor      : median = {noise_med:.3f} us | p99.9 = {noise_p999:.3f} us")
    out.append("Per-TTI Work     : All N users simultaneously: 1-frame 19-feature build, candidate")
    out.append("                   MCS expansion (K=3 for res -> 3N rows; K=7 for full -> 7N rows),")
    out.append("                   300-tree probability scoring, tbs*p_hat utility, and argmax.")
    out.append("")
    out.extend(eq_lines)
    out.append("")

    runtimes = [
        ("ONNX Runtime", score_onnx, np.float32),
        ("Treelite GTIL", score_treelite, np.float32),
        ("Vec NumPy", score_numpy, np.float64),
    ]

    for N in [10, 50, 100]:
        rng = np.random.RandomState(60001 + N)
        ref = rng.randint(1, 16, size=N).astype(np.int32)
        prevRef = ref.copy()
        obs_SINR = rng.randn(N).astype(np.float32) * 8.0 + 10.0
        prev_obs = obs_SINR.copy()
        obs_4 = obs_SINR.copy()
        off = np.zeros(N, dtype=np.float32)
        nk = rng.rand(N).astype(np.float32) * 0.2
        H_pend = (rng.rand(N) > 0.5).astype(np.float32)
        H_nret = rng.randint(0, 4, size=N).astype(np.float32)
        r_ema = rng.rand(N).astype(np.float32) * 50.0
        sl = rng.randint(1, 11, size=N).astype(np.float32)
        busy_cnt = rng.randint(0, 5, size=N).astype(np.float32)
        bits_rem = rng.randint(500, 10000, size=N).astype(np.float64)
        ctx = np.zeros((N, 3), dtype=np.float32)
        ctx[:, 0] = 1.0

        out.append(f"--- N = {N} Users {'(Main Scenario)' if N == 10 else ''} ---")
        out.append(f"{'Scheme & Runtime':34s} | {'Median (us)':>11s} | {'Corr p99.9 (us)':>15s} | {'15kHz(<=1ms)':>12s} | {'30kHz(<=500us)':>14s} | {'60kHz(<=250us)':>14s} | {'120kHz(<=125us)':>15s}")
        out.append("-" * 126)

        for mode_label, offs in [("GBT-res-ACK", res_offsets), ("GBT-full-ACK", full_offsets)]:
            for rt_label, fn, dt in runtimes:
                # Warmup
                for _ in range(n_warm):
                    s = construct_s_now_1frame(ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H_pend, H_nret, r_ema, sl, busy_cnt, ctx, N)
                    if dt == np.float64: s = s.astype(np.float64)
                    _ = run_decision(fn, s, ref, bits_rem, offs, tbs_lut, dtype=dt)

                t_arr = np.empty(n_ttis, dtype=np.float64)
                for it in range(n_ttis):
                    t0 = time.perf_counter_ns()
                    s = construct_s_now_1frame(ref, prevRef, obs_SINR, prev_obs, obs_4, off, nk, H_pend, H_nret, r_ema, sl, busy_cnt, ctx, N)
                    if dt == np.float64: s = s.astype(np.float64)
                    _ = run_decision(fn, s, ref, bits_rem, offs, tbs_lut, dtype=dt)
                    t_arr[it] = (time.perf_counter_ns() - t0) / 1000.0

                med = float(np.median(t_arr)) - noise_med
                p999_corr = float(np.percentile(t_arr, 99.9)) - noise_p999
                s15 = 100.0 * np.mean((t_arr - noise_med) <= 1000.0)
                s30 = 100.0 * np.mean((t_arr - noise_med) <= 500.0)
                s60 = 100.0 * np.mean((t_arr - noise_med) <= 250.0)
                s120 = 100.0 * np.mean((t_arr - noise_med) <= 125.0)
                lbl = f"{mode_label} ({rt_label})"
                out.append(f"{lbl:34s} | {med:11.2f} | {p999_corr:15.2f} | {s15:11.2f}% | {s30:13.2f}% | {s60:13.2f}% | {s120:14.2f}%")
        out.append("")

    section_txt = "\n".join(out) + "\n"
    with open(TGBT_TXT, "a", encoding="utf-8") as f:
        f.write(section_txt)
    print(section_txt)


if __name__ == "__main__":
    main()
