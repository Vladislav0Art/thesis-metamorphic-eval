"""
evaluate/resume.py — Resume/re-execution helpers for the evaluation orchestrator.

This module provides the logic for detecting and resuming interrupted N-run
evaluation loops without re-running steps that already succeeded.

How resume works
----------------
Before each run the orchestrator calls :func:`load_run_result` to check
whether a ``result.json`` exists from a previous attempt.  If it does,
:func:`classify_run_steps` inspects each step's ``success`` field:

  - ``true``  → step is skipped; its saved result is injected into ``context``
                 via :func:`reconstruct_agent_result` so downstream steps can
                 still read its artifacts.
  - ``false`` / missing → step is re-run.

Before a step re-runs, :func:`cleanup_step_artifacts` deletes any stale
artifact directories it previously produced so the step starts clean.

Forcing a step to re-run
------------------------
Set ``result.json["<step>"]["success"]`` to ``false`` manually and re-invoke
``evaluate.py``.  The step (and all subsequent ones) will be re-executed.
"""

import json
import logging
import shutil
import sys
from pathlib import Path
from typing import Optional

# Ensure scripts/ is importable regardless of where this module is loaded from.
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from eval.steps.agent import AgentStepResult

logger = logging.getLogger(__name__)


# Maps each step name to the run-N/ subdirectories it produces.
# These directories are deleted before the step re-runs on resume.
STEP_ARTIFACT_DIRS: dict[str, list[str]] = {
    "agent":      ["predictions", "trajectories"],
    "evaluation": ["eval"],
}


def cleanup_step_artifacts(step_name: str, run_dir: Path) -> None:
    """
    Delete the artifact directories that *step_name* produces inside *run_dir*.

    Called when a step is about to be re-executed during a resume so that stale
    output from the previous attempt does not bleed into the new run.  Missing
    directories are silently skipped (nothing to clean).

    Directories cleaned per step:
        agent      → run-N/predictions/, run-N/trajectories/
        evaluation → run-N/eval/
    """
    dirs = STEP_ARTIFACT_DIRS.get(step_name, [])
    if not dirs:
        logger.debug(f"No artifact dirs registered for step '{step_name}'; nothing to clean.")
        return

    for dir_name in dirs:
        target = run_dir / dir_name
        if target.exists():
            shutil.rmtree(target)
            logger.info(f"  [CLEANUP] Deleted stale artifact dir before re-run: {target}")
        else:
            logger.debug(f"  [CLEANUP] Artifact dir absent, nothing to delete: {target}")


def load_run_result(workdir: Path, run_number: int) -> Optional[dict]:
    """
    Load ``result.json`` for *run_number* from the workdir.

    Returns the parsed dict when the file exists and is valid JSON.
    Returns ``None`` when the file is absent or cannot be parsed, logging
    an appropriate message in each case.
    """
    result_path = workdir / f"run-{run_number}" / "result.json"
    if not result_path.exists():
        logger.info(f"Run {run_number}: no result.json found — will start fresh.")
        return None
    try:
        with open(result_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        logger.info(
            f"Run {run_number}: found existing result.json — checking resume state."
        )
        return data
    except Exception as e:
        logger.warning(
            f"Run {run_number}: could not read result.json ({e}) — treating as fresh run."
        )
        return None


def classify_run_steps(
    existing_result: Optional[dict],
    configured_steps: list[str],
) -> tuple[list[str], list[str]]:
    """
    Determine which configured steps must run and which can be skipped.

    A step is **skipped** when ``existing_result[step_name]["success"] is True``.
    Everything else (failed, missing key, or no prior result) goes into
    ``steps_to_run``.

    A user can force a step to re-run by setting its ``success`` field to
    ``false`` in the existing result.json before re-invoking evaluate.py.

    Args:
        existing_result:   Parsed content of ``result.json``, or ``None`` for
                           a fresh run with no prior result.
        configured_steps:  Ordered list of step names from ``run.steps`` config.

    Returns:
        ``(steps_to_run, steps_to_skip)`` — both lists preserve config order.
    """
    if existing_result is None:
        return list(configured_steps), []

    steps_to_run: list[str] = []
    steps_to_skip: list[str] = []

    for step_name in configured_steps:
        step_data = existing_result.get(step_name, {})
        if step_data.get("success") is True:
            steps_to_skip.append(step_name)
        else:
            steps_to_run.append(step_name)

    return steps_to_run, steps_to_skip


def reconstruct_agent_result(agent_data: dict) -> AgentStepResult:
    """
    Rebuild an ``AgentStepResult`` from the ``result.json["agent"]`` section.

    Used when the agent step succeeded in a previous run and is being skipped
    on resume.  The reconstructed object is injected into ``context["agent"]``
    so that ``EvaluationStep._resolve_patch_files`` can read ``fix_patches_path``
    from it exactly as if the agent had just run in this session.
    """
    fix_patches_str       = agent_data.get("fix_patches")
    trajectory_source_str = agent_data.get("trajectory_source")
    trajectory_dest_str   = agent_data.get("trajectory_dest")
    metrics               = agent_data.get("metrics", {})

    return AgentStepResult(
        success=agent_data.get("success", False),
        error=agent_data.get("error", ""),
        trajectory_source=(
            Path(trajectory_source_str) if trajectory_source_str else None
        ),
        copy_trajectories=agent_data.get("copy_trajectories", True),
        trajectory_dest=(
            Path(trajectory_dest_str) if trajectory_dest_str else None
        ),
        fix_patches_path=Path(fix_patches_str) if fix_patches_str else None,
        artifacts=agent_data.get("artifacts", []),
        metrics_execution=metrics.get("execution", []),
        metrics_summary=metrics.get("summary", {}),
    )
