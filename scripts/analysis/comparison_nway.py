"""N-way comparison plots and tables for comparing all strategies side-by-side."""

from typing import List, Tuple

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from analysis.data_loading import (
    _mannwhitneyu_pvalue,
    _vd_a12,
    get_per_run_pass_rates,
    load_instance_pass_rates_by_id,
    load_resolved_runs_by_id,
)

_ALPHA = 0.05

STRATEGY_STYLES = {
    "s0-original":          {"color": "#C8C8C8", "hatch": ""},
    "s1-renaming":          {"color": "#AEC6CF", "hatch": "//"},
    "s2-structural":        {"color": "#C3B1E1", "hatch": "\\\\"},
    "s3-problem-statement": {"color": "#FFB347", "hatch": "xx"},
    "s4-combined":          {"color": "#FFB3BA", "hatch": ".."},
}

_POOLED_FIELDS = [
    "instance_cost",
    "api_calls",
    "tokens_sent",
    "tokens_received",
    "tokens_total",
]


# ─── Core N-way boxplot helper ────────────────────────────────────────────────

def _draw_nway_boxplot(
    ax,
    datasets: List[list],
    labels: List[str],
    colors: List[str],
    hatches: List[str],
    ylabel: str,
    title: str,
    value_fmt: str = ".3f",
) -> None:
    """
    Draw N side-by-side box plots. Red solid = median, blue dashed = mean.
    Colors and hatches are applied per group.
    """
    n = len(datasets)
    positions = list(range(1, n + 1))

    bp = ax.boxplot(
        datasets,
        positions=positions,
        widths=0.55,
        patch_artist=True,
        showmeans=True,
        meanline=True,
        meanprops=dict(color="blue", linewidth=1.5, linestyle="--"),
        medianprops=dict(color="red", linewidth=2),
        whiskerprops=dict(linewidth=1.0),
        capprops=dict(linewidth=1.2),
        flierprops=dict(marker="D", markerfacecolor="gray",
                        markeredgecolor="none", markersize=4, alpha=0.6),
    )

    for patch, color, hatch in zip(bp["boxes"], colors, hatches):
        patch.set_facecolor(color)
        patch.set_alpha(0.75)
        patch.set_hatch(hatch)

    all_vals = [v for d in datasets for v in d]
    data_range = max(all_vals) - min(all_vals) if len(all_vals) > 1 else 1

    for data, pos in zip(datasets, positions):
        q3     = float(np.percentile(data, 75))
        median = float(np.median(data))
        mean   = float(np.mean(data))
        yoff   = q3 + data_range * 0.06
        ax.text(
            pos, yoff,
            f"med {median:{value_fmt}}\navg {mean:{value_fmt}}",
            ha="center", fontsize=6.5, linespacing=1.4,
            bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="none", alpha=0.75),
        )

    ax.set_xticks(positions)
    ax.set_xticklabels(labels, rotation=15, ha="right", fontsize=8)
    ax.set_ylabel(ylabel)
    ax.set_title(title, pad=20)


# ─── Public plot functions ─────────────────────────────────────────────────────

def plot_pass_rate_nway(strategies, all_metrics: dict) -> None:
    """
    1×2 figure: left = per-strategy boxplots, right = per-run line overlay.
    strategies: List[Strategy]; all_metrics: {name → metrics_dict}
    """
    model_label = strategies[0].model
    labels   = [s.display_name for s in strategies]
    colors   = [STRATEGY_STYLES.get(s.name, {}).get("color", "#CCCCCC") for s in strategies]
    hatches  = [STRATEGY_STYLES.get(s.name, {}).get("hatch", "")       for s in strategies]
    datasets = [get_per_run_pass_rates(all_metrics[s.name]) for s in strategies]
    n_runs   = all_metrics[strategies[0].name].get("n_runs", "?")

    fig, (ax_box, ax_line) = plt.subplots(1, 2, figsize=(14, 4.5))
    fig.suptitle(
        f"Pass rate — {model_label}  ({n_runs} runs × 20 instances)",
        fontsize=11,
    )

    # Left: boxplots
    _draw_nway_boxplot(ax_box, datasets, labels, colors, hatches,
                       "Pass rate (%)", "Distribution", value_fmt=".1f")
    ax_box.set_ylim(-5, 110)

    # Right: per-run line overlay
    _MARKERS    = ["o", "s", "^", "D", "v"]
    _LINESTYLES = ["-", "--", ":", "-.", (0, (3, 1, 1, 1))]
    n_max = max(len(d) for d in datasets)
    xs    = np.arange(1, n_max + 1)

    for i, (s, rates, color) in enumerate(zip(strategies, datasets, colors)):
        # Darken near-white grey so it's visible against a white background
        line_color = "#555555" if color == "#C8C8C8" else color
        ax_line.plot(
            xs[: len(rates)], rates,
            marker=_MARKERS[i % len(_MARKERS)],
            linestyle=_LINESTYLES[i % len(_LINESTYLES)],
            color=line_color,
            linewidth=1.5, markersize=6,
            label=s.display_name,
        )

    ax_line.set_xlabel("Run number")
    ax_line.set_ylabel("Pass rate (%)")
    ax_line.set_ylim(-5, 110)
    ax_line.set_xticks(xs)
    ax_line.set_xticklabels([f"R{n}" for n in xs])
    ax_line.set_title("Per-run pass rates")
    ax_line.legend(fontsize=8, loc="upper right")

    plt.tight_layout()


def plot_pooled_metrics_nway(strategies, all_obs: dict, model_label: str) -> None:
    """
    Two figures: (1) instance_cost + api_calls; (2) tokens_sent + tokens_received + tokens_total.
    strategies: List[Strategy]; all_obs: {name → obs_dict}
    """
    labels  = [s.display_name for s in strategies]
    colors  = [STRATEGY_STYLES.get(s.name, {}).get("color", "#CCCCCC") for s in strategies]
    hatches = [STRATEGY_STYLES.get(s.name, {}).get("hatch", "")       for s in strategies]

    n_obs = [len(all_obs[s.name].get("instance_cost", [])) for s in strategies]
    n_obs_str = "  |  ".join(f"{s.display_name}: {n}" for s, n in zip(strategies, n_obs))

    # Figure 1: cost + api_calls
    fig1, axes1 = plt.subplots(1, 2, figsize=(12, 4.5))
    fig1.suptitle(f"Pooled cost & API calls — {model_label}\n{n_obs_str}", fontsize=10)
    _draw_nway_boxplot(
        axes1[0],
        [all_obs[s.name]["instance_cost"] for s in strategies],
        labels, colors, hatches,
        "Instance cost (USD)", "Instance cost (USD)", value_fmt=".4f",
    )
    _draw_nway_boxplot(
        axes1[1],
        [all_obs[s.name]["api_calls"] for s in strategies],
        labels, colors, hatches,
        "API calls", "API calls", value_fmt=".1f",
    )
    plt.tight_layout()

    # Figure 2: tokens
    fig2, axes2 = plt.subplots(1, 3, figsize=(16, 4.5))
    fig2.suptitle(f"Pooled token usage — {model_label}\n{n_obs_str}", fontsize=10)
    _draw_nway_boxplot(
        axes2[0],
        [all_obs[s.name]["tokens_sent"] for s in strategies],
        labels, colors, hatches,
        "Tokens sent", "Tokens sent", value_fmt=",.0f",
    )
    _draw_nway_boxplot(
        axes2[1],
        [all_obs[s.name]["tokens_received"] for s in strategies],
        labels, colors, hatches,
        "Tokens received", "Tokens received", value_fmt=",.0f",
    )
    _draw_nway_boxplot(
        axes2[2],
        [all_obs[s.name]["tokens_total"] for s in strategies],
        labels, colors, hatches,
        "Tokens total", "Tokens total", value_fmt=",.0f",
    )
    plt.tight_layout()

    # Figure 3: reasoning tokens (skipped when no strategy has data)
    reasoning_data = [all_obs[s.name].get("reasoning_tokens_total", []) for s in strategies]
    if any(d for d in reasoning_data):
        _CLIP = 30_000
        fig3, ax3 = plt.subplots(figsize=(9, 4.5))
        fig3.suptitle(f"Pooled reasoning tokens — {model_label}\n{n_obs_str}", fontsize=10)
        _draw_nway_boxplot(
            ax3,
            [d if d else [0] for d in reasoning_data],
            labels, colors, hatches,
            "Reasoning tokens", "Reasoning tokens", value_fmt=",.0f",
        )
        ax3.set_ylim(bottom=0, top=_CLIP)

        # Dotted clip boundary
        ax3.axhline(_CLIP, color="gray", linewidth=0.8, linestyle=":", zorder=0)

        # Per-boxplot: annotate how many observations were cut
        for pos, data in enumerate(reasoning_data, start=1):
            if not data:
                continue
            n_cut = sum(1 for v in data if v > _CLIP)
            if n_cut:
                ax3.text(
                    pos, _CLIP * 0.985,
                    f"↑{n_cut} cut",
                    ha="center", va="top", fontsize=7.5, color="dimgray",
                    bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="lightgray", alpha=0.9),
                )

        plt.tight_layout()

        clip_notes = ", ".join(
            f"{s.display_name}: ↑{sum(1 for v in d if v > _CLIP)}"
            for s, d in zip(strategies, reasoning_data)
            if d and sum(1 for v in d if v > _CLIP) > 0
        )
        print(f"Reasoning tokens: y-axis clipped at {_CLIP:,}. Outliers cut — {clip_notes}.")


# ─── Resolution table ─────────────────────────────────────────────────────────

def build_resolution_table(strategies, sort_by_name: str = "s0-original") -> pd.DataFrame:
    """
    Per-instance resolution table sorted by the sort_by_name strategy's resolved count.

    Columns: instance_id, one column per strategy (showing resolved run labels or "—").
    Last row: total resolved count per strategy.
    """
    resolved_by   = {}
    all_ids: set  = set()

    for s in strategies:
        resolved = load_resolved_runs_by_id(s.filepath)
        outcomes = load_instance_pass_rates_by_id(s.filepath)
        resolved_by[s.name] = resolved
        all_ids |= set(outcomes.keys())

    sort_resolved = resolved_by.get(sort_by_name, {})
    sorted_ids = sorted(all_ids, key=lambda iid: (-len(sort_resolved.get(iid, [])), iid))

    rows = []
    for iid in sorted_ids:
        row = {"instance_id": iid}
        for s in strategies:
            runs = resolved_by[s.name].get(iid, [])
            row[s.display_name] = ", ".join(f"R{r}" for r in runs) if runs else "—"
        rows.append(row)

    # Summary row
    summary = {"instance_id": "TOTAL resolved"}
    for s in strategies:
        summary[s.display_name] = str(len(resolved_by[s.name]))
    rows.append(summary)

    cols = ["instance_id"] + [s.display_name for s in strategies]
    return pd.DataFrame(rows, columns=cols)


# ─── Compact statistical significance ─────────────────────────────────────────

def build_compact_stat_sig_df(
    s0_metrics: dict,
    s0_obs: dict,
    comparisons: List[Tuple[str, dict, dict]],
) -> pd.DataFrame:
    """
    Wide DataFrame with one row per metric and columns for each comparison.

    comparisons: list of (label, metrics_sX, obs_sX) for s1..s4.

    Columns: metric, med_s0, then for each label:
        {label}_med, {label}_p, {label}_A12, {label}_mag, {label}_sig
    """
    _data_s0 = {
        "pass_rate":       get_per_run_pass_rates(s0_metrics),
        "instance_cost":   s0_obs["instance_cost"],
        "api_calls":       s0_obs["api_calls"],
        "tokens_sent":     s0_obs["tokens_sent"],
        "tokens_received": s0_obs["tokens_received"],
        "tokens_total":    s0_obs["tokens_total"],
    }

    rows = []
    for metric in ["pass_rate"] + _POOLED_FIELDS:
        data_s0 = _data_s0[metric]
        med_s0  = float(np.median(data_s0))

        row: dict = {"metric": metric, "med_s0": med_s0}

        for label, metrics_sX, obs_sX in comparisons:
            data_sX = get_per_run_pass_rates(metrics_sX) if metric == "pass_rate" else obs_sX[metric]
            med_sX  = float(np.median(data_sX))
            p       = _mannwhitneyu_pvalue(data_s0, data_sX)
            sig     = p < _ALPHA
            if sig:
                a12, mag = _vd_a12(data_s0, data_sX)
            else:
                a12, mag = float("nan"), "—"

            row[f"{label}_med"] = med_sX
            row[f"{label}_p"]   = p
            row[f"{label}_A12"] = a12
            row[f"{label}_mag"] = mag
            row[f"{label}_sig"] = sig

        rows.append(row)

    return pd.DataFrame(rows)


def display_compact_stat_sig(
    df: pd.DataFrame,
    label_s0: str,
    labels_sX: List[str],
) -> None:
    """
    Display a styled compact statistical significance table.

    Highlights significant p-values in light yellow. Shows A12 + magnitude
    only for significant results.
    """
    fmt_for = {
        "pass_rate":      ("{:.1f}%",  "{:.1f}"),
        "instance_cost":  ("${:.4f}",  "${:.4f}"),
        "api_calls":      ("{:.1f}",   "{:.1f}"),
        "tokens_sent":    ("{:,.0f}",  "{:,.0f}"),
        "tokens_received":("{:,.0f}",  "{:,.0f}"),
        "tokens_total":   ("{:,.0f}",  "{:,.0f}"),
    }

    disp_rows = []
    for _, row in df.iterrows():
        metric = row["metric"]
        fmt_s0, fmt_sX = fmt_for.get(metric, ("{}", "{}"))
        disp: dict = {
            "metric": metric,
            f"med({label_s0})": fmt_s0.format(row["med_s0"]),
        }
        for label in labels_sX:
            med_str = fmt_sX.format(row[f"{label}_med"])
            p       = row[f"{label}_p"]
            a12     = row[f"{label}_A12"]
            mag     = row[f"{label}_mag"]
            sig     = row[f"{label}_sig"]
            p_str   = f"{p:.3f}{'*' if sig else ''}"
            a12_str = f"{a12:.2f} ({mag})" if sig else "—"
            disp[f"med({label})"] = med_str
            disp[f"p({label})"]   = p_str
            disp[f"A12({label})"] = a12_str
        disp_rows.append(disp)

    disp_df = pd.DataFrame(disp_rows).set_index("metric")

    # Build a boolean mask of significant p-value cells
    p_cols = [f"p({lbl})" for lbl in labels_sX]

    def _highlight_sig(val):
        if isinstance(val, str) and val.endswith("*"):
            return "background-color: #FFFACD; font-weight: bold"
        return ""

    styler = (
        disp_df.style
        .set_caption(
            f"Statistical significance: {label_s0} vs others  "
            f"(Wilcoxon rank-sum, α={_ALPHA}). "
            "* = significant. A12 > 0.5 → s0 tends to produce larger values."
        )
        .set_table_styles([
            {"selector": "th", "props": [("text-align", "center"), ("font-size", "11px")]},
            {"selector": "td", "props": [("text-align", "center"), ("font-size", "11px")]},
            {"selector": "th.row_heading", "props": [("text-align", "left")]},
        ])
    )
    # pandas ≥2.1 renamed applymap → map
    _apply_fn = getattr(styler, "map", None) or getattr(styler, "applymap")
    styled = _apply_fn(_highlight_sig, subset=p_cols)
    from IPython.display import display as _display
    _display(styled)


# ─── Per-instance helpers ──────────────────────────────────────────────────────

_FIELD_FMT = {
    "pass_rate":       "{:.1f}%",
    "instance_cost":   "${:.4f}",
    "api_calls":       "{:.1f}",
    "tokens_sent":     "{:,.0f}",
    "tokens_received": "{:,.0f}",
    "tokens_total":    "{:,.0f}",
}


def build_per_instance_pass_rate_nway(
    strategies,
    all_pass_rates_by_id: dict,
    sort_by_name: str = "s0-original",
) -> pd.DataFrame:
    """
    Per-instance pass rate fractions: each cell shows "resolved/total" (e.g. "3/5").

    Rows sorted by sort_by_name strategy's resolved count descending.
    No statistical test — with N=5 binary outcomes the test is severely underpowered;
    raw fractions are more informative.
    """
    s0_rates = all_pass_rates_by_id.get(sort_by_name, {})
    all_ids: set = set()
    for rates in all_pass_rates_by_id.values():
        all_ids |= set(rates.keys())

    sorted_ids = sorted(all_ids, key=lambda iid: (-sum(s0_rates.get(iid, [])), iid))

    rows = []
    for iid in sorted_ids:
        row = {"instance_id": iid}
        for s in strategies:
            outcomes = all_pass_rates_by_id[s.name].get(iid, [])
            n = len(outcomes)
            row[s.display_name] = f"{sum(outcomes)}/{n}" if n > 0 else "—"
        rows.append(row)

    cols = ["instance_id"] + [s.display_name for s in strategies]
    return pd.DataFrame(rows, columns=cols)


def display_per_instance_metric_sig_nway(
    strategies,
    all_obs_by_id: dict,
    fields: List[str] = None,
) -> None:
    """
    For each metric field, display one table: per-instance median + p-value for
    every s0-vs-sX pair (pooled per-run observations, not per-run averages).

    fields defaults to ["instance_cost", "api_calls"].
    Significant p-values (< α) are highlighted in yellow and marked with *.
    Rows sorted by descending number of significant comparisons (most interesting first).
    """
    if fields is None:
        fields = ["instance_cost", "api_calls"]

    s0 = next(s for s in strategies if s.name == "s0-original")
    sX_list = [s for s in strategies if s.name != "s0-original"]

    from IPython.display import display as _display

    def _highlight_sig(val):
        if isinstance(val, str) and val.endswith("*"):
            return "background-color: #FFFACD; font-weight: bold"
        return ""

    for field in fields:
        fmt = _FIELD_FMT.get(field, "{}")
        all_ids: set = set()
        for s in strategies:
            all_ids |= set(all_obs_by_id[s.name].keys())

        rows = []
        for iid in sorted(all_ids):
            data_s0 = all_obs_by_id[s0.name].get(iid, {}).get(field, [])
            if not data_s0:
                continue
            med_s0 = float(np.median(data_s0))
            row = {"instance_id": iid, f"med({s0.display_name})": fmt.format(med_s0)}
            n_sig = 0
            for sX in sX_list:
                data_sX = all_obs_by_id[sX.name].get(iid, {}).get(field, [])
                if not data_sX:
                    row[f"med({sX.display_name})"] = "—"
                    row[f"p({sX.display_name})"]   = "—"
                    row[f"A12({sX.display_name})"]  = "—"
                    continue
                med_sX = float(np.median(data_sX))
                p      = _mannwhitneyu_pvalue(data_s0, data_sX)
                sig    = p < _ALPHA
                n_sig += int(sig)
                if sig:
                    a12, mag = _vd_a12(data_s0, data_sX)
                    a12_str  = f"{a12:.2f} ({mag})"
                else:
                    a12_str = "—"
                row[f"med({sX.display_name})"] = fmt.format(med_sX)
                row[f"p({sX.display_name})"]   = f"{p:.3f}{'*' if sig else ''}"
                row[f"A12({sX.display_name})"] = a12_str
            row["_n_sig"] = n_sig
            rows.append(row)

        if not rows:
            continue

        df = pd.DataFrame(rows).sort_values(
            ["_n_sig", f"med({s0.display_name})"], ascending=[False, False]
        ).drop(columns=["_n_sig"]).set_index("instance_id")

        p_cols = [f"p({sX.display_name})" for sX in sX_list if f"p({sX.display_name})" in df.columns]
        styler = df.style.set_caption(
            f"Per-instance stat sig: {field}  "
            f"(pooled obs, Wilcoxon rank-sum, α={_ALPHA}; * = significant)"
        )
        _apply_fn = getattr(styler, "map", None) or getattr(styler, "applymap")
        _display(_apply_fn(_highlight_sig, subset=p_cols))


# ─── Metrics summary with Δ% ──────────────────────────────────────────────────

def build_metrics_summary_df(strategies, all_metrics: dict, all_obs: dict) -> pd.DataFrame:
    """
    Wide DataFrame: for each metric, s0 baseline median+avg and per-sX med, avg, Δmed%, Δavg%.

    pass_rate source:  per-run values (5 obs per strategy).
    Agent metrics:     pooled per-instance observations (runs × instances obs per strategy).
    Δ% = (sX - s0) / |s0| × 100; NaN when s0 == 0.
    """
    s0 = next(s for s in strategies if s.name == "s0-original")
    sX_list = [s for s in strategies if s.name != "s0-original"]

    def _data(metric, s):
        if metric == "pass_rate":
            return get_per_run_pass_rates(all_metrics[s.name])
        return all_obs[s.name][metric]

    rows = []
    for metric in ["pass_rate"] + _POOLED_FIELDS:
        d_s0   = _data(metric, s0)
        med_s0 = float(np.median(d_s0))
        avg_s0 = float(np.mean(d_s0))
        row    = {"metric": metric, "s0_med": med_s0, "s0_avg": avg_s0}

        for sX in sX_list:
            d_sX   = _data(metric, sX)
            med_sX = float(np.median(d_sX))
            avg_sX = float(np.mean(d_sX))
            row[f"{sX.display_name}_med"]  = med_sX
            row[f"{sX.display_name}_avg"]  = avg_sX
            row[f"{sX.display_name}_Δmed"] = (med_sX - med_s0) / abs(med_s0) * 100 if med_s0 else float("nan")
            row[f"{sX.display_name}_Δavg"] = (avg_sX - avg_s0) / abs(avg_s0) * 100 if avg_s0 else float("nan")

        rows.append(row)

    return pd.DataFrame(rows)


def _fmt_abs_delta(metric: str, abs_delta: float) -> str:
    """Format an absolute delta value with the correct unit and sign prefix."""
    sign = "+" if abs_delta >= 0 else "-"
    v    = abs(abs_delta)
    if metric == "pass_rate":
        return f"{abs_delta:+.1f}%"
    if metric == "instance_cost":
        return f"{sign}${v:.4f}"
    if metric == "api_calls":
        return f"{abs_delta:+.1f}"
    # tokens
    return f"{abs_delta:+,.0f}"


def display_metrics_summary(
    df: pd.DataFrame,
    strategies,
    show: List[str] = None,
) -> None:
    """
    Styled summary table: median & avg per strategy.

    show: subset of ['med', 'avg'] controlling which stat columns are rendered.
          Defaults to both.
    Δ columns show both the absolute change and the percentage change in parentheses,
    e.g. "-5.8% (-36.7%)" for pass_rate or "+$0.31 (+12.5%)" for instance_cost.
    Green = increased vs s0, red = decreased.
    """
    if show is None:
        show = ["med", "avg"]
    sX_list = [s for s in strategies if s.name != "s0-original"]

    disp_rows = []
    for _, row in df.iterrows():
        metric = row["metric"]
        fmt    = _FIELD_FMT.get(metric, "{}")
        disp   = {"metric": metric}
        if "med" in show:
            disp["s0_med"] = fmt.format(row["s0_med"])
        if "avg" in show:
            disp["s0_avg"] = fmt.format(row["s0_avg"])
        for sX in sX_list:
            med_s0  = row["s0_med"]
            avg_s0  = row["s0_avg"]
            med_sX  = row[f"{sX.display_name}_med"]
            avg_sX  = row[f"{sX.display_name}_avg"]
            pct_med = row[f"{sX.display_name}_Δmed"]
            pct_avg = row[f"{sX.display_name}_Δavg"]

            if "med" in show:
                disp[f"{sX.display_name}_med"] = fmt.format(med_sX)
                if np.isnan(pct_med):
                    disp[f"{sX.display_name}_Δmed"] = "—"
                else:
                    abs_str = _fmt_abs_delta(metric, med_sX - med_s0)
                    disp[f"{sX.display_name}_Δmed"] = f"{abs_str} ({pct_med:+.1f}%)"

            if "avg" in show:
                disp[f"{sX.display_name}_avg"] = fmt.format(avg_sX)
                if np.isnan(pct_avg):
                    disp[f"{sX.display_name}_Δavg"] = "—"
                else:
                    abs_str = _fmt_abs_delta(metric, avg_sX - avg_s0)
                    disp[f"{sX.display_name}_Δavg"] = f"{abs_str} ({pct_avg:+.1f}%)"

        disp_rows.append(disp)

    disp_df    = pd.DataFrame(disp_rows).set_index("metric")
    delta_cols = [c for c in disp_df.columns if "_Δ" in c]

    def _color_delta(val):
        if not isinstance(val, str) or val == "—":
            return ""
        if val.startswith("+"):
            return "background-color: #C6EFCE; color: #276221"
        if val.startswith("-"):
            return "background-color: #FFC7CE; color: #9C0006"
        return ""

    styler = disp_df.style.set_caption(
        "Metric summary: median & avg per strategy + Δ vs s0-original  "
        "(format: absolute change (% change); "
        "pass_rate = per-run values; agent metrics = pooled obs)"
    )
    _apply_fn = getattr(styler, "map", None) or getattr(styler, "applymap")
    from IPython.display import display as _display
    _display(_apply_fn(_color_delta, subset=delta_cols))
