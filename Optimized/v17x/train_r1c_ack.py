"""train_r1c_ack.py
Trains HistGradientBoostingClassifier model for Stage r1c (Amendment 10, Freeze v11/v12).
Spec: paper/proposals/R1c_ack_prereg.md §2.
"""
import sys, os, hashlib, joblib, csv
import numpy as np
import scipy.io as sio
from sklearn.ensemble import HistGradientBoostingClassifier

def train_model(calib_mat, joblib_out, trees_mat, hash_out, xfit_csv_out=None):
    print(f"Loading calibration data from {calib_mat}...")
    try:
        mat = sio.loadmat(calib_mat)
    except Exception:
        import h5py
        f = h5py.File(calib_mat, 'r')
        mat = {k: np.array(f[k]) for k in f.keys()}

    # Assert no forbidden truth columns in mat
    for k in mat.keys():
        k_low = k.lower()
        assert 'sinr' not in k_low, f"Forbidden column {k} found in calibration data!"
        assert 'psucc' not in k_low, f"Forbidden column {k} found in calibration data!"
        assert 'bler' not in k_low, f"Forbidden column {k} found in calibration data!"
        assert 'spd' not in k_low, f"Forbidden column {k} found in calibration data!"
        assert 'speed' not in k_low, f"Forbidden column {k} found in calibration data!"

    X_feat = np.asarray(mat['X_feat'], dtype=np.float64)
    if X_feat.shape[1] != 19 and X_feat.shape[0] == 19:
        X_feat = X_feat.T

    mcs_taken = np.asarray(mat['mcs_taken'], dtype=np.float64).reshape(-1, 1)
    if mcs_taken.shape[0] != X_feat.shape[0] and mcs_taken.shape[1] == X_feat.shape[0]:
        mcs_taken = mcs_taken.T

    ack1 = np.asarray(mat['ack1'], dtype=np.int32).ravel()
    trace_id = np.asarray(mat['trace_id'], dtype=np.int32).ravel()
    explored = np.asarray(mat['explored'], dtype=np.int32).ravel() if 'explored' in mat else np.zeros_like(ack1)

    N_samples = X_feat.shape[0]
    print(f"Loaded {N_samples} decisions across {len(np.unique(trace_id))} calibration traces.")
    assert X_feat.shape[1] == 19, f"Expected 19 observable features, got {X_feat.shape[1]}"
    assert len(ack1) == N_samples, f"ack1 length {len(ack1)} mismatch with {N_samples}"
    assert set(np.unique(ack1)).issubset({0, 1}), f"ack1 must be in {{0, 1}}, got {np.unique(ack1)}"

    # Inputs (20): obs_1..obs_19 and MCS index of transmission
    X_all = np.column_stack([X_feat, mcs_taken])
    assert X_all.shape == (N_samples, 20), f"Expected shape ({N_samples}, 20), got {X_all.shape}"

    # 1. Main deployed model (gbt_a settings, frozen)
    print("Fitting main deployed HistGradientBoostingClassifier model (gbt_a settings)...")
    clf = HistGradientBoostingClassifier(
        loss='log_loss',
        max_iter=300,
        learning_rate=0.05,
        max_leaf_nodes=31,
        min_samples_leaf=40,
        early_stopping=False,
        random_state=0
    )
    clf.fit(X_all, ack1)

    # Save joblib
    print(f"Saving deployed model to {joblib_out}...")
    os.makedirs(os.path.dirname(os.path.abspath(joblib_out)), exist_ok=True)
    joblib.dump(clf, joblib_out)

    # Compute SHA-256 hash before evaluation
    sha256 = hashlib.sha256(open(joblib_out, 'rb').read()).hexdigest()
    print(f"Deployed model SHA-256: {sha256}")
    if hash_out:
        os.makedirs(os.path.dirname(os.path.abspath(hash_out)), exist_ok=True)
        with open(hash_out, 'w', encoding='utf-8') as f:
            f.write(f"{sha256}  {os.path.basename(joblib_out)}\n")

    # 2. Export tree predictors for MATLAB
    print(f"Exporting tree structures for MATLAB bit-level prediction...")
    tree_list = []
    for pred in clf._predictors:
        p = pred[0]
        nodes = p.nodes
        tree_dict = {
            'feat': nodes['feature_idx'].astype(np.int32) + 1,  # 1-based for MATLAB
            'th': nodes['num_threshold'].astype(np.float64),
            'left': nodes['left'].astype(np.int32) + 1,         # 1-based for MATLAB
            'right': nodes['right'].astype(np.int32) + 1,       # 1-based for MATLAB
            'val': nodes['value'].astype(np.float64),
            'is_leaf': nodes['is_leaf'].astype(np.uint8)
        }
        tree_list.append(tree_dict)

    trees_export = {
        'baseline': float(np.ravel(clf._baseline_prediction)[0]),
        'trees': tree_list
    }

    # Equivalence check data (1000 samples)
    n_eq = min(1000, N_samples)
    X_eq = X_all[:n_eq]
    P_pred_sk = clf.predict_proba(X_eq)[:, 1]

    os.makedirs(os.path.dirname(os.path.abspath(trees_mat)), exist_ok=True)
    sio.savemat(trees_mat, {
        'trees_export': trees_export,
        'X_equiv': X_eq,
        'P_pred_sk': P_pred_sk,
        'sha256': sha256
    })

    # 3. 5-fold cross-fitting for calibration diagnostics if requested
    if xfit_csv_out:
        print("Computing 5-fold cross-fitted predictions (folds by trace mod 5)...")
        p_hat_xfit = np.zeros(N_samples, dtype=np.float64)
        folds = (trace_id.astype(int) - 1) % 5
        for k in range(5):
            idx_test = (folds == k)
            idx_train = (folds != k)
            clf_k = HistGradientBoostingClassifier(
                loss='log_loss',
                max_iter=300,
                learning_rate=0.05,
                max_leaf_nodes=31,
                min_samples_leaf=40,
                early_stopping=False,
                random_state=0
            )
            clf_k.fit(X_all[idx_train], ack1[idx_train])
            if np.sum(idx_test) > 0:
                p_hat_xfit[idx_test] = clf_k.predict_proba(X_all[idx_test])[:, 1]

        os.makedirs(os.path.dirname(os.path.abspath(xfit_csv_out)), exist_ok=True)
        with open(xfit_csv_out, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['trace', 'mcs', 'p_hat', 'ack1', 'explored'])
            for i in range(N_samples):
                w.writerow([int(trace_id[i]), int(mcs_taken[i]), f"{p_hat_xfit[i]:.6f}", int(ack1[i]), int(explored[i])])

    return sha256

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print("Usage: python train_r1c_ack.py <calib_mat> <joblib_out> <trees_mat> <hash_out> [xfit_csv_out]")
        sys.exit(1)
    xfit = sys.argv[5] if len(sys.argv) >= 6 else None
    train_model(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], xfit)
