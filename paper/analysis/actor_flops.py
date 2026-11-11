"""Hardware-independent cost of one actor forward pass (one user decision).

Counts multiply-accumulates (MACs) of the Gemm/MatMul layers of the exported actor
networks (Optimized/v17x/Dataset/actor_*.onnx; numerical equivalence with the
MATLAB network is checked in REPORT_a3b.txt section 2). FLOPs = 2 MACs + bias adds
+ ReLUs. Feature construction and the base-rule lookup are not counted.
Run: python3 actor_flops.py   (needs the onnx package)
"""
import os, csv, onnx
from onnx import numpy_helper
here = os.path.dirname(os.path.abspath(__file__)); D = os.path.join(here, '..', '..', 'Optimized', 'v17x', 'Dataset')
rows = []
for tag in ['m1', 'nr2']:
    m = onnx.load(os.path.join(D, f'actor_{tag}.onnx'))
    init = {i.name: numpy_helper.to_array(i) for i in m.graph.initializer}
    W = [v for v in init.values() if v.ndim == 2]; Bv = [v for v in init.values() if v.ndim == 1]
    macs = sum(w.size for w in W); relu = sum(w.shape[1] for w in W[:-1])
    rows.append(dict(actor=tag, layers='x'.join([str(W[0].shape[0])] + [str(w.shape[1]) for w in W]),
                     macs=macs, flops=2 * macs + sum(b.size for b in Bv) + relu, params=sum(v.size for v in init.values())))
os.makedirs(os.path.join(here, 'out'), exist_ok=True)
with open(os.path.join(here, 'out', 'actor_flops.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(rows)
