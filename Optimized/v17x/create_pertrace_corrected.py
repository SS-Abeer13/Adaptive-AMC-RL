import csv
import scipy.io as sio
import os

mat_path = 'Optimized/v17x/Dataset/g2_cross_check_results.mat'
orig_csv = 'Optimized/v17x/Dataset/presub/pertrace.csv'
corr_csv = 'Optimized/v17x/Dataset/presub/pertrace_corrected.csv'

# Load cross-check results: vals_6_10_cal (size 5 x 500)
mat = sio.loadmat(mat_path)
vals_6_10_cal = mat['res']['vals_6_10_cal'][0, 0]

print(f"Loaded vals_6_10_cal shape: {vals_6_10_cal.shape}")
for s_idx in range(6, 11):
    sp = s_idx - 6
    print(f"Seed {s_idx} mean (first 300 traces): {vals_6_10_cal[sp, :300].mean():.6f}")

# Read original pertrace.csv and substitute G2 NRG10 seeds 6..10
replaced_count = 0
total_rows = 0

with open(orig_csv, 'r', newline='', encoding='utf-8') as fin, \
     open(corr_csv, 'w', newline='', encoding='utf-8') as fout:
    reader = csv.reader(fin)
    writer = csv.writer(fout)
    
    header = next(reader)
    writer.writerow(header)
    
    for row in reader:
        total_rows += 1
        ts, scheme, seed_str, trace_str, val_str = row
        seed = int(seed_str)
        trace = int(trace_str)
        
        if ts == 'G2' and scheme == 'NRG10' and 6 <= seed <= 10:
            sp = seed - 6
            corr_val = vals_6_10_cal[sp, trace - 1]
            writer.writerow([ts, scheme, seed_str, trace_str, f"{corr_val:.6f}"])
            replaced_count += 1
        else:
            writer.writerow(row)

print(f"Total rows: {total_rows}, Replaced G2 rows: {replaced_count}")
assert replaced_count == 5 * 300, f"Expected 1500 replacements, got {replaced_count}"
print(f"Successfully generated {corr_csv}")
