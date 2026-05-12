from typing import List

import numpy as np
import pandas as pd

from analysis.data_loading import (
    _agent_id_to_eval_id,
    _mannwhitneyu_pvalue,
    _vd_a12,
    get_per_run_pass_rates,
    load_instance_pass_rates_by_id,
)

# ─── Statistical significance tables (comparison mode only) ───────────────────
_ALPHA = 0.05   # significance threshold

_STAT_AGENT_FIELDS = [
    ("instance_cost",   "${:.4f}",    "${:.4f}"),
    ("api_calls",       "{:.1f}",     "{:.1f}"),
    ("tokens_sent",     "{:,.0f}",    "{:,.0f}"),
    ("tokens_received", "{:,.0f}",    "{:,.0f}"),
    ("tokens_total",    "{:,.0f}",    "{:,.0f}"),
    # ("reasoning_tokens_total",    "{:,.0f}",    "{:,.0f}"),
]


def _stat_row(metric, data_a, data_b, med_fmt_a, med_fmt_b):
    """Compute one row of stats: (metric, n_a, n_b, med_a_str, med_b_str, p_str, a12_str, mag_str)."""
    n_a = len(data_a)
    n_b = len(data_b)
    med_a = float(np.median(data_a))
    med_b = float(np.median(data_b))
    p = _mannwhitneyu_pvalue(data_a, data_b)
    if p < _ALPHA:
        a12, mag = _vd_a12(data_a, data_b)
        a12_str = f"{a12:.2f}"
    else:
        a12_str = "-"
        mag = "-"
    return (metric, n_a, n_b,
            med_fmt_a.format(med_a), med_fmt_b.format(med_b),
            f"{p:.3f}", a12_str, mag)


def print_stat_significance_overall(
    obs_a: dict, obs_b: dict,
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    Print a single table of Wilcoxon rank-sum p-values and Vargha-Delaney A12
    effect sizes for all metrics, comparing A vs B.

    pass_rate:     uses per-run values  (N observations per side)
    agent metrics: uses pooled per-instance observations (N×M per side)

    Interpretation:
      p < 0.05 → statistically significant; A12 and magnitude are shown.
      p ≥ 0.05 → not significant; A12 shown as '-'.
      A12 > 0.5 → A tends to produce larger values than B.
    """
    W = 90
    print()
    print(f"{'─'*W}")
    print(f"  Statistical significance: {label_a} vs {label_b}  "
          f"(Wilcoxon rank-sum, α={_ALPHA})")
    print(f"{'─'*W}")
    hdr = f"  {'metric':<18} {'n_A':>4} {'n_B':>4}  {'med_A':>13} {'med_B':>13}  "
    hdr += f"{'p-value':>8}  {'A^12':>5}  magnitude"
    print(hdr)
    print(f"{'─'*W}")

    # pass_rate row
    rates_a = get_per_run_pass_rates(metrics_a)
    rates_b = get_per_run_pass_rates(metrics_b)
    row = _stat_row("pass_rate", rates_a, rates_b, "{:.1f}%", "{:.1f}%")
    _print_stat_row(row)

    # agent metric rows
    for field, fmt_a, fmt_b in _STAT_AGENT_FIELDS:
        row = _stat_row(field, obs_a[field], obs_b[field], fmt_a, fmt_b)
        _print_stat_row(row)

    print(f"{'─'*W}")
    print(f"  Note: pass_rate n = number of runs; agent metrics n = runs × instances per run.")
    print(f"  A^12 > 0.5 → {label_a} produces larger values on average.")


def _print_stat_row(row):
    metric, n_a, n_b, med_a, med_b, p_str, a12_str, mag_str = row
    print(f"  {metric:<18} {n_a:>4} {n_b:>4}  {med_a:>13} {med_b:>13}  "
          f"{p_str:>8}  {a12_str:>5}  {mag_str}")


def _stat_df_row(name, data_a, data_b):
    """
    Compute one DataFrame row.
    Returns: (name, n_a, n_b, med_a, med_b, p_value, a12_or_nan, magnitude, significant)
    A12 is NaN when p ≥ α so pandas renders it cleanly as NaN instead of '-'.
    """
    n_a = len(data_a)
    n_b = len(data_b)
    med_a = float(np.median(data_a))
    med_b = float(np.median(data_b))
    p = _mannwhitneyu_pvalue(data_a, data_b)
    significant = p < _ALPHA
    if significant:
        a12, mag = _vd_a12(data_a, data_b)
    else:
        a12 = float("nan")
        mag = "-"
    return (name, n_a, n_b, med_a, med_b, p, a12, mag, significant)


def get_stat_significance_overall_df(
    obs_a: dict, obs_b: dict,
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
) -> "pd.DataFrame":
    """
    Return a DataFrame with one row per metric (pass_rate + all agent metrics).

    Columns: metric, n_A, n_B, med_A, med_B, p_value, A12, magnitude, significant
    All numeric columns are stored as floats for easy filtering and styling.
    A12 is NaN when p ≥ α.
    """
    rows = []
    rates_a = get_per_run_pass_rates(metrics_a)
    rates_b = get_per_run_pass_rates(metrics_b)
    rows.append(_stat_df_row("pass_rate", rates_a, rates_b))
    for field, _, _ in _STAT_AGENT_FIELDS:
        rows.append(_stat_df_row(field, obs_a[field], obs_b[field]))
    return pd.DataFrame(
        rows,
        columns=["metric", "n_A", "n_B", "med_A", "med_B", "p_value", "A12", "magnitude", "significant"],
    )


def get_stat_significance_per_instance_df(
    obs_by_id_a: dict, obs_by_id_b: dict,
    field: str,
) -> "pd.DataFrame":
    """
    Return a DataFrame with one row per instance_id for a single metric `field`.

    Columns: instance_id, n_A, n_B, med_A, med_B, p_value, A12, magnitude, significant
    """
    rows = []
    for iid in sorted(set(obs_by_id_a) | set(obs_by_id_b)):
        data_a = obs_by_id_a.get(iid, {}).get(field, [])
        data_b = obs_by_id_b.get(iid, {}).get(field, [])
        if not data_a or not data_b:
            continue
        rows.append(_stat_df_row(iid, data_a, data_b))
    return pd.DataFrame(
        rows,
        columns=["instance_id", "n_A", "n_B", "med_A", "med_B", "p_value", "A12", "magnitude", "significant"],
    )

def get_per_instance_pass_rate_df(
    dir_a: str,
    dir_b: str,
    instance_ids: List[str] = None,
) -> pd.DataFrame:
    """
    Per-instance pass rate comparison.

    For each instance_id present in both dirs, collects N binary outcomes
    (0/1) per side across all runs, then runs Wilcoxon rank-sum + A12.

    Columns: instance_id, n_A, n_B, pass_rate_A_%, pass_rate_B_%,
             p_value, A12, magnitude, significant
    """
    outcomes_a = load_instance_pass_rates_by_id(dir_a, instance_ids)
    outcomes_b = load_instance_pass_rates_by_id(dir_b, instance_ids)

    rows = []
    for iid in sorted(set(outcomes_a) | set(outcomes_b)):
        eval_iid = _agent_id_to_eval_id(iid)
        data_a = outcomes_a.get(iid, [])
        data_b = outcomes_b.get(iid, [])
        if not data_a or not data_b:
            continue
        n_a, n_b = len(data_a), len(data_b)
        rate_a = float(np.mean(data_a)) * 100
        rate_b = float(np.mean(data_b)) * 100
        p = _mannwhitneyu_pvalue(data_a, data_b)
        significant = p < _ALPHA
        if significant:
            a12, mag = _vd_a12(data_a, data_b)
        else:
            a12, mag = float("nan"), "-"
        rows.append((iid, n_a, n_b, rate_a, rate_b, p, a12, mag, significant, eval_iid))

    return pd.DataFrame(rows, columns=[
        "instance_id", "n_A", "n_B",
        "pass_rate_A_%", "pass_rate_B_%",
        "p_value", "A12", "magnitude", "significant",
        "eval_instance_id",
    ])


def print_stat_significance_per_instance(
    obs_by_id_a: dict, obs_by_id_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    Print one table per agent metric, with a row per instance_id.
    For each instance, compares the N per-run values from A vs B.
    """
    all_ids = sorted(set(obs_by_id_a) | set(obs_by_id_b))
    W = 90

    for field, fmt_a, fmt_b in _STAT_AGENT_FIELDS:
        print()
        print(f"{'─'*W}")
        print(f"  Per-instance: {field}  |  {label_a} vs {label_b}  "
              f"(Wilcoxon rank-sum, α={_ALPHA})")
        print(f"{'─'*W}")
        hdr = f"  {'instance_id':<36} {'n_A':>4} {'n_B':>4}  {'med_A':>12} {'med_B':>12}  "
        hdr += f"{'p-value':>8}  {'A^12':>5}  magnitude"
        print(hdr)
        print(f"{'─'*W}")

        for iid in all_ids:
            data_a = obs_by_id_a.get(iid, {}).get(field, [])
            data_b = obs_by_id_b.get(iid, {}).get(field, [])
            if not data_a or not data_b:
                continue
            row = _stat_row(iid, data_a, data_b, fmt_a, fmt_b)
            _, n_a, n_b, med_a, med_b, p_str, a12_str, mag_str = row
            print(f"  {iid:<36} {n_a:>4} {n_b:>4}  {med_a:>12} {med_b:>12}  "
                  f"{p_str:>8}  {a12_str:>5}  {mag_str}")

        print(f"{'─'*W}")

