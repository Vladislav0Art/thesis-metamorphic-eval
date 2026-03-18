"""
AgentStep — runs MSWE-agent and converts its output.

Substeps executed in order
--------------------------
1. Checkout the configured git branch in the MSWE-agent repo.
2. Ensure the Python environment is set up (venv + dependencies).
3. Write ``keys.cfg`` with API tokens if not already present.
4. TODO [PLACEHOLDER] Run MSWE-agent (run.py or multirun.py).
5. Discover the trajectory folder produced by the agent.
6. Copy the trajectory folder into run_dir (if ``copy_trajectories=True``).
7. Convert ``all_preds.jsonl`` → ``fix_patches.jsonl`` (multi_swe_bench format).

Placeholder behaviour
---------------------
Steps 4-7 depend on actual agent output.  While the agent execution is a
placeholder, ``_run_agent()`` returns ``False`` and steps 5-7 are skipped.
``AgentStepResult.fix_patches_path`` will be ``None`` in that case, which
EvaluationStep handles gracefully by requiring an explicit ``patch_files``
entry in its config section.

Trajectory discovery
--------------------
MSWE-agent writes trajectories to::

    {agent_dir}/trajectories/{username}/{model}__{benchmark}__...../
        all_preds.jsonl
        args.yaml
        *.traj
        patches/

After the agent runs, we glob for ``all_preds.jsonl`` files under
``trajectories/`` and pick the most recently modified parent directory.
Because the orchestrator controls timing, the newest file is always the one
just produced by this run.

Prediction conversion (convert substep)
----------------------------------------
MSWE-agent output schema (one JSON object per line in all_preds.jsonl):
    {"instance_id": "org__repo-N", "model_name_or_path": "...", "model_patch": "..."}

multi_swe_bench input schema (fix_patches.jsonl):
    {"org": "...", "repo": "...", "number": N, "model_name_or_path": "...", "fix_patch": "..."}

The conversion is inlined here (rather than shelling out to
convert_model_predictions.py) so that the step is fully self-contained and
reuses the read_jsonl / write_jsonl helpers from common/fs.py.
"""

import re
import shutil
import sys
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# Ensure scripts/ is on sys.path
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from common.cli import run_cli_command
from common.fs import read_jsonl, write_jsonl
from eval.steps.base import Step, StepResult
from eval.steps.setup import Setup
# Config dataclasses come from eval.config (single source of truth for schema)
from eval.config import AgentStepConfig

logger = logging.getLogger(__name__)

# Matches MSWE-agent instance_id: "org__repo-number"
_INSTANCE_ID_RE = re.compile(r"^(.+?)__(.+?)-(\d+)$")


def _parse_instance_id(instance_id: str) -> tuple[str, str, int]:
    """Parse ``'org__repo-N'`` into ``(org, repo, N)``."""
    m = _INSTANCE_ID_RE.match(instance_id)
    if not m:
        raise ValueError(
            f"Invalid instance_id '{instance_id}'. Expected format: 'org__repo-number'."
        )
    org, repo, number = m.groups()
    return org, repo, int(number)


# ─── Step result ──────────────────────────────────────────────────────────────

@dataclass
class AgentStepResult(StepResult):
    """
    Artifacts produced by the agent step.

    Attributes:
        trajectory_source:  Original trajectory folder inside the MSWE-agent repo.
                            Always set when the agent actually ran.
        copy_trajectories:  Whether the trajectory was copied into run_dir.
        trajectory_dest:    Copied trajectory path inside run_dir/trajectories/.
                            None if copy_trajectories=False or agent didn't run.
        fix_patches_path:   Path to the converted fix_patches.jsonl inside
                            run_dir/predictions/.  None if agent didn't run.
    """
    trajectory_source: Optional[Path] = None
    copy_trajectories: bool = True
    trajectory_dest: Optional[Path] = None
    fix_patches_path: Optional[Path] = None

    def to_dict(self) -> dict:
        return {
            **super().to_dict(),
            "trajectory_source": str(self.trajectory_source) if self.trajectory_source else None,
            "copy_trajectories": self.copy_trajectories,
            "trajectory_dest": str(self.trajectory_dest) if self.trajectory_dest else None,
            "fix_patches": str(self.fix_patches_path) if self.fix_patches_path else None,
        }


# ─── Step ─────────────────────────────────────────────────────────────────────

class AgentStep(Step):
    """Runs MSWE-agent and converts its output to multi_swe_bench format."""

    def __init__(self, config: AgentStepConfig):
        super().__init__("agent")
        self.config = config
        self.dir = Path(config.dir)
        self.setup = Setup(config.setup, self.dir)

    def run(self, run_dir: Path, context: dict) -> AgentStepResult:
        """Execute the full agent pipeline."""
        try:
            # Step 1: put the repo on the right branch
            self._checkout_branch()

            # Step 2: ensure Python env (creates venv if absent, installs deps)
            self.setup.ensure()

            # Step 3: write API keys to keys.cfg
            self._write_keys_cfg()

            # Step 4: run the agent (currently a placeholder)
            agent_ran = self._run_agent()

            if not agent_ran:
                # Placeholder path: setup is done, but no trajectories exist yet.
                logger.warning(
                    "[PLACEHOLDER] Agent did not run; skipping trajectory discovery, "
                    "copy, and prediction conversion.  fix_patches.jsonl will not be "
                    "generated until the agent is actually executed."
                )
                return AgentStepResult(
                    success=True,
                    copy_trajectories=self.config.copy_trajectories,
                )

            # Step 5: find the trajectory folder the agent just wrote
            trajectory_source = self._discover_trajectory()
            logger.info(f"Discovered trajectory folder: {trajectory_source}")

            # Step 6: optionally copy the whole trajectory into the run archive
            trajectory_dest = None
            if self.config.copy_trajectories:
                trajectory_dest = self._copy_trajectory(trajectory_source, run_dir)
                logger.info(f"Trajectory copied to: {trajectory_dest}")
            else:
                logger.info(
                    "copy_trajectories=False: trajectory remains at source. "
                    "The source path is recorded in result.json."
                )

            # Step 7: convert all_preds.jsonl → fix_patches.jsonl
            fix_patches_path = self._convert(trajectory_source, run_dir)
            logger.info(f"Converted predictions written to: {fix_patches_path}")

            return AgentStepResult(
                success=True,
                trajectory_source=trajectory_source.resolve(),
                copy_trajectories=self.config.copy_trajectories,
                trajectory_dest=trajectory_dest.resolve() if trajectory_dest else None,
                fix_patches_path=fix_patches_path.resolve(),
            )

        except Exception as e:
            logger.error(f"AgentStep failed: {e}", exc_info=True)
            return AgentStepResult(success=False, error=str(e))

    # ─── Substep implementations ──────────────────────────────────────────────

    def _checkout_branch(self):
        """Checkout the configured git branch inside the MSWE-agent repo."""
        logger.info(f"Fetching remote refs in {self.dir} ...")
        stdout, stderr, code = run_cli_command("git", ["fetch"], cwd=str(self.dir))
        if code != 0:
            # A missing remote is non-fatal: the branch may already be local.
            logger.warning(f"git fetch returned non-zero (non-fatal): {stderr.strip()}")

        logger.info(f"Checking out branch '{self.config.branch}' ...")
        stdout, stderr, code = run_cli_command(
            "git", ["checkout", self.config.branch], cwd=str(self.dir)
        )
        if code != 0:
            raise RuntimeError(
                f"Failed to checkout branch '{self.config.branch}' in {self.dir}:\n"
                f"{stderr.strip()}"
            )
        logger.info(f"On branch '{self.config.branch}'.")

    def _write_keys_cfg(self):
        """
        Write API tokens to ``keys.cfg`` in the MSWE-agent repo root.

        Format expected by MSWE-agent::

            OPENAI_API_KEY="sk-..."
            ANTHROPIC_API_KEY="sk-ant-..."
        """
        keys_path = self.dir / self.config.keys.path
        if keys_path.exists() and not self.config.keys.override:
            logger.info(
                f"keys.cfg already exists at {keys_path}; "
                "skipping generation (set keys.override=true to regenerate)."
            )
            return

        lines = [f'{k}="{v}"' for k, v in self.config.keys.values.items()]
        keys_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        logger.info(f"Written keys.cfg ({len(lines)} token(s)) → {keys_path}")

    def _run_agent(self) -> bool:
        """
        [PLACEHOLDER] Run MSWE-agent on the configured benchmark.

        TODO: Replace the placeholder body with an actual ``run_cli_command``
              call once the setup/config pipeline has been validated end-to-end.

        When implemented, the command will be:

            cd {agent_dir}
            {venv}/bin/python {script} \\
                --model_name      <model_name> \\
                --pr_file         <benchmark_file> \\
                --config_file     <config_file> \\
                ... (other flags)

        For ``multirun.py``, ``RUNNING_THREADS={threads}`` must be set in env.

        Returns:
            True  — agent ran and produced trajectory output.
            False — placeholder; no actual agent execution.
        """
        c = self.config.config
        script = "multirun.py" if self.config.runner.parallel else "run.py"

        cmd_lines = [
            f"python {script}",
            f"  --model_name {c.model_name}",
            f"  --pr_file {c.benchmark_file}",
            f"  --config_file {c.config_file}",
            f"  --per_instance_cost_limit {c.per_instance_cost_limit}",
            f"  --cache_task_images {c.cache_task_images}",
            f"  --pre_build_all_images {c.pre_build_all_images}",
            f"  --remove_image {c.remove_image}",
            f"  --skip_existing {c.skip_existing}",
            f"  --print_config {c.print_config}",
            f"  --max_workers_build_image {c.max_workers_build_image}",
        ]
        if self.config.runner.parallel:
            cmd_lines.insert(0, f"RUNNING_THREADS={self.config.runner.threads} \\")

        logger.info("[PLACEHOLDER] MSWE-agent would be run with:")
        for line in cmd_lines:
            logger.info(f"    {line} \\")
        logger.info("[PLACEHOLDER] Skipping actual agent execution.")

        return False  # TODO: return True after implementing actual execution

    def _discover_trajectory(self) -> Path:
        """
        Find the trajectory folder most recently written by MSWE-agent.

        MSWE-agent writes trajectories to::

            {agent_dir}/trajectories/{username}/{model}__{benchmark}__...

        We glob for all ``all_preds.jsonl`` files under ``trajectories/`` and
        return the parent directory of the most recently modified one.
        """
        trajectories_root = self.dir / "trajectories"
        if not trajectories_root.exists():
            raise RuntimeError(
                f"Trajectories directory not found: {trajectories_root}\n"
                "Ensure MSWE-agent has been run at least once."
            )

        all_preds_files = list(trajectories_root.rglob("all_preds.jsonl"))
        if not all_preds_files:
            raise RuntimeError(
                f"No all_preds.jsonl found under {trajectories_root}. "
                "Ensure the agent produced output."
            )

        # The newest file was produced by this run
        most_recent = max(all_preds_files, key=lambda p: p.stat().st_mtime)
        return most_recent.parent

    def _copy_trajectory(self, trajectory_source: Path, run_dir: Path) -> Path:
        """
        Copy the entire trajectory folder into ``{run_dir}/trajectories/``,
        preserving the original folder name.
        """
        dest_root = run_dir / "trajectories"
        trajectory_dest = dest_root / trajectory_source.name

        if trajectory_dest.exists():
            logger.warning(
                f"Trajectory destination already exists; overwriting: {trajectory_dest}"
            )
            shutil.rmtree(trajectory_dest)

        shutil.copytree(str(trajectory_source), str(trajectory_dest))
        logger.info(f"Trajectory copied: {trajectory_source.name}")
        return trajectory_dest

    def _convert(self, trajectory_source: Path, run_dir: Path) -> Path:
        """
        Convert ``all_preds.jsonl`` (MSWE-agent format) to ``fix_patches.jsonl``
        (multi_swe_bench format) and write it to ``{run_dir}/predictions/``.

        This is the same logic as ``scripts/convert_model_predictions.py``,
        inlined here so the step is self-contained.
        """
        all_preds_path = trajectory_source / "all_preds.jsonl"
        if not all_preds_path.exists():
            raise RuntimeError(f"all_preds.jsonl not found at: {all_preds_path}")

        predictions_dir = run_dir / "predictions"
        predictions_dir.mkdir(parents=True, exist_ok=True)
        fix_patches_path = predictions_dir / "fix_patches.jsonl"

        raw_entries = read_jsonl(str(all_preds_path))
        converted = []
        errors = 0

        for entry in raw_entries:
            try:
                org, repo, number = _parse_instance_id(entry["instance_id"])
                converted.append({
                    "org": org,
                    "repo": repo,
                    "number": number,
                    "model_name_or_path": entry["model_name_or_path"],
                    "fix_patch": entry["model_patch"],
                })
            except (KeyError, ValueError) as e:
                logger.warning(f"Skipping malformed entry during conversion: {e}")
                errors += 1

        write_jsonl(str(fix_patches_path), converted)
        logger.info(
            f"Conversion complete: {len(converted)} entries written, "
            f"{errors} skipped → {fix_patches_path}"
        )
        return fix_patches_path
