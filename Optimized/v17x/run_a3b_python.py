import os
import sys
import time
import platform
import numpy as np
import scipy.io as sio
import onnxruntime as ort
import pandas as pd

def run_python_benchmark():
    here = os.path.dirname(os.path.abspath(__file__))
    dataset_dir = os.path.join(here, "Dataset")
    
    print("=== Loading MATLAB Exports and ONNX Models ===")
    mat_path = os.path.join(dataset_dir, "a3b_export.mat")
    mat = sio.loadmat(mat_path)
    X_test = mat['X_test']
    logits_nr2_matlab = mat['logits_nr2_test']
    logits_m1_matlab = mat['logits_m1_test']
    
    Wa_nr2_raw = mat['Wa_nr2'][0, 0]
    Wa_nr2 = {
        'w1': Wa_nr2_raw['w1'].astype(np.float32),
        'b1': Wa_nr2_raw['b1'].astype(np.float32),
        'w2': Wa_nr2_raw['w2'].astype(np.float32),
        'b2': Wa_nr2_raw['b2'].astype(np.float32),
        'w3': Wa_nr2_raw['w3'].astype(np.float32),
        'b3': Wa_nr2_raw['b3'].astype(np.float32),
    }
    
    Wa_m1_raw = mat['Wa_m1'][0, 0]
    Wa_m1 = {
        'w1': Wa_m1_raw['w1'].astype(np.float32),
        'b1': Wa_m1_raw['b1'].astype(np.float32),
        'w2': Wa_m1_raw['w2'].astype(np.float32),
        'b2': Wa_m1_raw['b2'].astype(np.float32),
        'w3': Wa_m1_raw['w3'].astype(np.float32),
        'b3': Wa_m1_raw['b3'].astype(np.float32),
    }
    
    onnx_nr2_path = os.path.join(dataset_dir, "actor_nr2.onnx")
    onnx_m1_path = os.path.join(dataset_dir, "actor_m1.onnx")
    
    sess_opts = ort.SessionOptions()
    sess_opts.intra_op_num_threads = 4
    sess_opts.inter_op_num_threads = 1
    sess_opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    
    sess_nr2 = ort.InferenceSession(onnx_nr2_path, sess_opts, providers=['CPUExecutionProvider'])
    sess_m1 = ort.InferenceSession(onnx_m1_path, sess_opts, providers=['CPUExecutionProvider'])
    
    print("=== Numerical Equivalence Check vs MATLAB ===")
    # 1. NumPy verification
    # Input is 57 x 1000
    h1_nr2 = np.maximum(0.0, Wa_nr2['w1'] @ X_test + Wa_nr2['b1'])
    h2_nr2 = np.maximum(0.0, Wa_nr2['w2'] @ h1_nr2 + Wa_nr2['b2'])
    logits_nr2_numpy = Wa_nr2['w3'] @ h2_nr2 + Wa_nr2['b3']
    diff_numpy_nr2 = np.max(np.abs(logits_nr2_numpy - logits_nr2_matlab))
    
    h1_m1 = np.maximum(0.0, Wa_m1['w1'] @ X_test + Wa_m1['b1'])
    h2_m1 = np.maximum(0.0, Wa_m1['w2'] @ h1_m1 + Wa_m1['b2'])
    logits_m1_numpy = Wa_m1['w3'] @ h2_m1 + Wa_m1['b3']
    diff_numpy_m1 = np.max(np.abs(logits_m1_numpy - logits_m1_matlab))
    
    # 2. ONNX verification
    # ONNX expects (BatchSize, 57)
    X_test_onnx = X_test.T.astype(np.float32)
    logits_nr2_onnx = sess_nr2.run(None, {'in': X_test_onnx})[0].T
    diff_onnx_nr2 = np.max(np.abs(logits_nr2_onnx - logits_nr2_matlab))
    
    logits_m1_onnx = sess_m1.run(None, {'in': X_test_onnx})[0].T
    diff_onnx_m1 = np.max(np.abs(logits_m1_onnx - logits_m1_matlab))
    
    print(f"NR2 NumPy max abs diff vs MATLAB : {diff_numpy_nr2:.2e}")
    print(f"NR2 ONNX  max abs diff vs MATLAB : {diff_onnx_nr2:.2e}")
    print(f"M1  NumPy max abs diff vs MATLAB : {diff_numpy_m1:.2e}")
    print(f"M1  ONNX  max abs diff vs MATLAB : {diff_onnx_m1:.2e}")
    
    # Check action selection match (argmax)
    act_matlab_nr2 = np.argmax(logits_nr2_matlab, axis=0)
    act_numpy_nr2 = np.argmax(logits_nr2_numpy, axis=0)
    act_onnx_nr2 = np.argmax(logits_nr2_onnx, axis=0)
    act_diff_numpy_nr2 = np.sum(act_matlab_nr2 != act_numpy_nr2)
    act_diff_onnx_nr2 = np.sum(act_matlab_nr2 != act_onnx_nr2)
    
    act_matlab_m1 = np.argmax(logits_m1_matlab, axis=0)
    act_numpy_m1 = np.argmax(logits_m1_numpy, axis=0)
    act_onnx_m1 = np.argmax(logits_m1_onnx, axis=0)
    act_diff_numpy_m1 = np.sum(act_matlab_m1 != act_numpy_m1)
    act_diff_onnx_m1 = np.sum(act_matlab_m1 != act_onnx_m1)
    
    print(f"NR2 Argmax discrepancies across 1000 samples: NumPy={act_diff_numpy_nr2}, ONNX={act_diff_onnx_nr2}")
    print(f"M1  Argmax discrepancies across 1000 samples: NumPy={act_diff_numpy_m1}, ONNX={act_diff_onnx_m1}")
    
    # Benchmark settings
    n_users_list = [10, 50, 100]
    n_warm = 1000
    n_ttis = 100000
    
    delta_act = np.array([-1, 0, 1], dtype=np.int32)
    
    results = []
    
    print("\n=== Starting Python Latency Benchmark (100k TTIs, warm-up 1k excluded) ===")
    
    for N in n_users_list:
        print(f"\n--- Benchmarking N = {N} users ---")
        rng = np.random.RandomState(2000 + N)
        # Pre-generate random states of shape (57, N)
        S_const = rng.randn(57, N).astype(np.float32)
        S_onnx_const = S_const.T.copy() # (N, 57)
        ref_const = rng.randint(0, 16, size=N).astype(np.int32)
        
        # -------------------------------------------------------------
        # 1. NumPy Matrix-Multiply Benchmark
        # -------------------------------------------------------------
        for model_name, Wa in [("NR2", Wa_nr2), ("M1", Wa_m1)]:
            # Batched
            w1, b1 = Wa['w1'], Wa['b1']
            w2, b2 = Wa['w2'], Wa['b2']
            w3, b3 = Wa['w3'], Wa['b3']
            base_off = -2 if model_name == "NR2" else 0
            
            # Warmup
            for _ in range(n_warm):
                h1 = np.maximum(0.0, w1 @ S_const + b1)
                h2 = np.maximum(0.0, w2 @ h1 + b2)
                out = w3 @ h2 + b3
                a = np.argmax(out, axis=0)
                cqi = np.clip(ref_const + base_off + delta_act[a], 0, 15)
                
            times = np.zeros(n_ttis, dtype=np.float64)
            for it in range(n_ttis):
                t0 = time.perf_counter_ns()
                h1 = np.maximum(0.0, w1 @ S_const + b1)
                h2 = np.maximum(0.0, w2 @ h1 + b2)
                out = w3 @ h2 + b3
                a = np.argmax(out, axis=0)
                cqi = np.clip(ref_const + base_off + delta_act[a], 0, 15)
                times[it] = (time.perf_counter_ns() - t0) / 1000.0 # us
                
            med = float(np.median(times))
            p99 = float(np.percentile(times, 99))
            p999 = float(np.percentile(times, 99.9))
            mx = float(np.max(times))
            print(f"NumPy {model_name:4s} [batched , N={N:3d}] ... median: {med:6.2f} us | p99: {p99:6.2f} us | p99.9: {p999:6.2f} us | max: {mx:6.2f} us")
            results.append({
                'scheme': model_name,
                'runtime': 'NumPy',
                'mode': 'batched',
                'users': N,
                'median_us': med,
                'p99_us': p99,
                'p99_9_us': p999,
                'max_us': mx
            })
            
            # Per-user loop
            # Slice columns for per-user
            S_cols = [S_const[:, i:i+1] for i in range(N)]
            cqi_vec = np.zeros(N, dtype=np.int32)
            for _ in range(n_warm):
                for i in range(N):
                    h1_i = np.maximum(0.0, w1 @ S_cols[i] + b1)
                    h2_i = np.maximum(0.0, w2 @ h1_i + b2)
                    out_i = w3 @ h2_i + b3
                    a_i = np.argmax(out_i)
                    cqi_vec[i] = max(0, min(15, ref_const[i] + base_off + delta_act[a_i]))
                    
            times = np.zeros(n_ttis, dtype=np.float64)
            for it in range(n_ttis):
                t0 = time.perf_counter_ns()
                for i in range(N):
                    h1_i = np.maximum(0.0, w1 @ S_cols[i] + b1)
                    h2_i = np.maximum(0.0, w2 @ h1_i + b2)
                    out_i = w3 @ h2_i + b3
                    a_i = np.argmax(out_i)
                    cqi_vec[i] = max(0, min(15, ref_const[i] + base_off + delta_act[a_i]))
                times[it] = (time.perf_counter_ns() - t0) / 1000.0
                
            med = float(np.median(times))
            p99 = float(np.percentile(times, 99))
            p999 = float(np.percentile(times, 99.9))
            mx = float(np.max(times))
            print(f"NumPy {model_name:4s} [per_user, N={N:3d}] ... median: {med:6.2f} us | p99: {p99:6.2f} us | p99.9: {p999:6.2f} us | max: {mx:6.2f} us")
            results.append({
                'scheme': model_name,
                'runtime': 'NumPy',
                'mode': 'per_user',
                'users': N,
                'median_us': med,
                'p99_us': p99,
                'p99_9_us': p999,
                'max_us': mx
            })
            
        # -------------------------------------------------------------
        # 2. ONNX Runtime Benchmark
        # -------------------------------------------------------------
        for model_name, sess in [("NR2", sess_nr2), ("M1", sess_m1)]:
            base_off = -2 if model_name == "NR2" else 0
            
            # Batched
            inp_dict = {'in': S_onnx_const}
            for _ in range(n_warm):
                out = sess.run(None, inp_dict)[0]
                a = np.argmax(out, axis=1)
                cqi = np.clip(ref_const + base_off + delta_act[a], 0, 15)
                
            times = np.zeros(n_ttis, dtype=np.float64)
            for it in range(n_ttis):
                t0 = time.perf_counter_ns()
                out = sess.run(None, inp_dict)[0]
                a = np.argmax(out, axis=1)
                cqi = np.clip(ref_const + base_off + delta_act[a], 0, 15)
                times[it] = (time.perf_counter_ns() - t0) / 1000.0
                
            med = float(np.median(times))
            p99 = float(np.percentile(times, 99))
            p999 = float(np.percentile(times, 99.9))
            mx = float(np.max(times))
            print(f"ONNX  {model_name:4s} [batched , N={N:3d}] ... median: {med:6.2f} us | p99: {p99:6.2f} us | p99.9: {p999:6.2f} us | max: {mx:6.2f} us")
            results.append({
                'scheme': model_name,
                'runtime': 'onnxruntime',
                'mode': 'batched',
                'users': N,
                'median_us': med,
                'p99_us': p99,
                'p99_9_us': p999,
                'max_us': mx
            })
            
            # Per-user loop
            S_rows = [S_onnx_const[i:i+1, :] for i in range(N)]
            cqi_vec = np.zeros(N, dtype=np.int32)
            for _ in range(n_warm):
                for i in range(N):
                    out_i = sess.run(None, {'in': S_rows[i]})[0]
                    a_i = np.argmax(out_i[0])
                    cqi_vec[i] = max(0, min(15, ref_const[i] + base_off + delta_act[a_i]))
                    
            times = np.zeros(n_ttis, dtype=np.float64)
            for it in range(n_ttis):
                t0 = time.perf_counter_ns()
                for i in range(N):
                    out_i = sess.run(None, {'in': S_rows[i]})[0]
                    a_i = np.argmax(out_i[0])
                    cqi_vec[i] = max(0, min(15, ref_const[i] + base_off + delta_act[a_i]))
                times[it] = (time.perf_counter_ns() - t0) / 1000.0
                
            med = float(np.median(times))
            p99 = float(np.percentile(times, 99))
            p999 = float(np.percentile(times, 99.9))
            mx = float(np.max(times))
            print(f"ONNX  {model_name:4s} [per_user, N={N:3d}] ... median: {med:6.2f} us | p99: {p99:6.2f} us | p99.9: {p999:6.2f} us | max: {mx:6.2f} us")
            results.append({
                'scheme': model_name,
                'runtime': 'onnxruntime',
                'mode': 'per_user',
                'users': N,
                'median_us': med,
                'p99_us': p99,
                'p99_9_us': p999,
                'max_us': mx
            })
            
    df_py = pd.DataFrame(results)
    py_res_path = os.path.join(dataset_dir, "a3b_python_results.csv")
    df_py.to_csv(py_res_path, index=False)
    print(f"\nPython results saved to {py_res_path}")

if __name__ == "__main__":
    run_python_benchmark()
