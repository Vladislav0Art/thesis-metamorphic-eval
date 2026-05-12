import json
from bisect import bisect_left
from pathlib import Path
from typing import List

import numpy as np
from scipy import stats

# ─── Data loading ─────────────────────────────────────────────────────────────

def load_metrics(dirpath, filename: str = "metrics_summary.json") -> dict:
    path = Path(dirpath) / filename
    if not path.exists():
        raise FileNotFoundError(f"metrics_summary.json not found in: {dirpath}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    data["per_run"] = sorted(data.get("per_run", []), key=lambda r: r["run_number"])
    if "pass_rate" in data and "per_run" in data["pass_rate"]:
        data["pass_rate"]["per_run"] = sorted(
            data["pass_rate"]["per_run"], key=lambda r: r["run_number"]
        )
    return data



def load_instance_observations(dirpath, instance_ids=None) -> dict:
    """
    Walk eval_dir/run-*/result.json and collect per-instance agent metrics.

    Returns a dict of field → list (one entry per instance across all runs):
        instance_cost, api_calls, tokens_sent, tokens_received, tokens_total

    instance_ids: if not None, only include entries whose instance_id is in this list.
    Runs with a missing or empty execution list are silently skipped.
    """
    _iids = set(instance_ids) if instance_ids is not None else None
    obs = {f: [] for f in ("instance_cost", "api_calls",
                            "tokens_sent", "tokens_received", "tokens_total",
                            "reasoning_tokens_total")}
    for path in sorted(Path(dirpath).glob("run-*/result.json")):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        for inst in data.get("agent", {}).get("metrics", {}).get("execution", []):
            if _iids is not None and inst.get("instance_id") not in _iids:
                continue
            for field in (
                "instance_cost",
                "api_calls",
                "tokens_sent",
                "tokens_received",
                "reasoning_tokens_total",
            ):
                if field in inst:
                    obs[field].append(inst[field])
            sent = inst.get("tokens_sent")
            recv = inst.get("tokens_received")
            if sent is not None and recv is not None:
                obs["tokens_total"].append(sent + recv)
    return obs



def validate_metrics(metrics: dict, label: str) -> list:
    """
    Return a list of warning strings for data quality issues:
    - Runs where total_instances < n_instances_per_run (incomplete eval run, pass rate may be inflated)
    - Runs with n_missing > 0 in agent metrics (missing .traj files)
    """
    issues = []
    expected = metrics.get("n_instances_per_run")

    for run in metrics.get("per_run", []):
        run_num = run["run_number"]
        ev = run.get("evaluation")
        if ev and expected is not None and ev["total_instances"] < expected:
            issues.append(
                f"[{label}] Run {run_num}: only {ev['total_instances']} of "
                f"{expected} instances were evaluated — pass rate may be inflated."
            )
        ag = run.get("agent")
        if ag and ag.get("n_missing", 0) > 0:
            issues.append(
                f"[{label}] Run {run_num}: {ag['n_missing']} trajectory file(s) missing "
                "— agent metrics are incomplete."
            )
    return issues


def get_per_run_pass_rates(metrics: dict) -> list:
    """Extract per_run[i].evaluation.pass_rate values in run order."""
    return [
        run["evaluation"]["pass_rate"]
        for run in metrics["per_run"]
        if run.get("evaluation") is not None
    ]


def get_per_run_agent_field(metrics: dict, field: str) -> list:
    """Extract per_run[i].agent.{field}.avg values in run order."""
    return [
        run["agent"][field]["avg"]
        for run in metrics["per_run"]
        if run.get("agent") and field in run["agent"]
    ]


def get_per_run_tokens_total(metrics: dict) -> list:
    """
    Return per-run total token counts (tokens_sent + tokens_received) derived
    from per_run data.  tokens_total is not stored in metrics_summary.json; it
    is computed here for plotting purposes.
    """
    result = []
    for run in metrics["per_run"]:
        ag       = run.get("agent", {})
        sent     = ag.get("tokens_sent",     {}).get("avg")
        received = ag.get("tokens_received", {}).get("avg")
        if sent is not None and received is not None:
            result.append(sent + received)
    return result


def get_run_numbers(metrics: dict) -> list:
    """Return the run_number list from per_run."""
    return [r["run_number"] for r in metrics["per_run"]]


# p-value related metrics and loading
def load_instance_observations_by_id(dirpath, instance_ids=None) -> dict:
    """
    Walk eval_dir/run-*/result.json and collect per-instance agent metrics,
    grouped by instance_id.

    instance_ids: if not None, only include entries whose instance_id is in this list.
    Returns: dict[instance_id → dict[field → list]]
    """
    _iids = set(instance_ids) if instance_ids is not None else None
    obs = {}
    for path in sorted(Path(dirpath).glob("run-*/result.json")):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        for inst in data.get("agent", {}).get("metrics", {}).get("execution", []):
            iid = inst.get("instance_id")
            if iid is None:
                continue
            if _iids is not None and iid not in _iids:
                continue
            if iid not in obs:
                obs[iid] = {f: [] for f in ("instance_cost", "api_calls",
                                             "tokens_sent", "tokens_received", "tokens_total",
                                             "reasoning_tokens_total")}
            for field in ("instance_cost", "api_calls", "tokens_sent", "tokens_received",
                          "reasoning_tokens_total"):
                if field in inst:
                    obs[iid][field].append(inst[field])
            sent = inst.get("tokens_sent")
            recv = inst.get("tokens_received")
            if sent is not None and recv is not None:
                obs[iid]["tokens_total"].append(sent + recv)
    return obs


def _agent_id_to_eval_id(agent_id: str) -> str:
    """Convert agent instance_id to eval instance_id format.

    'mockito__mockito-3129' -> 'mockito/mockito:pr-3129'
    'alibaba__fastjson2-82' -> 'alibaba/fastjson2:pr-82'
    """
    org, rest = agent_id.split("__", 1)   # rest = 'repo-number'
    idx = rest.rfind("-")                  # last dash separates repo from PR number
    repo = rest[:idx]
    number = rest[idx + 1:]
    return f"{org}/{repo}:pr-{number}"


def load_instance_pass_rates_by_id(dirpath, instance_ids=None) -> dict:
    """
    Walk eval_dir/run-*/result.json and collect per-run pass/fail (0/1) for
    every instance_id, keyed in agent format ('org__repo-number').

    instance_ids: if not None, only include entries whose instance_id is in this list.
    Returns: dict[agent_instance_id → list[int]]
    """
    _iids = set(instance_ids) if instance_ids is not None else None
    outcomes: dict[str, list[int]] = {}
    for path in sorted(Path(dirpath).glob("run-*/result.json")):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        resolved_eval_ids = set(
            data.get("evaluation", {})
                .get("metrics", {})
                .get("summary", {})
                .get("resolved_ids", [])
        )
        for inst in data.get("agent", {}).get("metrics", {}).get("execution", []):
            agent_iid = inst.get("instance_id")
            if agent_iid is None:
                continue
            if _iids is not None and agent_iid not in _iids:
                continue
            eval_iid = _agent_id_to_eval_id(agent_iid)
            resolved = 1 if eval_iid in resolved_eval_ids else 0
            outcomes.setdefault(agent_iid, []).append(resolved)
    return outcomes


def load_resolved_runs_by_id(dirpath, instance_ids=None) -> dict:
    """
    Walk eval_dir/run-*/result.json and collect, per instance_id, the
    run_numbers in which the instance was resolved.

    instance_ids: if not None, only include entries whose instance_id is in this list.
    Returns: dict[agent_instance_id → sorted list[run_number]]
    """
    _iids = set(instance_ids) if instance_ids is not None else None
    resolved_runs: dict[str, list[int]] = {}
    for path in sorted(Path(dirpath).glob("run-*/result.json")):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        run_number = data.get("run_number")
        if run_number is None:
            try:
                run_number = int(path.parent.name.split("-")[1])
            except (IndexError, ValueError):
                run_number = 0
        resolved_eval_ids = set(
            data.get("evaluation", {})
                .get("metrics", {})
                .get("summary", {})
                .get("resolved_ids", [])
        )
        for inst in data.get("agent", {}).get("metrics", {}).get("execution", []):
            agent_iid = inst.get("instance_id")
            if agent_iid is None:
                continue
            if _iids is not None and agent_iid not in _iids:
                continue
            eval_iid = _agent_id_to_eval_id(agent_iid)
            if eval_iid in resolved_eval_ids:
                resolved_runs.setdefault(agent_iid, []).append(run_number)
    return {iid: sorted(runs) for iid, runs in resolved_runs.items()}



def load_filtered_metrics(dirpath, instance_ids) -> dict:
    """
    Recompute per-run agent averages and pass rate from run-i/result.json,
    restricted to instance_ids.

    Returns a dict compatible with get_per_run_agent_field, get_per_run_pass_rates,
    get_per_run_tokens_total, and plot_pass_rate_distribution.
    Runs with no matching execution entries are included with agent=None.
    """
    _iids_agent = set(instance_ids)
    _iids_eval  = {_agent_id_to_eval_id(iid) for iid in instance_ids}

    per_run           = []
    pass_rate_per_run = []

    for path in sorted(Path(dirpath).glob("run-*/result.json")):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        run_number = data.get("run_number", len(per_run) + 1)

        # Agent: filter execution entries to instance_ids
        execution = [
            inst for inst in
            data.get("agent", {}).get("metrics", {}).get("execution", [])
            if inst.get("instance_id") in _iids_agent
        ]

        agent = None
        if execution:
            def _avg(field, _ex=execution):
                vals = [e[field] for e in _ex if field in e]
                return sum(vals) / len(vals) if vals else None
            agent = {
                "instance_cost":   {"avg": _avg("instance_cost")},
                "api_calls":       {"avg": _avg("api_calls")},
                "tokens_sent":     {"avg": _avg("tokens_sent")},
                "tokens_received": {"avg": _avg("tokens_received")},
            }

        # Evaluation: recount resolved/submitted within instance_ids
        ev = data.get("evaluation", {}).get("metrics", {}).get("summary", {})
        submitted_eval = set(ev.get("submitted_ids", []))
        resolved_eval  = set(ev.get("resolved_ids",  []))

        filtered_total    = len(_iids_eval & submitted_eval)
        filtered_resolved = len(_iids_eval & resolved_eval)
        pass_rate = (filtered_resolved / filtered_total * 100) if filtered_total > 0 else 0.0

        per_run.append({
            "run_number": run_number,
            "agent":      agent,
            "evaluation": {"pass_rate": pass_rate, "total_instances": filtered_total},
        })
        pass_rate_per_run.append({
            "run_number": run_number,
            "resolved":   filtered_resolved,
            "total":      filtered_total,
            "pass_rate":  pass_rate,
        })

    per_run           = sorted(per_run,           key=lambda r: r["run_number"])
    pass_rate_per_run = sorted(pass_rate_per_run, key=lambda r: r["run_number"])

    pr_vals = [r["pass_rate"] for r in pass_rate_per_run]
    pr_avg  = sum(pr_vals) / len(pr_vals) if pr_vals else None
    pr_std  = (sum((v - pr_avg) ** 2 for v in pr_vals) / max(len(pr_vals) - 1, 1)) ** 0.5 \
              if len(pr_vals) >= 2 else None

    return {
        "per_run":             per_run,
        "n_instances_per_run": len(instance_ids),
        "pass_rate": {
            "avg":     pr_avg,
            "std":     pr_std,
            "per_run": pass_rate_per_run,
        },
    }





def _vd_a12(treatment, control):
    """
    Vargha-Delaney A12 effect size (Vargha & Delaney, 2000).

    A12 = probability that a random value from `treatment` exceeds one from `control`.
    A12 = 0.5 → no difference.  A12 > 0.5 → treatment tends to be larger.

    Magnitude thresholds (Hess & Kromrey, 2004):
      |scaled_A| > 0.474 → large
      |scaled_A| > 0.33  → medium
      |scaled_A| > 0.147 → small
      otherwise          → negligible
    where scaled_A = (A12 - 0.5) * 2.

    Uses the rankdata formula from Gist 2 by @jacksonpradolima (numerically stable).
    Works for unequal-length lists (the equal-length guard in the original gist is
    overly strict — the formula is valid for m ≠ n).
    """
    m = len(treatment)
    n = len(control)
    r = stats.rankdata(list(treatment) + list(control))
    r1 = sum(r[:m])
    A = (2 * r1 - m * (m + 1)) / (2 * n * m)
    levels = [0.147, 0.33, 0.474]          # Hess & Kromrey 2004
    magnitudes = ["negligible", "small", "medium", "large"]
    scaled_A = (A - 0.5) * 2
    magnitude = magnitudes[bisect_left(levels, abs(scaled_A))]
    return A, magnitude


def _mannwhitneyu_pvalue(data_a, data_b):
    """
    Two-sided Wilcoxon rank-sum test (= Mann-Whitney U test) for two independent samples.
    Returns the p-value. Uses scipy.stats.mannwhitneyu with alternative='two-sided'.
    """
    _, p = stats.mannwhitneyu(data_a, data_b, alternative="two-sided")
    return p
