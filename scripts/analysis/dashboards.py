import json
import sys
import warnings
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from bisect import bisect_left
from scipy import stats
import pandas as pd
from typing import List


from analysis.data_loading import (
    load_metrics,
    load_instance_observations,
    validate_metrics,
    load_instance_observations_by_id,
    load_filtered_metrics,
)
from analysis.single_eval_plots import (
    plot_pass_rate_distribution,
    plot_agent_cost_api_per_run,
    plot_agent_tokens_per_run,
    plot_reasoning_tokens_single,
    plot_pooled_cost_api_single,
    plot_pooled_tokens_single,
    plot_pooled_reasoning_tokens_single,
    plot_cost_vs_tokens_scatter,
    print_summary_table,
)
from analysis.comparison_plots import (
    plot_pass_rate_comparison,
    plot_pass_rate_per_run_overlay,
    plot_agent_cost_api_comparison,
    plot_tokens_comparison,
    plot_reasoning_tokens_comparison,
    plot_pooled_cost_api_comparison,
    plot_pooled_tokens_comparison,
    plot_pooled_reasoning_tokens_comparison,
)
from analysis.stat_significance import (
    print_stat_significance_overall,
    print_stat_significance_per_instance,
)

# ─── Dashboard orchestrators ──────────────────────────────────────────────────

def build_single_report(dirpath_a, label_a: str, instance_ids=None) -> None:
    metrics = load_metrics(dirpath_a)

    # When filtering, recompute per-run stats from raw results for figures 1–3
    eff_metrics = (
        load_filtered_metrics(dirpath_a, instance_ids) if instance_ids is not None else metrics
    )

    # keep original for validation
    for w in validate_metrics(metrics, label_a):
        warnings.warn(w, stacklevel=2)

    fig1, ax1 = plt.subplots(figsize=(11, 3.5))
    # was: metrics
    plot_pass_rate_distribution(eff_metrics, label_a, ax=ax1)
    plt.tight_layout()
    plt.show()

    # was: metrics
    plot_agent_cost_api_per_run(eff_metrics, label_a)
    plt.show()

    # was: metrics
    plot_agent_tokens_per_run(eff_metrics, label_a)
    plt.show()

    plot_reasoning_tokens_single(metrics, label_a)
    plt.show()

    obs = load_instance_observations(dirpath_a, instance_ids=instance_ids)
    plot_pooled_cost_api_single(obs, label_a)
    plt.show()

    plot_pooled_tokens_single(obs, label_a)
    plt.show()

    plot_pooled_reasoning_tokens_single(obs, label_a)
    plt.show()

    fig6, ax6 = plt.subplots(figsize=(5, 4))
    # was: metrics
    plot_cost_vs_tokens_scatter(eff_metrics, label_a, ax=ax6)
    plt.tight_layout()
    plt.show()

    # keep original (reads pooled/run_variability)
    print()
    print_summary_table(metrics, label_a)


def build_comparison_report(
    dirpath_a, label_a: str,
    dirpath_b, label_b: str,
    instance_ids=None,
) -> None:
    metrics_a = load_metrics(dirpath_a)
    metrics_b = load_metrics(dirpath_b)

    # When filtering, recompute per-run stats from raw results for figures 1–3
    if instance_ids is not None:
        eff_metrics_a = load_filtered_metrics(dirpath_a, instance_ids)
        eff_metrics_b = load_filtered_metrics(dirpath_b, instance_ids)
    else:
        eff_metrics_a, eff_metrics_b = metrics_a, metrics_b

    for w in validate_metrics(metrics_a, label_a) + validate_metrics(metrics_b, label_b):
        warnings.warn(w, stacklevel=2)

    # Figure 1: pass rate
    fig1, (ax1a, ax1b) = plt.subplots(1, 2, figsize=(12, 4))
    plot_pass_rate_comparison(eff_metrics_a, eff_metrics_b, label_a, label_b, ax=ax1a)
    plot_pass_rate_per_run_overlay(eff_metrics_a, eff_metrics_b, label_a, label_b, ax=ax1b)
    plt.tight_layout()
    plt.show()

    # Figure 2: cost & API calls (per-run averages)
    plot_agent_cost_api_comparison(eff_metrics_a, eff_metrics_b, label_a, label_b)
    plt.show()

    # Figure 3: token usage (per-run averages)
    plot_tokens_comparison(eff_metrics_a, eff_metrics_b, label_a, label_b)
    plt.show()

    # Figure 3b: reasoning tokens (optional — skipped with warning if absent)
    plot_reasoning_tokens_comparison(metrics_a, metrics_b, label_a, label_b)
    plt.show()

    # Figures 4–5: pooled observations (already filtered via instance_ids)
    obs_a = load_instance_observations(dirpath_a, instance_ids=instance_ids)
    obs_b = load_instance_observations(dirpath_b, instance_ids=instance_ids)
    plot_pooled_cost_api_comparison(obs_a, obs_b, label_a, label_b)
    plt.show()

    plot_pooled_tokens_comparison(obs_a, obs_b, label_a, label_b)
    plt.show()

    plot_pooled_reasoning_tokens_comparison(obs_a, obs_b, label_a, label_b)
    plt.show()

    # Summary tables — always use pre-aggregated values (pooled/run_variability not filterable)
    print()
    print_summary_table(metrics_a, label_a)
    print()
    print_summary_table(metrics_b, label_b)
    print()

    # Statistical significance
    print_stat_significance_overall(obs_a, obs_b, eff_metrics_a, eff_metrics_b, label_a, label_b)
    print()
    obs_by_id_a = load_instance_observations_by_id(dirpath_a, instance_ids=instance_ids)
    obs_by_id_b = load_instance_observations_by_id(dirpath_b, instance_ids=instance_ids)
    print_stat_significance_per_instance(obs_by_id_a, obs_by_id_b, label_a, label_b)

