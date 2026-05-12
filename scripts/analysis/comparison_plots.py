import warnings

import matplotlib.pyplot as plt
import numpy as np

from analysis.styling import COLOR_A, COLOR_B
from analysis.data_loading import (
    get_per_run_agent_field,
    get_per_run_pass_rates,
    get_per_run_tokens_total,
)

# ─── Comparison plots (A vs B) ────────────────────────────────────────────────

def plot_pass_rate_comparison(
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
    ax=None,
) -> None:
    """
    Box plot comparing per-run pass rates for A and B.
    Each box is built from N per-run pass rate values (one per run).
    The internal red line is the median; the blue dashed line is the mean.
    """
    if ax is None:
        _, ax = plt.subplots(figsize=(5, 4.5))

    rates_a = get_per_run_pass_rates(metrics_a)
    rates_b = get_per_run_pass_rates(metrics_b)
    _draw_boxplot(ax, rates_a, rates_b, label_a, label_b,
                  "Pass rate (%)", "Pass rate comparison", value_fmt=".1f")
    ax.set_ylim(-5, 110)


def plot_pass_rate_per_run_overlay(
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
    ax=None,
) -> None:
    """
    Two lines on the same axes: per-run pass rates for A and B.
    Shows run-to-run shape rather than just summary stats.
    """
    if ax is None:
        _, ax = plt.subplots(figsize=(7, 4))

    rates_a = get_per_run_pass_rates(metrics_a)
    rates_b = get_per_run_pass_rates(metrics_b)
    n = max(len(rates_a), len(rates_b))
    xs = np.arange(1, n + 1)

    if rates_a:
        ax.plot(xs[:len(rates_a)], rates_a, marker="o", color=COLOR_A,
                linewidth=1.5, markersize=5, label=label_a)
    if rates_b:
        ax.plot(xs[:len(rates_b)], rates_b, marker="s", color=COLOR_B,
                linewidth=1.5, markersize=5, linestyle="--", label=label_b)

    ax.set_xlabel("Run number")
    ax.set_ylabel("Pass rate (%)")
    ax.set_ylim(-5, 110)
    ax.set_xticks(xs)
    ax.set_title("Per-run pass rates")
    ax.legend(fontsize=8)


# ── Box plot helpers ──────────────────────────────────────────────────────────

def _draw_boxplot(ax, data_a, data_b, label_a, label_b, ylabel, title, value_fmt=".3f"):
    """
    Draw side-by-side box plots for two groups (A and B).

    Box layout:
      - Box spans Q1 (25th pct) to Q3 (75th pct)
      - Red solid line inside box = median (50th pct)
      - Blue dashed line = mean
      - Whiskers extend to min/max within 1.5×IQR; points beyond are outliers

    Annotations above each box show exact median and mean values.
    """
    positions = [1, 2]
    bp = ax.boxplot(
        [data_a, data_b],
        positions=positions,
        widths=0.45,
        patch_artist=True,
        showmeans=True,
        meanline=True,
        meanprops=dict(color="blue", linewidth=2, linestyle="--"),
        medianprops=dict(color="red", linewidth=2),
        whiskerprops=dict(linewidth=1.2),
        capprops=dict(linewidth=1.5),
        flierprops=dict(marker="D", markerfacecolor="gray",
                        markeredgecolor="none", markersize=5, alpha=0.7),
    )

    for patch, color in zip(bp["boxes"], [COLOR_A, COLOR_B]):
        patch.set_facecolor(color)
        patch.set_alpha(0.65)

    # Annotate median and mean above each box
    all_data = list(data_a) + list(data_b)
    data_range = max(all_data) - min(all_data) if len(all_data) > 1 else 1
    for data, pos in zip([data_a, data_b], positions):
        q3     = float(np.percentile(data, 75))
        median = float(np.median(data))
        mean   = float(np.mean(data))
        yoff   = q3 + data_range * 0.08
        ax.text(pos, yoff,
                f"med {median:{value_fmt}}\navg {mean:{value_fmt}}",
                ha="center", fontsize=7, linespacing=1.5,
                bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.7))

    ax.set_xticks(positions)
    ax.set_xticklabels([label_a, label_b])
    ax.set_ylabel(ylabel)
    ax.set_title(title, pad=20)


def plot_agent_cost_api_comparison(
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    1×2 box plot figure comparing instance_cost and api_calls for A vs B.

    Each box is built from N per-run averages (one data point per run).
    The box spans Q1–Q3; the red line is the median; the blue dashed line is the mean.
    Whiskers reach the most extreme non-outlier values (within 1.5×IQR).
    """
    fig, axes = plt.subplots(1, 2, figsize=(9, 4.5))
    fig.suptitle("Cost & API calls comparison (per-run averages)", fontsize=11)

    cost_a = get_per_run_agent_field(metrics_a, "instance_cost")
    cost_b = get_per_run_agent_field(metrics_b, "instance_cost")
    _draw_boxplot(axes[0], cost_a, cost_b, label_a, label_b,
                  "Instance cost (USD)", "Instance cost (USD)", value_fmt=".4f")

    api_a = get_per_run_agent_field(metrics_a, "api_calls")
    api_b = get_per_run_agent_field(metrics_b, "api_calls")
    _draw_boxplot(axes[1], api_a, api_b, label_a, label_b,
                  "API calls", "API calls", value_fmt=".1f")

    plt.tight_layout()


def plot_tokens_comparison(
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    1×3 box plot figure comparing tokens_sent, tokens_received, and tokens_total
    (= sent + received, derived) for A vs B.

    Each box is built from N per-run averages.
    """
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.5))
    fig.suptitle("Token usage comparison (per-run averages)", fontsize=11)

    sent_a = get_per_run_agent_field(metrics_a, "tokens_sent")
    sent_b = get_per_run_agent_field(metrics_b, "tokens_sent")
    _draw_boxplot(axes[0], sent_a, sent_b, label_a, label_b,
                  "Tokens sent", "Tokens sent", value_fmt=",.0f")

    recv_a = get_per_run_agent_field(metrics_a, "tokens_received")
    recv_b = get_per_run_agent_field(metrics_b, "tokens_received")
    _draw_boxplot(axes[1], recv_a, recv_b, label_a, label_b,
                  "Tokens received", "Tokens received", value_fmt=",.0f")

    total_a = get_per_run_tokens_total(metrics_a)
    total_b = get_per_run_tokens_total(metrics_b)
    _draw_boxplot(axes[2], total_a, total_b, label_a, label_b,
                  "Tokens total", "Tokens total", value_fmt=",.0f")

    plt.tight_layout()


def plot_pooled_cost_api_comparison(
    obs_a: dict, obs_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    1×2 box plot figure comparing pooled per-instance instance_cost and api_calls
    for A vs B. Each box is built from N_runs × M_instances individual observations.
    """
    n_a = len(obs_a.get("instance_cost", []))
    n_b = len(obs_b.get("instance_cost", []))
    fig, axes = plt.subplots(1, 2, figsize=(9, 4.5))
    fig.suptitle(
        f"Pooled cost & API calls comparison  ({label_a}: {n_a} obs, {label_b}: {n_b} obs)",
        fontsize=11,
    )

    _draw_boxplot(axes[0], obs_a["instance_cost"], obs_b["instance_cost"],
                  label_a, label_b, "Instance cost (USD)", "Instance cost (USD)", value_fmt=".4f")
    _draw_boxplot(axes[1], obs_a["api_calls"], obs_b["api_calls"],
                  label_a, label_b, "API calls", "API calls", value_fmt=".1f")
    plt.tight_layout()


def plot_pooled_tokens_comparison(
    obs_a: dict, obs_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    1×3 box plot figure comparing pooled per-instance token metrics for A vs B.
    Each box is built from N_runs × M_instances individual observations.
    """
    n_a = len(obs_a.get("tokens_sent", []))
    n_b = len(obs_b.get("tokens_sent", []))
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.5))
    fig.suptitle(
        f"Pooled token usage comparison  ({label_a}: {n_a} obs, {label_b}: {n_b} obs)",
        fontsize=11,
    )

    _draw_boxplot(axes[0], obs_a["tokens_sent"],     obs_b["tokens_sent"],
                  label_a, label_b, "Tokens sent",     "Tokens sent",     value_fmt=",.0f")
    _draw_boxplot(axes[1], obs_a["tokens_received"], obs_b["tokens_received"],
                  label_a, label_b, "Tokens received", "Tokens received", value_fmt=",.0f")
    _draw_boxplot(axes[2], obs_a["tokens_total"],    obs_b["tokens_total"],
                  label_a, label_b, "Tokens total",    "Tokens total",    value_fmt=",.0f")
    plt.tight_layout()


def plot_pooled_reasoning_tokens_comparison(
    obs_a: dict, obs_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    Standalone box plot comparing pooled per-instance reasoning_tokens_total for A vs B.

    Emits a warning naming which eval(s) are missing the field and returns
    without a plot if either side has no data.
    """
    reasoning_a = obs_a.get("reasoning_tokens_total", [])
    reasoning_b = obs_b.get("reasoning_tokens_total", [])

    missing = []
    if not reasoning_a:
        missing.append(label_a)
    if not reasoning_b:
        missing.append(label_b)
    if missing:
        warnings.warn(
            f"reasoning_tokens_total not found in: {', '.join(missing)} "
            "— skipping pooled reasoning tokens comparison plot"
        )
        return

    n_a, n_b = len(reasoning_a), len(reasoning_b)
    fig, ax = plt.subplots(figsize=(5, 4.5))
    fig.suptitle(
        f"Pooled reasoning tokens comparison  ({label_a}: {n_a} obs, {label_b}: {n_b} obs)",
        fontsize=11,
    )
    _draw_boxplot(ax, reasoning_a, reasoning_b,
                  label_a, label_b, "Reasoning tokens", "Reasoning tokens", value_fmt=",.0f")
    plt.tight_layout()


def plot_reasoning_tokens_comparison(
    metrics_a: dict, metrics_b: dict,
    label_a: str, label_b: str,
) -> None:
    """
    Single box plot comparing per-run reasoning_tokens_total averages for A vs B.

    reasoning_tokens_total is optional — present only for models that expose
    reasoning token counts.  If the field is absent from either metrics dict,
    a warning naming the missing eval(s) is emitted and no plot is produced.
    """
    values_a = get_per_run_agent_field(metrics_a, "reasoning_tokens_total")
    values_b = get_per_run_agent_field(metrics_b, "reasoning_tokens_total")

    missing = []
    if not values_a:
        missing.append(label_a)
    if not values_b:
        missing.append(label_b)
    if missing:
        warnings.warn(
            f"reasoning_tokens_total not found in: {', '.join(missing)} "
            "— skipping reasoning tokens comparison plot"
        )
        return

    fig, ax = plt.subplots(figsize=(5, 4.5))
    fig.suptitle("Reasoning tokens comparison (per-run averages)", fontsize=11)
    _draw_boxplot(ax, values_a, values_b, label_a, label_b,
                  "Reasoning tokens", "Reasoning tokens", value_fmt=",.0f")
    plt.tight_layout()