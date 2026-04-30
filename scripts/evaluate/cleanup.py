"""
evaluate/cleanup.py — Pre-run cleanup helpers for the evaluation orchestrator.

Contains cleanup logic that runs before a step executes to ensure a clean state.
"""

import logging
import sys
from pathlib import Path

# Ensure scripts/ is importable regardless of where this module is loaded from.
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from eval.config import AgentStepConfig
from eval.steps.agent import build_run_name

logger = logging.getLogger(__name__)


def cleanup_agent_preds(agent_cfg: AgentStepConfig) -> None:
    """
    Delete ``all_preds.jsonl`` from the expected MSWE-agent trajectory folder.

    Called before each agent run so that multi-run loops start with a clean
    slate.  Without this, MSWE-agent appends to the existing file and
    subsequent runs pick up predictions from previous runs, making it
    impossible to tell which version of a patch was evaluated.

    Only the ``all_preds.jsonl`` file is deleted; individual ``*.traj`` and
    ``patches/*.patch`` files are left intact (they are named by instance_id
    and are overwritten in-place by the agent anyway).
    """
    trajectories_root = Path(agent_cfg.dir) / "trajectories"
    if not trajectories_root.exists():
        logger.warning(
            f"Trajectories root does not exist, skipping cleanup "
            f"(possibly the first run on a fresh agent repo): {trajectories_root}"
        )
        return

    expected_name = build_run_name(agent_cfg.config)
    logger.info(
        f"Cleaning up stale all_preds.jsonl for expected trajectory name: {expected_name}"
    )

    matches = [p for p in trajectories_root.glob(f"*/{expected_name}") if p.is_dir()]
    for folder in matches:
        preds_file = folder / "all_preds.jsonl"
        if preds_file.exists():
            preds_file.unlink()
            logger.info(f"Deleted stale all_preds.jsonl from: {folder}")
        else:
            logger.debug(f"No all_preds.jsonl to clean in: {folder}")
