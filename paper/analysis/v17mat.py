"""Read v17 results_*.mat (MATLAB v7.3 / HDF5) with h5py: scheme names and per-seed x per-trace metrics."""
import h5py, numpy as np

def _str(f, ref):
    return ''.join(chr(c) for c in np.array(f[ref]).flatten())

def load(path):
    f = h5py.File(path, 'r')
    r = f['results']
    schemes = [_str(f, x) for x in np.array(r['schemes']).flatten()]
    M = r['metrics']
    out = {}
    for key in ['primary', 'cell_tp', 'ontime', 'jain', 'edge_tp', 'act_hist']:
        refs = np.array(M[key]).flatten()
        out[key] = {}
        for s, ref in zip(schemes, refs):
            a = np.array(f[ref])
            # MATLAB stores column-major; h5py returns transposed -> back to (seeds, traces)
            out[key][s] = a.T
    curves = {k: np.array(r[k]).T for k in ['learning_curves', 'entropy_curves'] if k in r}
    return schemes, out, curves, f
