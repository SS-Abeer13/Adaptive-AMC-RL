"""train_r1_gbt.py
Trains 7 HistGradientBoostingRegressor models for Stage r1_gbt (Amendment 8, Freeze v9).
Spec: paper/proposals/R_presub_prereg.md §3.
"""
import sys, os, hashlib, joblib
import numpy as np
import scipy.io as sio
from sklearn.ensemble import HistGradientBoostingRegressor

def train(calib_mat, joblib_out, trees_mat, hash_out):
    print(f"Loading calibration data from {calib_mat}...")
    try:
        mat = sio.loadmat(calib_mat)
    except Exception:
        import h5py
        f = h5py.File(calib_mat, 'r')
        mat = {k: np.array(f[k]) for k in f.keys()}

    X = np.asarray(mat['X'], dtype=np.float64)
    # If transposed from MATLAB, ensure shape is (N, 19)
    if X.shape[1] != 19 and X.shape[0] == 19:
        X = X.T
    Y = np.asarray(mat['Y'], dtype=np.float64) # shape (N, 7) or (7, N)
    if Y.shape[1] != 7 and Y.shape[0] == 7:
        Y = Y.T

    N_samples = X.shape[0]
    print(f"Training data shape: X={X.shape}, Y={Y.shape}")
    assert X.shape[1] == 19, f"Expected 19 features, got {X.shape[1]}"
    assert Y.shape[1] == 7, f"Expected 7 actions, got {Y.shape[1]}"

    models = []
    trees_export = []

    for a in range(7):
        print(f"Fitting model {a+1}/7 for offset {a-4:+d}...")
        y_a = Y[:, a]
        m = HistGradientBoostingRegressor(
            max_iter=300,
            learning_rate=0.05,
            max_leaf_nodes=31,
            min_samples_leaf=40,
            early_stopping=False,
            random_state=0
        )
        m.fit(X, y_a)
        models.append(m)

        # Export tree predictors
        tree_list = []
        for pred in m._predictors:
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

        trees_export.append({
            'baseline': float(m._baseline_prediction),
            'trees': tree_list
        })

    # Save joblib
    print(f"Saving joblib models to {joblib_out}...")
    joblib.dump(models, joblib_out)

    # Compute SHA-256 hash
    sha256 = hashlib.sha256(open(joblib_out, 'rb').read()).hexdigest()
    print(f"SHA-256: {sha256}")
    with open(hash_out, 'w', encoding='utf-8') as f:
        f.write(f"{sha256}  {os.path.basename(joblib_out)}\n")

    # Equivalence check data
    n_eq = min(1000, N_samples)
    X_eq = X[:n_eq]
    Y_pred_sk = np.column_stack([m.predict(X_eq) for m in models])

    # Save trees and equivalence data for MATLAB
    print(f"Saving trees struct to {trees_mat}...")
    # Package into cell array of structs for clean MATLAB load
    sio.savemat(trees_mat, {
        'trees_export': trees_export,
        'X_equiv': X_eq,
        'Y_pred_sk': Y_pred_sk,
        'sha256': sha256
    })
    print("GBT training and export complete.")

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print("Usage: python train_r1_gbt.py <calib_mat> <joblib_out> <trees_mat> <hash_out>")
        sys.exit(1)
    train(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
