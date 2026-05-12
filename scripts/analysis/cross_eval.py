import warnings

import numpy as np
import pandas as pd

from analysis.data_loading import (
    _mannwhitneyu_pvalue,
    _vd_a12,
    get_per_run_pass_rates,
    load_filtered_metrics,
    load_instance_observations,
    load_metrics,
)

_ALPHA = 0.05


def build_cross_eval_comparison_df(
    entries,
    metric: str = "pass_rate",
    instance_ids=None,
) -> pd.DataFrame:
    """
    Build a summary comparison table across multiple (strategy, model) eval pairs.

    entries: list of (strategy_label, model_label, dir_s0, dir_sX)
             Set dir_sX to None to produce an N/A row for that entry.

    metric = "pass_rate"
        Uses per-run pass-rate values; displays mean.
    metric = any agent field ("instance_cost", "api_calls", "tokens_sent",
                              "tokens_received", "tokens_total")
        Uses pooled per-instance observations; displays median.

    instance_ids: optional list of instance IDs to restrict both dirs to.
        Pass the 20 common benchmark IDs to ensure comparability when one dir
        contains more instances than the other (e.g. a 47-benchmark run vs 20).
        For pass_rate, uses load_filtered_metrics; for agent fields, filters
        load_instance_observations.

    Returns a DataFrame with columns:
        strategy, model, val_s0, val_sX, delta, p_value, A12, magnitude, significant

    A12 = P(s0 > sX): A12 > 0.5 means the baseline tends to produce larger values.
    Entries whose dir_sX is None or whose directory is missing yield N/A rows.
    """
    _NA = "N/A"
    rows = []
    for strategy, model, dir_s0, dir_sX in entries:
        if dir_sX is None:
            warnings.warn(f"[{strategy} / {model}] dir_sX is None — skipping stats")
            rows.append((strategy, model, _NA, _NA, _NA, _NA, _NA, _NA, _NA))
            continue

        try:
            if metric == "pass_rate":
                if instance_ids is not None:
                    data_a = get_per_run_pass_rates(load_filtered_metrics(dir_s0, instance_ids))
                    data_b = get_per_run_pass_rates(load_filtered_metrics(dir_sX, instance_ids))
                else:
                    data_a = get_per_run_pass_rates(load_metrics(dir_s0))
                    data_b = get_per_run_pass_rates(load_metrics(dir_sX))
                val_a = float(np.mean(data_a))
                val_b = float(np.mean(data_b))
            else:
                data_a = load_instance_observations(dir_s0, instance_ids=instance_ids)[metric]
                data_b = load_instance_observations(dir_sX, instance_ids=instance_ids)[metric]
                val_a = float(np.median(data_a))
                val_b = float(np.median(data_b))
        except FileNotFoundError as exc:
            warnings.warn(f"[{strategy} / {model}] {exc} — skipping stats")
            rows.append((strategy, model, _NA, _NA, _NA, _NA, _NA, _NA, _NA))
            continue

        delta = val_b - val_a
        p = _mannwhitneyu_pvalue(data_a, data_b)
        significant = p < _ALPHA
        if significant:
            a12, mag = _vd_a12(data_a, data_b)
        else:
            a12 = _NA
            mag = _NA

        rows.append((strategy, model, val_a, val_b, delta, p, a12, mag, significant))

    return pd.DataFrame(rows, columns=[
        "strategy", "model",
        "val_s0", "val_sX",
        "delta", "p_value", "A12", "magnitude", "significant",
    ])
