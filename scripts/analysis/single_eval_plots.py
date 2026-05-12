import matplotlib.pyplot as plt
import numpy as np

from analysis.styling import ALPHA_BAND, COLOR_A
from analysis.data_loading import (
    get_per_run_agent_field,
    get_per_run_tokens_total,
    get_run_numbers,
)

# ─── Single-eval plots ────────────────────────────────────────────────────────

def plot_pass_rate_distribution(
    metrics: dict,
    label: str,
    color: str = COLOR_A,
    ax=None,
) -> None:
    """
    Bar chart of per-run pass rates with avg ± std band.
    Anomalous runs (total_instances < n_instances_per_run) are marked with '*'.
    """
    if ax is None:
        _, ax = plt.subplots(figsize=(10, 3.5))

    expected   = metrics.get("n_instances_per_run")
    pr         = metrics.get("pass_rate", {})
    avg        = pr.get("avg")
    std        = pr.get("std")
    per_run    = pr.get("per_run", [])
    run_nums   = [r["run_number"] for r in per_run]
    pass_rates = [r["pass_rate"]  for r in per_run]
    totals     = [r["total"]      for r in per_run]

    xs = np.arange(len(run_nums))
    ax.bar(xs, pass_rates, color=color, alpha=0.75, width=0.6, zorder=3)

    for i, (rate, total) in enumerate(zip(pass_rates, totals)):
        if expected is not None and total < expected:
            ax.text(xs[i], rate + 1.5, "*", ha="center", color="crimson", fontsize=13, zorder=5)

    if avg is not None:
        ax.axhline(avg, color=color, linewidth=1.5, linestyle="--", label=f"avg = {avg:.1f}%")
    if avg is not None and std is not None:
        ax.axhspan(avg - std, avg + std, color=color, alpha=ALPHA_BAND, label=f"±std ({std:.1f}%)")

    ax.set_xticks(xs)
    ax.set_xticklabels([f"R{n}" for n in run_nums])
    ax.set_ylim(0, 110)
    ax.set_ylabel("Pass rate (%)")
    ax.set_title(f"{label} — pass rate per run")
    ax.legend(fontsize=8)

    n_inst = metrics.get("n_instances_per_run", "?")
    ax.text(0.01, 0.97, f"M = {n_inst} instances/run  |  * = incomplete eval run",
            transform=ax.transAxes, va="top", fontsize=7, color="gray")


def _plot_field_line(ax, xs, values, avg_val, std_val, color, title):
    """Internal helper: draw a single per-run line with avg ± std band."""
    ax.plot(xs, values, marker="o", color=color, linewidth=1.5, markersize=5, zorder=3)
    if avg_val is not None:
        ax.axhline(avg_val, color=color, linestyle="--", linewidth=1, alpha=0.6)
    if avg_val is not None and std_val is not None:
        ax.axhspan(avg_val - std_val, avg_val + std_val, color=color, alpha=ALPHA_BAND)
    ax.set_title(title)


def plot_agent_cost_api_per_run(
    metrics: dict,
    label: str,
    color: str = COLOR_A,
) -> None:
    """
    1×2 subplot: per-run line charts for instance_cost and api_calls.

    instance_cost (not total_cost) is the primary cost metric: it is the
    marginal cost for a single instance's API calls, independent of session
    ordering.  total_cost accumulates context across multiple instances in the
    same session and is not comparable across different session sizes.
    """
    fields = ("instance_cost", "api_calls")
    titles = ("Instance cost (USD)", "API calls")

    fig, axes = plt.subplots(1, 2, figsize=(9, 3.5))
    fig.suptitle(f"{label} — cost & API calls per run", fontsize=11, y=1.02)

    run_nums = get_run_numbers(metrics)
    var      = metrics.get("run_variability", {})
    xs       = np.arange(len(run_nums))

    for ax, field, title in zip(axes, fields, titles):
        values  = get_per_run_agent_field(metrics, field)
        fv      = var.get(field, {})
        _plot_field_line(ax, xs, values, fv.get("avg_of_run_avgs"), fv.get("std_of_run_avgs"),
                         color, title)
        ax.set_xticks(xs)
        ax.set_xticklabels([f"R{n}" for n in run_nums])

    plt.tight_layout()


def plot_agent_tokens_per_run(
    metrics: dict,
    label: str,
    color: str = COLOR_A,
) -> None:
    """
    1×3 subplot: per-run line charts for tokens_sent, tokens_received, and
    tokens_total (= sent + received, derived — not stored in the JSON).

    Shaded band shows ±std_of_run_avgs for stored fields; for tokens_total
    the band is derived from the per-run totals using numpy.
    """
    run_nums      = get_run_numbers(metrics)
    var           = metrics.get("run_variability", {})
    xs            = np.arange(len(run_nums))
    tokens_total  = get_per_run_tokens_total(metrics)

    # Derive avg and std for tokens_total from per-run values
    total_avg = float(np.mean(tokens_total)) if tokens_total else None
    total_std = float(np.std(tokens_total, ddof=1)) if len(tokens_total) >= 2 else None

    FIELDS = [
        ("tokens_sent",     "Tokens sent",     get_per_run_agent_field(metrics, "tokens_sent"),
         var.get("tokens_sent", {}).get("avg_of_run_avgs"),
         var.get("tokens_sent", {}).get("std_of_run_avgs")),
        ("tokens_received", "Tokens received", get_per_run_agent_field(metrics, "tokens_received"),
         var.get("tokens_received", {}).get("avg_of_run_avgs"),
         var.get("tokens_received", {}).get("std_of_run_avgs")),
        ("tokens_total",    "Tokens total",    tokens_total,
         total_avg, total_std),
    ]

    fig, axes = plt.subplots(1, 3, figsize=(13, 3.5))
    fig.suptitle(f"{label} — tokens per run", fontsize=11, y=1.02)

    for ax, (_, title, values, avg_val, std_val) in zip(axes, FIELDS):
        _plot_field_line(ax, xs, values, avg_val, std_val, color, title)
        ax.set_xticks(xs)
        ax.set_xticklabels([f"R{n}" for n in run_nums])

    plt.tight_layout()


def _draw_single_boxplot(ax, data, color, ylabel, title, value_fmt=".3f"):
    """
    Single-group boxplot over pooled per-instance observations.

    Box spans Q1–Q3; red solid line = median; blue dashed line = mean.
    Whiskers extend to the most extreme non-outlier values (1.5×IQR).
    """
    bp = ax.boxplot(
        [data], positions=[1], widths=0.45,
        patch_artist=True,
        showmeans=True, meanline=True,
        meanprops=dict(color="blue", linewidth=2, linestyle="--"),
        medianprops=dict(color="red", linewidth=2),
        whiskerprops=dict(linewidth=1.2),
        capprops=dict(linewidth=1.5),
        flierprops=dict(marker="D", markerfacecolor="gray",
                        markeredgecolor="none", markersize=5, alpha=0.7),
    )
    bp["boxes"][0].set_facecolor(color)
    bp["boxes"][0].set_alpha(0.65)

    median     = float(np.median(data))
    mean       = float(np.mean(data))
    q3         = float(np.percentile(data, 75))
    data_range = max(data) - min(data) if len(data) > 1 else 1
    ax.text(1, q3 + data_range * 0.08,
            f"med {median:{value_fmt}}\navg {mean:{value_fmt}}",
            ha="center", fontsize=7, linespacing=1.5,
            bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.7))

    ax.set_xticks([])
    ax.set_ylabel(ylabel)
    ax.set_title(title)


def plot_pooled_cost_api_single(
    obs: dict,
    label: str,
    color: str = COLOR_A,
) -> None:
    """
    1×2 figure of pooled per-instance boxplots for instance_cost and api_calls.
    Each box is built from N_runs × M_instances individual observations.
    """
    n = len(obs.get("instance_cost", []))
    fig, axes = plt.subplots(1, 2, figsize=(9, 4.5))
    fig.suptitle(f"{label} — pooled instance cost & API calls ({n} observations)", fontsize=11)

    _draw_single_boxplot(axes[0], obs["instance_cost"], color,
                         "Instance cost (USD)", "Instance cost (USD)", value_fmt=".4f")
    _draw_single_boxplot(axes[1], obs["api_calls"], color,
                         "API calls", "API calls", value_fmt=".1f")
    plt.tight_layout()


def plot_pooled_tokens_single(
    obs: dict,
    label: str,
    color: str = COLOR_A,
) -> None:
    """
    1×3 figure of pooled per-instance boxplots for tokens_sent, tokens_received,
    and tokens_total (= sent + received, derived).
    Each box is built from N_runs × M_instances individual observations.
    """
    n = len(obs.get("tokens_sent", []))
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.5))
    fig.suptitle(f"{label} — pooled token usage ({n} observations)", fontsize=11)

    _draw_single_boxplot(axes[0], obs["tokens_sent"],     color,
                         "Tokens sent",     "Tokens sent",     value_fmt=",.0f")
    _draw_single_boxplot(axes[1], obs["tokens_received"], color,
                         "Tokens received", "Tokens received", value_fmt=",.0f")
    _draw_single_boxplot(axes[2], obs["tokens_total"],    color,
                         "Tokens total",    "Tokens total",    value_fmt=",.0f")
    plt.tight_layout()


def plot_cost_vs_tokens_scatter(metrics: dict, label: str, color: str = COLOR_A, ax=None) -> None:
    """
    Scatter: avg tokens_sent vs avg instance_cost per run, annotated with run numbers.
    Useful for confirming linear cost scaling and spotting outlier (expensive/stuck) runs.
    """
    if ax is None:
        _, ax = plt.subplots(figsize=(5, 4))

    run_nums = get_run_numbers(metrics)
    costs    = get_per_run_agent_field(metrics, "instance_cost")
    tokens   = get_per_run_agent_field(metrics, "tokens_sent")

    ax.scatter(tokens, costs, color=color, s=60, zorder=3, alpha=0.85)
    for rn, x, y in zip(run_nums, tokens, costs):
        ax.annotate(f"R{rn}", (x, y), textcoords="offset points",
                    xytext=(5, 3), fontsize=7, color="gray")

    ax.set_xlabel("Avg tokens sent")
    ax.set_ylabel("Avg instance cost (USD)")
    ax.set_title(f"{label} — cost vs. tokens per run")


def print_summary_table(metrics: dict, label: str) -> None:
    """Print headline numbers as a formatted text summary."""
    pr   = metrics.get("pass_rate", {})
    pool = metrics.get("pooled", {})
    n_r  = metrics.get("n_runs", "?")
    n_i  = metrics.get("n_instances_per_run", "?")

    avg_pr = pr.get("avg")
    std_pr = pr.get("std")
    ic     = pool.get("instance_cost", {})
    ts     = pool.get("tokens_sent", {})
    tr     = pool.get("tokens_received", {})
    ac     = pool.get("api_calls", {})

    ts_avg = ts.get("avg")
    tr_avg = tr.get("avg")

    print(f"{'─'*50}")
    print(f"  {label}  ({n_r} runs × {n_i} instances)")
    print(f"{'─'*50}")
    if avg_pr is not None:
        std_s = f"± {std_pr:.1f}" if std_pr is not None else ""
        print(f"  Pass rate        {avg_pr:>6.1f} %   {std_s}")
    if ic.get("avg") is not None:
        print(f"  Instance cost    ${ic['avg']:>8.4f}   (median ${ic['median']:.4f})")
    if ts_avg is not None:
        print(f"  Tokens sent      {ts_avg:>10,.0f}   (median {ts['median']:,.0f})")
    if tr_avg is not None:
        print(f"  Tokens received  {tr_avg:>10,.0f}   (median {tr['median']:,.0f})")
    if ts_avg is not None and tr_avg is not None:
        print(f"  Tokens total     {ts_avg + tr_avg:>10,.0f}")
    if ac.get("avg") is not None:
        print(f"  API calls        {ac['avg']:>7.1f}   (median {ac['median']:.1f})")
    print(f"{'─'*50}")

    if isinstance(n_i, int) and n_i <= 5:
        print(f"\n  Note: M={n_i} instances/run → pass rate takes only discrete values")
        print(f"  (multiples of {100/n_i:.1f}%). The ±std reflects discrete distribution")
        print(f"  spread, not measurement noise.")