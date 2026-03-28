"""
metrics.py — Pure math functions for agent execution metrics.

All functions operate on plain Python dicts/lists and depend only on the
standard library (``statistics``, ``json``, ``pathlib``).  They are
intentionally free of side effects so they can be imported directly into
Jupyter notebooks for plot generation without pulling in the rest of the
pipeline.

────────────────────────────────────────────────────────────────────────────
Metric fields
────────────────────────────────────────────────────────────────────────────
Every per-instance execution dict contains the following numeric fields,
sourced from ``info.model_stats`` inside a ``.traj`` file produced by
MSWE-agent:

    total_cost      — total API cost in USD for this instance
    instance_cost   — same as total_cost (MSWE-agent bookkeeping convention)
    tokens_sent     — number of prompt tokens sent to the model
    tokens_received — number of completion tokens received from the model
    api_calls       — number of individual API round-trips made

────────────────────────────────────────────────────────────────────────────
Summary dict shape
────────────────────────────────────────────────────────────────────────────
Functions that produce a "summary" return a dict with a nested sub-dict per
metric field::

    {
        "n_instances": 11,
        "n_missing":   2,          ← instances whose .traj file was absent
        "total_cost":  {"avg": 3.14, "median": 2.88},
        "tokens_sent": {"avg": 500000, "median": 450000},
        ...
    }

────────────────────────────────────────────────────────────────────────────
Cross-run aggregation
────────────────────────────────────────────────────────────────────────────
``aggregate_runs()`` builds the top-level ``metrics_summary.json`` structure
that contains two complementary views:

pooled
    All N×M observations merged into one flat dataset.  Avg and median over
    this pool answer: "What is the *expected* cost / token count for a single
    agent invocation on this benchmark?"  This is the headline number for the
    thesis.

run_variability
    Statistics *about* the N per-run averages (mean, std dev, min, max).
    Answers: "How *consistent* is the agent across independent runs?"
    ``std_of_run_avgs`` is the ± value for thesis error bars.
    A high std relative to the mean suggests the agent is unstable — which
    may be an interesting finding when comparing normal vs. metamorphic runs.
"""

import json
from pathlib import Path
from statistics import mean, median, stdev
from typing import Optional

# The metric fields extracted from model_stats in every .traj file
METRIC_FIELDS: tuple = (
    "total_cost",
    "instance_cost",
    "tokens_sent",
    "tokens_received",
    "api_calls",
)


# ─── .traj file reader ────────────────────────────────────────────────────────

def extract_model_stats(traj_data: dict) -> Optional[dict]:
    """
    Extract ``info.model_stats`` from a *parsed* ``.traj`` JSON dict.

    Returns a dict with only the known ``METRIC_FIELDS`` keys, or ``None``
    if the expected structure is absent or malformed.

    Args:
        traj_data: The parsed JSON content of a ``.traj`` file.
    """
    try:
        stats = traj_data["info"]["model_stats"]
        return {f: stats[f] for f in METRIC_FIELDS if f in stats}
    except (KeyError, TypeError):
        return None


def read_traj_metrics(traj_path: Path) -> Optional[dict]:
    """
    Open a ``.traj`` file, parse it, and return its ``info.model_stats`` dict.

    This is the only function in this module that performs file I/O.  It is
    provided as a convenience for notebook usage where you want to inspect a
    single trajectory file without loading the rest of the pipeline.

    Returns ``None`` if the file does not exist, cannot be parsed as JSON,
    or lacks the expected ``info.model_stats`` structure.

    Args:
        traj_path: Absolute or relative path to the ``.traj`` file.
    """
    try:
        with open(traj_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return extract_model_stats(data)
    except Exception:
        return None


# ─── Single-run aggregation ───────────────────────────────────────────────────

def _field_stats(values: list) -> dict:
    """Return ``{"avg": ..., "median": ...}`` for a list of numbers, or nulls."""
    if not values:
        return {"avg": None, "median": None}
    return {"avg": mean(values), "median": median(values)}


def summarize_executions(executions: list) -> dict:
    """
    Compute per-field avg and median over a list of per-instance execution dicts.

    Each entry in *executions* must contain ``"instance_id"`` and optionally
    the numeric ``METRIC_FIELDS``.  Entries where **all** metric fields are
    absent (e.g. because the ``.traj`` file was missing) are counted in
    ``n_missing`` but do not affect the numeric aggregations.

    Args:
        executions: List of per-instance metric dicts, one per instance.

    Returns::

        {
            "n_instances": 11,
            "n_missing":   2,
            "total_cost":  {"avg": 3.14, "median": 2.88},
            "instance_cost": {"avg": 3.14, "median": 2.88},
            "tokens_sent": {"avg": 500000, "median": 450000},
            "tokens_received": {"avg": 3500, "median": 3200},
            "api_calls":   {"avg": 55.0, "median": 50.0}
        }
    """
    n_missing = sum(
        1 for e in executions
        if not any(f in e for f in METRIC_FIELDS)
    )
    result: dict = {
        "n_instances": len(executions),
        "n_missing": n_missing,
    }
    for field in METRIC_FIELDS:
        values = [e[field] for e in executions if field in e]
        result[field] = _field_stats(values)
    return result


# ─── Cross-run aggregation ────────────────────────────────────────────────────

def pooled_stats(all_executions: list) -> dict:
    """
    Pool all per-instance observations across N runs and compute aggregate
    avg / median for each metric field.

    Args:
        all_executions: A list of N lists.  Each inner list is the
                        ``execution`` array from one run (raw per-instance
                        dicts as produced by ``_collect_metrics`` in
                        ``AgentStep``).

    Returns::

        {
            "n_observations": 33,
            "total_cost":  {"avg": 3.14, "median": 2.88},
            ...
        }

    ``n_observations`` counts only entries that have at least one metric field
    (i.e. excludes instances whose ``.traj`` was absent in every run).

    This is the *headline number* for the thesis: "On average, a single agent
    invocation on this benchmark cost $X and consumed Y tokens."
    """
    flat = [e for run in all_executions for e in run]
    result: dict = {
        "n_observations": sum(
            1 for e in flat if any(f in e for f in METRIC_FIELDS)
        )
    }
    for field in METRIC_FIELDS:
        values = [e[field] for e in flat if field in e]
        result[field] = _field_stats(values)
    return result


def run_variability_stats(run_summaries: list) -> dict:
    """
    Describe the spread of per-run averages across N runs.

    Args:
        run_summaries: A list of N summary dicts, each as returned by
                       ``summarize_executions``.

    For each metric field, returns::

        {
            "total_cost": {
                "avg_of_run_avgs": 3.14,
                "std_of_run_avgs": 0.02,   # None when N < 2
                "min_run_avg":     3.12,
                "max_run_avg":     3.16
            },
            ...
        }

    ``std_of_run_avgs`` is the standard deviation of the N per-run means.
    Use it as the ± value in thesis tables: "cost was $3.14 ± $0.02 per
    instance".  A high std relative to the mean implies the agent is not
    stable across runs.

    ``avg_of_run_avgs`` equals ``pooled.avg`` only when every run processes
    the same number of instances (which is the normal case).
    """
    result: dict = {}
    for field in METRIC_FIELDS:
        avgs = [
            s[field]["avg"]
            for s in run_summaries
            if isinstance(s.get(field), dict) and s[field].get("avg") is not None
        ]
        result[field] = {
            "avg_of_run_avgs": mean(avgs)   if avgs          else None,
            "std_of_run_avgs": stdev(avgs)  if len(avgs) >= 2 else None,
            "min_run_avg":     min(avgs)    if avgs          else None,
            "max_run_avg":     max(avgs)    if avgs          else None,
        }
    return result


def aggregate_runs(
    run_numbers: list,
    run_summaries: list,
    all_executions: list,
) -> dict:
    """
    Build the full ``metrics_summary.json`` structure.

    Args:
        run_numbers:    Ordered list of run indices, e.g. ``[1, 2, 3]``.
        run_summaries:  One summary dict per run (from ``summarize_executions``).
        all_executions: One execution list per run (raw per-instance dicts).

    Returns::

        {
            "n_runs": 3,
            "n_instances_per_run": 11,
            "pooled": {
                "n_observations": 33,
                "total_cost": {"avg": 3.14, "median": 2.88},
                ...
            },
            "run_variability": {
                "total_cost": {
                    "avg_of_run_avgs": 3.14, "std_of_run_avgs": 0.02,
                    "min_run_avg": 3.12, "max_run_avg": 3.16
                },
                ...
            },
            "per_run": [
                {"run_number": 1, "summary": {...}},
                {"run_number": 2, "summary": {...}},
                {"run_number": 3, "summary": {...}}
            ]
        }
    """
    n_instances = run_summaries[0]["n_instances"] if run_summaries else 0
    return {
        "n_runs": len(run_summaries),
        "n_instances_per_run": n_instances,
        "pooled": pooled_stats(all_executions),
        "run_variability": run_variability_stats(run_summaries),
        "per_run": [
            {"run_number": run_numbers[i], "summary": run_summaries[i]}
            for i in range(len(run_numbers))
        ],
    }
