"""
evaluate/io.py — Result file I/O helpers for the evaluation orchestrator.

Functions here handle writing per-run manifests (result.json) and the
cross-run aggregated metrics summary (metrics_summary.json).  They are pure
I/O wrappers with no side effects beyond filesystem writes.
"""

import json
import logging
import sys
from pathlib import Path

# Ensure scripts/ is importable regardless of where this module is loaded from.
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from eval.metrics import aggregate_runs

logger = logging.getLogger(__name__)


def write_result_json(run_dir: Path, data: dict) -> None:
    """
    Write (or overwrite) ``result.json`` in *run_dir*.

    Called after every step so that partial results are persisted on failure.
    Path objects are serialised as strings via the ``default=str`` fallback.
    """
    result_path = run_dir / "result.json"
    with open(result_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, default=str)


def write_metrics_summary(workdir: Path, n_runs: int) -> None:
    """
    Aggregate per-run metrics across all N completed runs and write
    ``{workdir}/metrics_summary.json``.

    Called once after the N-run loop.  Reads both ``agent.metrics`` and
    ``evaluation.metrics`` from each ``run-i/result.json``, then delegates
    all math to ``eval.metrics.aggregate_runs`` (stdlib only, no side effects).

    Skips runs whose ``result.json`` is missing or has no agent metrics.
    Evaluation metrics are optional: if the evaluation step did not run,
    ``pass_rate`` is omitted from the output.

    Output file: ``{workdir}/metrics_summary.json``
    See :func:`eval.metrics.aggregate_runs` for the full schema.
    """
    run_numbers: list    = []
    run_summaries: list  = []
    all_executions: list = []
    eval_summaries: list = []
    any_agent_metrics    = False
    any_eval_metrics     = False

    for run_number in range(1, n_runs + 1):
        result_path = workdir / f"run-{run_number}" / "result.json"
        if not result_path.exists():
            logger.warning(f"result.json missing for run-{run_number}; skipping its metrics.")
            continue
        with open(result_path, "r", encoding="utf-8") as f:
            result_data = json.load(f)

        agent_metrics   = result_data.get("agent", {}).get("metrics", {})
        agent_summary   = agent_metrics.get("summary")
        agent_execution = agent_metrics.get("execution", [])
        eval_summary    = result_data.get("evaluation", {}).get("metrics", {}).get("summary")

        if not agent_summary and not eval_summary:
            logger.warning(
                f"No agent or evaluation metrics in run-{run_number}/result.json; skipping."
            )
            continue

        run_numbers.append(run_number)
        run_summaries.append(agent_summary)
        all_executions.append(agent_execution)
        eval_summaries.append(eval_summary)

        if agent_summary:
            any_agent_metrics = True
        if eval_summary:
            any_eval_metrics = True

    if not run_numbers:
        logger.warning("No metrics found in any run; metrics_summary.json will not be written.")
        return

    if not any_agent_metrics:
        logger.info(
            "No agent metrics found across all runs (evaluation-only run). "
            "metrics_summary.json will contain pass_rate data only."
        )

    summary = aggregate_runs(
        run_numbers,
        run_summaries,
        all_executions,
        eval_summaries=eval_summaries if any_eval_metrics else None,
    )
    logger.info(
        f"Aggregated metrics: {len(run_numbers)} run(s), "
        f"agent={'yes' if any_agent_metrics else 'no'}, "
        f"eval={'yes' if any_eval_metrics else 'no'}."
    )
    metrics_path = workdir / "metrics_summary.json"
    with open(metrics_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    logger.info(f"Cross-run metrics summary → {metrics_path}")
