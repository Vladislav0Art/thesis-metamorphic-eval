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
        "pass_rate": {                  ← only present when evaluation step ran
            "avg": 45.5, "std": 3.2, "min": 40.0, "max": 50.0,
            "per_run": [{"run_number": 1, "resolved": 5, "total": 11,
                         "pass_rate": 45.5}, ...]
        },
        "per_run": [
            {
                "run_number": 1,
                "agent":      {"n_instances": 11, "n_missing": 0,
                               "total_cost": {"avg": 3.14, ...}, ...},
                "evaluation": {"total_instances": 11, "resolved_instances": 5,
                               "unresolved_instances": 6, "pass_rate": 45.5}
            },
            ...
        ]
    }

See ``scripts/eval/metrics.py`` for the pure math functions used here;
they are also directly importable in Jupyter notebooks.

Internal sub-package layout
---------------------------
Helper functions are split across ``scripts/evaluate/``:

    evaluate/cleanup.py  — cleanup_agent_preds (wipes stale all_preds.jsonl)
    evaluate/io.py       — write_result_json, write_metrics_summary
    evaluate/resume.py   — load_run_result, classify_run_steps,
                           reconstruct_agent_result, cleanup_step_artifacts,
                           STEP_ARTIFACT_DIRS
"""

import argparse
import logging
import sys
from datetime import datetime
from pathlib import Path

# ── Bootstrap sys.path ────────────────────────────────────────────────────────
# Adds the scripts/ directory to sys.path so that ``eval.*``, ``common.*``,
# and the ``evaluate.*`` sub-package are importable regardless of CWD.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.logger import configure_logging
from eval.config import load_config, EvalConfig
from eval.steps.base import StepResult
from eval.steps.agent import AgentStep
from eval.steps.evaluation import EvaluationStep

from evaluate.cleanup import cleanup_agent_preds
from evaluate.io import write_result_json, write_metrics_summary
from evaluate.resume import (
    load_run_result,
    classify_run_steps,
    reconstruct_agent_result,
    cleanup_step_artifacts,
)

logger = logging.getLogger(__name__)

# Maps step names (as they appear in run.steps) to their Step subclasses.
# Add new steps here as the pipeline grows.
_STEP_REGISTRY = {
    "agent":      AgentStep,
    "evaluation": EvaluationStep,
}


# ─── Orchestration ────────────────────────────────────────────────────────────

def run_evaluation(config: EvalConfig, config_filepath: str) -> None:
    """
    Main orchestration loop.

    Args:
        config:          Fully loaded EvalConfig (paths already resolved).
        config_filepath: Original path to the config file (stored in result.json
                         for traceability).
    """
    # ── Set up workdir ────────────────────────────────────────────────────────
    workdir = Path(config.run.workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    # Script-level log at workdir root — captures output from all N runs.
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

    # Warn when skip_existing=True would cause runs 2..N to skip all instances.
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

        logger.info("")
        logger.info("=" * 70)
        logger.info(f"  Run {run_number} of {config.run.N}")
        logger.info(f"  Run dir : {run_dir.resolve()}")
        logger.info("=" * 70)

        # ── Resume detection ───────────────────────────────────────────────────
        existing_result = load_run_result(workdir, run_number)
        steps_to_run, steps_to_skip = classify_run_steps(
            existing_result, config.run.steps
        )

        if not steps_to_run:
            logger.info(
                f"  Run {run_number}/{config.run.N}: all configured steps "
                f"{config.run.steps} succeeded previously — skipping entire run."
            )
            continue

        if steps_to_skip:
            logger.info(
                f"  Run {run_number}/{config.run.N}: skipping {steps_to_skip} "
                f"(succeeded previously); resuming from '{steps_to_run[0]}'."
            )
        else:
            logger.info(
                f"  Run {run_number}/{config.run.N}: no prior results — starting fresh."
            )

        run_dir.mkdir(parents=True, exist_ok=True)

        # ── result_data: resume from existing file or start fresh ──────────────
        if existing_result is not None:
            result_data = existing_result
            result_data["timestamp"] = datetime.now().isoformat()
            logger.info(
                f"  Loaded existing result_data from result.json; "
                f"timestamp updated to {result_data['timestamp']}."
            )
        else:
            result_data = {
                "run_number":     run_number,
                "timestamp":      datetime.now().isoformat(),
                "config_file":    str(Path(config_filepath).resolve()),
                "workdir":        str(workdir.resolve()),
                "steps_executed": [],
            }

        context: dict[str, StepResult] = {}
        # Inject run_number so steps (e.g. EvaluationStep) can adjust per-run behaviour.
        context["_run_number"] = run_number

        # ── Inject skipped step results into context so later steps can read them ──
        if "agent" in steps_to_skip and existing_result is not None:
            agent_data = existing_result.get("agent", {})
            context["agent"] = reconstruct_agent_result(agent_data)
            fix_patches = agent_data.get("fix_patches", "<none>")
            logger.info(
                f"  Injected saved agent result into context "
                f"(fix_patches={fix_patches})."
            )

        # ── Clean stale all_preds.jsonl only when agent step will actually run ──
        # Without this, MSWE-agent appends to the previous run's predictions.
        if "agent" in steps_to_run and config.steps.agent is not None:
            cleanup_agent_preds(config.steps.agent)

        # ── Step loop ──────────────────────────────────────────────────────────
        for step_name in config.run.steps:
            if step_name in steps_to_skip:
                logger.info(
                    f"  [SKIP] step '{step_name}' — succeeded in previous execution."
                )
                continue

            # On resume: wipe stale artifacts so the step starts clean.
            # On a fresh run existing_result is None, so this branch is skipped.
            if existing_result is not None:
                cleanup_step_artifacts(step_name, run_dir)

            logger.info("")
            logger.info(f"{'─' * 70}")
            logger.info(
                f"  [RUN]  step '{step_name.upper()}'  (run {run_number}/{config.run.N})"
            )
            logger.info(f"{'─' * 70}")

            step_config = getattr(config.steps, step_name)
            step_class  = _STEP_REGISTRY[step_name]
            step        = step_class(step_config)

            result: StepResult = step.run(run_dir, context)

            context[step_name] = result
            # Guard against duplicates when the step is being retried on resume.
            if step_name not in result_data.get("steps_executed", []):
                result_data.setdefault("steps_executed", []).append(step_name)
            result_data[step_name] = result.to_dict()

            # Persist result.json after every step (partial results survive failures).
            write_result_json(run_dir, result_data)

            if not result.success:
                logger.error(f"  Step '{step_name}' failed: {result.error}")
                logger.error(
                    f"  Partial results saved to: {run_dir / 'result.json'}"
                )
                logger.error(
                    f"  Re-run the same command to resume from "
                    f"run {run_number}, step '{step_name}'."
                )
                sys.exit(1)

            logger.info(f"  Step '{step_name}' completed successfully.")

        logger.info("")
        logger.info(f"  Run {run_number} complete.  Manifest: {run_dir / 'result.json'}")

    # ── Cross-run metrics summary ─────────────────────────────────────────────
    # Always attempt: write_metrics_summary handles agent-only, eval-only, and
    # combined runs gracefully; it skips writing only when no metrics exist at all.
    logger.info("")
    logger.info("Computing cross-run metrics summary ...")
    write_metrics_summary(workdir, config.run.N)

    # ── Summary ───────────────────────────────────────────────────────────────
    logger.info("")
    logger.info("=" * 70)
    logger.info(f"  All {config.run.N} run(s) completed successfully.")
    logger.info(f"  Log     : {workdir / 'evaluate.log'}")
    logger.info(f"  Metrics : {workdir / 'metrics_summary.json'}")
    logger.info("=" * 70)


# ─── Entry point ──────────────────────────────────────────────────────────────

def main() -> None:
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
        print(f"[ERROR] Failed to load config: {e}", file=sys.stderr)
        sys.exit(1)

    run_evaluation(config, args.config)


if __name__ == "__main__":
    main()
