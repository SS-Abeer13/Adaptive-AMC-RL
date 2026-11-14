import pandas as pd
import numpy as np

def run():
    df = pd.read_csv('Optimized/v17x/Dataset/presub/actions.csv')

    def sp_class(s):
        if s < 10: return '<10'
        elif s <= 20: return '10-20'
        else: return '>20'

    df['sp_class'] = df['speed_mps'].map(sp_class)

    # In actions.csv: action is sent(u) - ref(u).
    # Intended offsets are -3, -2, -1 corresponding to delta in {-1, 0, +1}.
    # action == 0 occurs when ref == 1 (clipped at min CQI 1).
    delta_map = {-3: -1, -2: 0, -1: 1}
    df_unclipped = df[df['action'].isin([-3, -2, -1])].copy()
    df_unclipped['delta'] = df_unclipped['action'].map(delta_map)

    bins = [
        ('all', lambda d: pd.Series(True, index=d.index)),
        ('busy=0', lambda d: d['busy'] == 0),
        ('busy>=1', lambda d: d['busy'] >= 1),
        ('slack<=0.6', lambda d: (d['has_packet'] == 1) & (d['slack_frac'] <= 0.6)),
        ('slack>0.6', lambda d: (d['has_packet'] == 1) & (d['slack_frac'] > 0.6)),
        ('speed<10', lambda d: d['sp_class'] == '<10'),
        ('speed10-20', lambda d: d['sp_class'] == '10-20'),
        ('speed>20', lambda d: d['sp_class'] == '>20')
    ]

    print('=== UNCLIPPED DELTA SHARES (SUMMING TO 100%) ===')
    print('{:<15} | {:<12} | {:<18} | {:<15} | {:<18}'.format('Bin', 'N decisions', 'delta = -1 (Cons)', 'delta = 0 (Neut)', 'delta = +1 (Aggr)'))
    print('-'*85)

    results = []
    for name, cond in bins:
        sub = df_unclipped[cond(df_unclipped)]
        n = len(sub)
        pct_m1 = (sub['delta'] == -1).mean() * 100
        pct_0  = (sub['delta'] == 0).mean() * 100
        pct_p1 = (sub['delta'] == 1).mean() * 100
        print('{:<15} | {:<12} | {:<15.2f} | {:<15.2f} | {:<15.2f}'.format(name, n, pct_m1, pct_0, pct_p1))
        results.append({
            'bin': name,
            'n_unclipped': n,
            'pct_minus1': pct_m1,
            'pct_zero': pct_0,
            'pct_plus1': pct_p1
        })

    print('\n=== OVERALL DECISIONS (INCLUDING FLOOR-CLIPPED action=0) ===')
    print('{:<15} | {:<10} | {:<14} | {:<14} | {:<14} | {:<14}'.format('Bin', 'N total', 'act=-3 (d=-1)', 'act=-2 (d=0)', 'act=-1 (d=+1)', 'act=0 (clip)'))
    print('-'*85)
    for name, cond in bins:
        sub = df[cond(df)]
        n = len(sub)
        p_m3 = (sub['action'] == -3).mean() * 100
        p_m2 = (sub['action'] == -2).mean() * 100
        p_m1 = (sub['action'] == -1).mean() * 100
        p_0  = (sub['action'] == 0).mean() * 100
        print('{:<15} | {:<10} | {:<14.2f} | {:<14.2f} | {:<14.2f} | {:<14.2f}'.format(name, n, p_m3, p_m2, p_m1, p_0))

    # Min / max over seeds for unclipped
    print('\n=== SEED VARIABILITY (MIN / MAX ACROSS 10 SEEDS) ===')
    for name, cond in bins:
        sub = df_unclipped[cond(df_unclipped)]
        seed_m1 = sub[sub['delta'] == -1].groupby(sub['seed']).size() / sub.groupby(sub['seed']).size() * 100
        seed_0  = sub[sub['delta'] == 0].groupby(sub['seed']).size() / sub.groupby(sub['seed']).size() * 100
        seed_p1 = sub[sub['delta'] == 1].groupby(sub['seed']).size() / sub.groupby(sub['seed']).size() * 100
        print('{:<15} | d=-1: [{:.2f}, {:.2f}] | d=0: [{:.2f}, {:.2f}] | d=+1: [{:.2f}, {:.2f}]'.format(
            name, seed_m1.min(), seed_m1.max(), seed_0.min(), seed_0.max(), seed_p1.min(), seed_p1.max()))

if __name__ == '__main__':
    run()
