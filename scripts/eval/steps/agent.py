"""
AgentStep — runs MSWE-agent and converts its output.

Substeps executed in order
--------------------------
1. Checkout the configured git branch in the MSWE-agent repo.
2. Ensure the Python environment is set up (venv + dependencies).
3. Write ``keys.cfg`` with API tokens if not already present.
4. Run MSWE-agent (run.py or multirun.py).
5. Discover the trajectory folder produced by the agent.
6. Copy the trajectory folder into run_dir (if ``copy_trajectories=True``).
7. Convert ``all_preds.jsonl`` → ``fix_patches.jsonl`` (multi_swe_bench format).

Early-exit behaviour
--------------------
If ``_run_agent()`` raises, the step fails immediately and steps 5-7 are
skipped.  ``AgentStepResult.fix_patches_path`` will be ``None`` in that case,
which EvaluationStep handles gracefully by requiring an explicit
``patch_files`` entry in its config section.

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

import os
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

from common.cli import run_cli_command, run_cli_command_streaming
from common.fs import read_jsonl, write_jsonl
from eval.metrics import read_traj_metrics, summarize_executions
from eval.steps.base import Step, StepResult
from eval.steps.setup import Setup
# Config dataclasses come from eval.config (single source of truth for schema)
from eval.config import AgentStepConfig, AgentRunConfig

logger = logging.getLogger(__name__)

# Matches MSWE-agent instance_id: "org__repo-number"
_INSTANCE_ID_RE = re.compile(r"^(.+?)__(.+?)-(\d+)$")


def build_run_name(config: AgentRunConfig) -> str:
    """
    Reproduce the ``run_name`` property from MSWE-agent ``run.py``.

    The name encodes all parameters that affect the trajectory so that two
    runs with the same settings always land in the same folder::

        {model_name}__{data_stem}__{config_stem}
            __t-{temp:.2f}__p-{top_p:.2f}
            __c-{per_instance_cost_limit:.2f}__install-1

    ``data_stem`` is the file stem of ``benchmark_file`` (MSWE-agent's
    ``get_data_path_name`` reduces to ``Path(path).stem`` for local files).
    ``install-1`` is always 1 because ``install_environment`` defaults to True.

    Used both for targeted discovery and for pre-run cleanup.
    """
    model_name   = config.model_name.replace(":", "-")
    data_stem    = Path(config.benchmark_file).stem
    config_stem  = Path(config.config_file).stem

    return (
        f"{model_name}__{data_stem}__{config_stem}"
        f"__t-{config.temperature:.2f}__p-{config.top_p:.2f}"
        f"__c-{config.per_instance_cost_limit:.2f}__install-1"
    )


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
        artifacts:          Per-instance artifact paths collected from the
                            trajectory folder.  Each entry has keys:
                            ``instance_id``, ``trajectory`` (abs path or null),
                            ``patch`` (abs path or null).
        metrics_execution:  Per-instance model_stats extracted from each
                            ``.traj`` file.  Entries where the traj file was
                            absent contain only ``instance_id``.
        metrics_summary:    Avg / median summary over ``metrics_execution``
                            for this run (see ``eval.metrics.summarize_executions``).
    """
    trajectory_source: Optional[Path] = None
    copy_trajectories: bool = True
    trajectory_dest: Optional[Path] = None
    fix_patches_path: Optional[Path] = None
    artifacts: list = None          # list[dict]
    metrics_execution: list = None  # list[dict]
    metrics_summary: dict = None    # avg/median per metric field

    def to_dict(self) -> dict:
        return {
            **super().to_dict(),
            "trajectory_source": str(self.trajectory_source) if self.trajectory_source else None,
            "copy_trajectories": self.copy_trajectories,
            "trajectory_dest": str(self.trajectory_dest) if self.trajectory_dest else None,
            "fix_patches": str(self.fix_patches_path) if self.fix_patches_path else None,
            "artifacts": self.artifacts if self.artifacts is not None else [],
            "metrics": {
                "execution": self.metrics_execution if self.metrics_execution is not None else [],
                "summary":   self.metrics_summary   if self.metrics_summary   is not None else {},
            },
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

            # Step 4: run the agent
            agent_ran = self._run_agent(run_dir)

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

            # Step 8: collect per-instance artifact paths from the trajectory folder
            # Use the copied destination when available so paths point inside run_dir.
            artifacts_folder = trajectory_dest if trajectory_dest else trajectory_source
            artifacts = self._collect_artifacts(artifacts_folder)
            logger.info(f"Collected artifacts for {len(artifacts)} instance(s).")

            # Step 9: extract model_stats from each .traj file and summarise.
            metrics_execution = self._collect_metrics(artifacts)
            metrics_summary   = summarize_executions(metrics_execution)
            n_missing = metrics_summary.get("n_missing", 0)
            logger.info(
                f"Collected execution metrics for {len(metrics_execution)} instance(s) "
                f"({n_missing} missing traj file(s))."
            )

            return AgentStepResult(
                success=True,
                trajectory_source=trajectory_source.resolve(),
                copy_trajectories=self.config.copy_trajectories,
                trajectory_dest=trajectory_dest.resolve() if trajectory_dest else None,
                fix_patches_path=fix_patches_path.resolve(),
                artifacts=artifacts,
                metrics_execution=metrics_execution,
                metrics_summary=metrics_summary,
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

    def _run_agent(self, run_dir: Path) -> bool:
        """
        Run MSWE-agent on the configured benchmark.

        stdout is written to ``{run_dir}/agent.log`` only (not evaluate.log).
        stderr is written to the same file and, when ``stream_output=True``,
        also forwarded to the evaluate.py logger so it appears in evaluate.log.

        Returns:
            True  — agent ran successfully and produced trajectory output.

        Raises:
            RuntimeError — agent process exited with a non-zero code.
        """
        c = self.config.config
        script = "multirun.py" if self.config.runner.parallel else "run.py"
        venv_python = str(self.dir / self.config.setup.venv / "bin" / "python")

        env = self.setup.venv_env()
        if self.config.runner.parallel:
            env["RUNNING_THREADS"] = str(self.config.runner.threads)

        args = [
            script,
            "--model_name",              c.model_name,
            "--temperature",             str(c.temperature),
            "--top_p",                   str(c.top_p),
            "--total_cost_limit",        str(c.total_cost_limit),
            "--pr_file",                 c.benchmark_file,
            "--config_file",             c.config_file,
            "--per_instance_cost_limit", str(c.per_instance_cost_limit),
            "--cache_task_images",       str(c.cache_task_images),
            "--pre_build_all_images",    str(c.pre_build_all_images),
            "--remove_image",            str(c.remove_image),
            "--skip_existing",           str(c.skip_existing),
            "--print_config",            str(c.print_config),
            "--max_workers_build_image", str(c.max_workers_build_image),
        ]

        agent_log = run_dir / "agent.log"
        logger.info(f"Running MSWE-agent: {venv_python} {' '.join(args)}")
        logger.info(f"Agent output → {agent_log}")
        stdout, stderr, code = run_cli_command_streaming(
            venv_python, args,
            cwd=str(self.dir),
            env=env,
            log_file=agent_log,
            stream_stderr=self.config.stream_output,
        )

        if code != 0:
            raise RuntimeError(
                f"MSWE-agent exited with code {code}.\n"
                f"stderr: {stderr.strip()}"
            )

        return True

    def _collect_artifacts(self, trajectory_folder: Path) -> list:
        """
        Scan *trajectory_folder* for per-instance ``.traj`` and ``.patch`` files
        and return a list of artifact dicts.

        Expected layout inside the trajectory folder::

            {instance_id}.traj
            patches/
                {instance_id}.patch

        For each unique ``instance_id`` found (derived from either file type),
        the entry has the form::

            {
                "instance_id": "mockito__mockito-3129",
                "trajectory":  "/abs/path/mockito__mockito-3129.traj",   # or null
                "patch":       "/abs/path/patches/mockito__mockito-3129.patch"  # or null
            }

        Missing files are represented as ``null``.
        """
        patches_dir = trajectory_folder / "patches"

        # Collect all instance_ids seen in either location
        traj_files  = {p.stem: p for p in trajectory_folder.glob("*.traj")}
        patch_files = {p.stem: p for p in patches_dir.glob("*.patch")} if patches_dir.is_dir() else {}

        instance_ids = sorted(traj_files.keys() | patch_files.keys())

        artifacts = []
        for iid in instance_ids:
            traj  = traj_files.get(iid)
            patch = patch_files.get(iid)
            artifacts.append({
                "instance_id": iid,
                "trajectory":  str(traj.resolve())  if traj  else None,
                "patch":       str(patch.resolve()) if patch else None,
            })

        return artifacts

    def _collect_metrics(self, artifacts: list) -> list:
        """
        Read ``info.model_stats`` from each ``.traj`` file listed in *artifacts*
        and return a flat list of per-instance execution metric dicts.

        Each returned entry always contains ``instance_id``.  When the traj
        file exists and is valid, the numeric metric fields are included too::

            {
                "instance_id":    "mockito__mockito-3129",
                "total_cost":     5.07,
                "instance_cost":  5.07,
                "tokens_sent":    1002772,
                "tokens_received": 3666,
                "api_calls":      61
            }

        When the traj file is absent or malformed the entry only has
        ``instance_id`` (no numeric fields), which ``summarize_executions``
        counts as a missing entry.
        """
        execution = []
        for artifact in artifacts:
            entry: dict = {"instance_id": artifact["instance_id"]}
            traj_path = artifact.get("trajectory")
            if traj_path:
                stats = read_traj_metrics(Path(traj_path))
                if stats:
                    entry.update(stats)
            execution.append(entry)
        return execution

    def _discover_trajectory(self) -> Path:
        """
        Find the trajectory folder produced by the current MSWE-agent run.

        MSWE-agent writes trajectories to::

            {agent_dir}/trajectories/{username}/{run_name}/

        where ``run_name`` encodes model, benchmark, temperature, top_p, cost
        limit, and install flag (see :func:`build_run_name`).

        **Primary strategy**: construct the expected folder name deterministically
        and glob for ``*/{run_name}`` inside the trajectories root.  This is
        robust regardless of which other runs exist.

        **Fallback**: if the expected folder is absent (e.g. the config diverged
        from what the agent actually produced), scan for the most recently
        modified ``all_preds.jsonl`` and return its parent directory — the
        original behaviour.
        """
        trajectories_root = self.dir / "trajectories"
        if not trajectories_root.exists():
            raise RuntimeError(
                f"Trajectories directory not found: {trajectories_root}\n"
                "Ensure MSWE-agent has been run at least once."
            )

        # ── Primary: deterministic folder name ────────────────────────────────
        expected_name = build_run_name(self.config.config)
        logger.info(f"Looking for generated/modified trajectory folder with expected name: {expected_name}")

        matches = [p for p in trajectories_root.glob(f"*/{expected_name}") if p.is_dir()]
        if matches:
            # Normally there is exactly one; pick newest if somehow duplicated.
            folder = max(matches, key=lambda p: p.stat().st_mtime)
            logger.info(f"Trajectory folder matched by name: {folder.name}")
            return folder

        logger.warning(
            f"Expected trajectory folder '{expected_name}' not found under "
            f"{trajectories_root}; falling back to most-recently-modified search."
        )

        # ── Fallback: newest all_preds.jsonl ──────────────────────────────────
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
