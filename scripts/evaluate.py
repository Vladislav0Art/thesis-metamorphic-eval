#!/usr/bin/env python3
"""
evaluate.py — Metamorphic Evaluation Orchestrator
==================================================

Ties together all phases of the metamorphic evaluation pipeline (MSWE-agent and multi_swe_bench harness)
into a single command so that a full end-to-end run requires no manual intermediate steps.

Usage
-----
    python scripts/evaluate.py --config path/to/evaluate.yaml

See ``scripts/evaluate.example.yaml`` for a fully annotated configuration file.

Pipeline phases (steps)
-----------------------
The steps to execute are declared in ``run.steps`` inside the config file.
They run in the order listed.

  agent
      1. Checkout the configured git branch in the MSWE-agent repo.
      2. Ensure the Python environment (venv + deps).
      3. Write ``keys.cfg`` with API tokens.
      4. Run MSWE-agent (run.py or multirun.py).
      5. Discover the generated trajectory folder.
      6. Copy the trajectory folder into the run archive (if enabled).
      7. Convert ``all_preds.jsonl`` → ``fix_patches.jsonl`` (multi_swe_bench format).

  evaluation
      1. Checkout the configured git branch in the multi_swe_bench repo.
      2. Ensure the Python environment (venv + deps).
      3. Resolve ``fix_patches.jsonl`` (from agent step or explicit config).
      4. Auto-generate ``config.json`` for the multi_swe_bench harness.
      5. Run the multi_swe_bench evaluation harness.

Steps can be run together or independently:
  - Full run:          ``run.steps: [agent, evaluation]``
  - Agent only:        ``run.steps: [agent]``
  - Evaluation only:   ``run.steps: [evaluation]``
    (requires ``evaluation.config.patch_files`` to be set explicitly)

Path resolution
---------------
All relative paths in the config YAML are resolved relative to the *config
file's own directory*, not the CWD from which this script is invoked.  This
makes the config file portable: you can place it anywhere inside the project
tree and paths like ``./agents/MSWE-agent`` will resolve correctly.

Workdir and run-N structure
---------------------------
All artefacts for a run are isolated under ``{workdir}/run-{N}/``.
When ``run.N > 1``, run-1 through run-N are created sequentially.
The exact layout per run:

    {workdir}/
        evaluate.log                    ← script-level log (all runs)
        run-1/
            result.json                 ← run manifest; written after each step
            predictions/
                fix_patches.jsonl       ← convert substep output
            trajectories/               ← copy of MSWE-agent trajectory folder
                {model}__{benchmark}__*/
                    all_preds.jsonl
                    args.yaml
                    *.traj
                    patches/
            eval/
                config.json             ← auto-generated harness config
                workdir/                ← harness internal workdir
                output/
                    final_report.json   ← primary result metric
                repos/
                logs/
        metrics_summary.json        ← cross-run metrics (written once after all runs)

result.json
-----------
A JSON manifest written to ``{run_dir}/result.json`` after each step
completes (so partial results are saved on failure).  It contains absolute
paths to every produced artefact and is the canonical place to look for
where things are, especially when ``copy_trajectories=false`` (the
trajectory source path is still recorded there).

Schema:
```
    {
        "run_number":  1,
        "timestamp":   "ISO-8601",
        "config_file": "/abs/path/to/evaluate.yaml",
        "workdir":     "/abs/path/to/workdir",
        "steps_executed": ["agent", "evaluation"],
        "agent": {
            "success":            true,
            "error":              "",
            "trajectory_source":  "/abs/path/.../trajectories/gpt4o__...",
            "copy_trajectories":  true,
            "trajectory_dest":    "/abs/path/.../run-1/trajectories/gpt4o__...",
            "fix_patches":        "/abs/path/.../run-1/predictions/fix_patches.jsonl",
            "artifacts":          [{"instance_id": "...", "trajectory": "...", "patch": "..."}],
            "metrics": {
                "execution": [{"instance_id": "...", "total_cost": 5.07, "...": "..."}],
                "summary":   {"n_instances": 11, "n_missing": 0,
                              "total_cost": {"avg": 3.14, "median": 2.88}, "...": "..."}
            }
        },
        "evaluation": {
            "success":     true,
            "error":       "",
            "eval_config": "/abs/path/.../run-1/eval/config.json",
            "report":      "/abs/path/.../run-1/eval/output/final_report.json"
        }
    }
```

metrics_summary.json
--------------------
Written once to ``{workdir}/metrics_summary.json`` after all N runs finish.
Contains two complementary cross-run views:

  pooled
      All N×M per-instance observations merged into one flat dataset.
      Avg and median over this pool answer: "What is the expected cost /
      token count per agent invocation on this benchmark?"
      This is the headline metric for the thesis.

  run_variability
      Statistics *about* the N per-run averages (mean, std dev, min, max).
      Answers: "How consistent is the agent across independent runs?"
      ``std_of_run_avgs`` is the ± value for thesis error bars.

Schema::

    {
        "n_runs": 3,
        "n_instances_per_run": 11,
        "pooled": {
            "n_observations": 33,
            "total_cost":  {"avg": 3.14, "median": 2.88},
            "tokens_sent": {"avg": 500000, "median": 450000},
            ...
        },
        "run_variability": {
            "total_cost": {
                "avg_of_run_avgs": 3.14,  "std_of_run_avgs": 0.02,
                "min_run_avg":     3.12,  "max_run_avg":     3.16
            },
            ...
        },
        "per_run": [
            {"run_number": 1, "summary": {"n_instances": 11, "n_missing": 0,
                                          "total_cost": {"avg": 3.14, ...}, ...}},
            ...
        ]
    }

See ``scripts/eval/metrics.py`` for the pure math functions used here;
they are also directly importable in Jupyter notebooks.
"""

import argparse
import json
import logging
import sys
from datetime import datetime
from pathlib import Path

# ── Bootstrap sys.path ────────────────────────────────────────────────────────
# Adds the scripts/ directory to sys.path so that ``eval.*`` and ``common.*``
# sub-packages are importable regardless of the CWD when the script is run.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.logger import configure_logging
from eval.config import load_config, EvalConfig, AgentStepConfig
from eval.metrics import aggregate_runs
from eval.steps.base import StepResult
from eval.steps.agent import AgentStep, build_run_name
from eval.steps.evaluation import EvaluationStep

logger = logging.getLogger(__name__)

# Maps step names (as they appear in run.steps) to their Step subclasses.
# Add new steps here as the pipeline grows.
_STEP_REGISTRY = {
    "agent":      AgentStep,
    "evaluation": EvaluationStep,
}


# ─── Trajectory cleanup ───────────────────────────────────────────────────────

def _cleanup_agent_preds(agent_cfg: AgentStepConfig):
    """
    Delete ``all_preds.jsonl`` from the expected MSWE-agent trajectory folder.

    Called before each run so that multi-run loops start with a clean slate.
    Without this, MSWE-agent appends to the existing file and subsequent runs
    pick up predictions from previous runs, making it impossible to tell which
    version of a patch was evaluated.

    Only the ``all_preds.jsonl`` file is deleted; individual ``*.traj`` and
    ``patches/*.patch`` files are left intact (they are named by instance_id
    and are overwritten in-place by the agent anyway).
    """
    trajectories_root = Path(agent_cfg.dir) / "trajectories"
    if not trajectories_root.exists():
        logger.warning(
            f"Trajectories root does not exist, skipping cleanup (possibly, the first run on a fresh agent repo): {trajectories_root}"
        )
        return

    expected_name = build_run_name(agent_cfg.config)
    logger.info(f"Cleaning up stale all_preds.jsonl files for expected trajectory name: {expected_name}")

    matches = [p for p in trajectories_root.glob(f"*/{expected_name}") if p.is_dir()]
    for folder in matches:
        preds_file = folder / "all_preds.jsonl"
        if preds_file.exists():
            preds_file.unlink()
            logger.info(f"Deleted stale all_preds.jsonl from: {folder}")
        else:
            logger.debug(f"No all_preds.jsonl to clean in: {folder}")


# ─── Cross-run metrics ────────────────────────────────────────────────────────

def _write_metrics_summary(workdir: Path, n_runs: int):
    """
    Aggregate per-run execution metrics across all N completed runs and write
    ``{workdir}/metrics_summary.json``.

    Called once after the N-run loop.  Reads the ``agent.metrics`` section of
    each ``run-i/result.json`` that was produced by AgentStep, then delegates
    all math to ``eval.metrics.aggregate_runs`` (stdlib only, no side effects).

    Skips runs whose ``result.json`` is missing or has no agent metrics (e.g.
    when only the evaluation step ran).  If no run has metrics, the file is not
    written and a warning is logged.

    Output file: ``{workdir}/metrics_summary.json``
    See :func:`eval.metrics.aggregate_runs` for the full schema.
    """
    run_numbers: list   = []
    run_summaries: list = []
    all_executions: list = []

    for run_number in range(1, n_runs + 1):
        result_path = workdir / f"run-{run_number}" / "result.json"
        if not result_path.exists():
            logger.warning(f"result.json missing for run-{run_number}; skipping its metrics.")
            continue
        with open(result_path, "r", encoding="utf-8") as f:
            result_data = json.load(f)

        metrics = result_data.get("agent", {}).get("metrics", {})
        summary   = metrics.get("summary")
        execution = metrics.get("execution", [])

        if not summary:
            logger.warning(f"No agent metrics in run-{run_number}/result.json; skipping.")
            continue

        run_numbers.append(run_number)
        run_summaries.append(summary)
        all_executions.append(execution)

    if not run_summaries:
        logger.warning("No per-run agent metrics found; metrics_summary.json will not be written.")
        return

    summary = aggregate_runs(run_numbers, run_summaries, all_executions)
    metrics_path = workdir / "metrics_summary.json"
    with open(metrics_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    logger.info(f"Cross-run metrics summary → {metrics_path}")


# ─── result.json helpers ──────────────────────────────────────────────────────

def _write_result_json(run_dir: Path, data: dict):
    """
    Write (or overwrite) ``result.json`` in *run_dir*.

    Called after every step so that partial results are persisted on failure.
    Path objects are serialised as strings via the ``default=str`` fallback.
    """
    result_path = run_dir / "result.json"
    with open(result_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, default=str)


# ─── Orchestration ────────────────────────────────────────────────────────────

def run_evaluation(config: EvalConfig, config_filepath: str):
    """
    Main orchestration loop.

    Args:
        config:          Fully loaded EvalConfig (paths already resolved).
        config_filepath: Original path to the config file (to be stored in
                         result.json for traceability).
    """
    # ── Set up workdir ────────────────────────────────────────────────────────
    workdir = Path(config.run.workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    # ── Script-level logging: {workdir}/evaluate.log ──────────────────────────
    # Uses the shared configure_logging() from common/logger.py.
    # The log file lives at the workdir root (not run-specific) so it captures
    # log output from all N runs.
    configure_logging(log_filename=str(workdir / "evaluate.log"))

    logger.info("=" * 70)
    logger.info("  Metamorphic Evaluation Pipeline")
    logger.info("=" * 70)
    logger.info(f"  Config file : {Path(config_filepath).resolve()}")
    logger.info(f"  Workdir     : {workdir.resolve()}")
    logger.info(f"  Steps       : {config.run.steps}")
    logger.info(f"  Runs        : {config.run.N}")
    logger.info("=" * 70)

    # ── Validate step list before starting any run ────────────────────────────
    for step_name in config.run.steps:
        if step_name not in _STEP_REGISTRY:
            logger.error(
                f"Unknown step: '{step_name}'. "
                f"Valid steps: {list(_STEP_REGISTRY.keys())}"
            )
            sys.exit(1)
        step_config = getattr(config.steps, step_name, None)
        if step_config is None:
            logger.error(
                f"Step '{step_name}' is listed in run.steps but has no "
                f"configuration block under `steps.{step_name}` in the YAML "
                f"config file '{config_filepath}'."
            )
            sys.exit(1)

    # Warn when skip_existing=True would cause runs 2..N to skip all instances
    if config.run.N > 1:
        agent_cfg = getattr(config.steps, "agent", None)
        if agent_cfg is not None and getattr(agent_cfg.config, "skip_existing", False):
            logger.warning(
                f"run.N={config.run.N} with agent.config.skip_existing=true: "
                "runs 2..N will skip instances already processed in run-1. "
                "Set skip_existing=false if each run must process all instances."
            )

    # ── N-run loop ────────────────────────────────────────────────────────────
    for run_number in range(1, config.run.N + 1):
        run_dir = workdir / f"run-{run_number}"
        run_dir.mkdir(parents=True, exist_ok=True)

        logger.info("")
        logger.info("=" * 70)
        logger.info(f"  Run {run_number} of {config.run.N}")
        logger.info(f"  Run dir : {run_dir.resolve()}")
        logger.info("=" * 70)

        # Clean stale all_preds.jsonl so this run starts with a fresh file.
        # Without this, MSWE-agent appends to the previous run's predictions.
        if "agent" in config.run.steps and config.steps.agent is not None:
            _cleanup_agent_preds(config.steps.agent)

        result_data: dict = {
            "run_number":     run_number,
            "timestamp":      datetime.now().isoformat(),
            "config_file":    str(Path(config_filepath).resolve()),
            "workdir":        str(workdir.resolve()),
            "steps_executed": [],
        }

        context: dict[str, StepResult] = {}

        for step_name in config.run.steps:
            logger.info("")
            logger.info(f"{'─' * 70}")
            logger.info(f"  Step: {step_name.upper()}  (run {run_number}/{config.run.N})")
            logger.info(f"{'─' * 70}")

            step_config = getattr(config.steps, step_name)
            step_class  = _STEP_REGISTRY[step_name]
            step        = step_class(step_config)

            result: StepResult = step.run(run_dir, context)

            context[step_name] = result
            result_data["steps_executed"].append(step_name)
            result_data[step_name] = result.to_dict()

            # Persist result.json after every step (partial results survive failures)
            _write_result_json(run_dir, result_data)

            if not result.success:
                logger.error(f"Step '{step_name}' failed: {result.error}")
                logger.error(
                    f"Aborting pipeline.  Partial results saved to: "
                    f"{run_dir / 'result.json'}"
                )
                sys.exit(1)

            logger.info(f"  Step '{step_name}' completed successfully.")

        logger.info("")
        logger.info(f"  Run {run_number} complete.  Manifest: {run_dir / 'result.json'}")

    # ── Cross-run metrics summary ─────────────────────────────────────────────
    if "agent" in config.run.steps and config.steps.agent is not None:
        logger.info("")
        logger.info("Computing cross-run metrics summary ...")
        _write_metrics_summary(workdir, config.run.N)

    # ── Summary ───────────────────────────────────────────────────────────────
    logger.info("")
    logger.info("=" * 70)
    logger.info(f"  All {config.run.N} run(s) completed successfully.")
    logger.info(f"  Log     : {workdir / 'evaluate.log'}")
    logger.info(f"  Metrics : {workdir / 'metrics_summary.json'}")
    logger.info("=" * 70)


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Metamorphic evaluation orchestrator.  Runs the configured subset of "
            "pipeline steps (agent, evaluation) end-to-end.\n\n"
            "See `scripts/evaluate.example.yaml` for a fully annotated config file."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--config",
        required=True,
        metavar="PATH",
        help=(
            "Path to the YAML configuration file.  All relative paths inside "
            "the file are resolved relative to the config file's own directory."
        ),
    )
    args = parser.parse_args()

    try:
        config: EvalConfig = load_config(args.config)
    except (FileNotFoundError, KeyError, ValueError) as e:
        # Print to stderr before logging is configured
        print(f"[ERROR] Failed to load config: {e}", file=sys.stderr)
        sys.exit(1)

    run_evaluation(config, args.config)


if __name__ == "__main__":
    main()
