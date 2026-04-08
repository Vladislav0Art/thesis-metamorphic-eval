"""
EvaluationStep — runs the multi_swe_bench evaluation harness.

Substeps executed in order
--------------------------
1. Checkout the configured git branch in the multi_swe_bench repo.
2. Ensure the Python environment is set up (venv + dependencies).
3. Resolve the path to ``fix_patches.jsonl``:
     • If AgentStep ran before this step, use its ``fix_patches_path``.
     • Otherwise use the explicit ``evaluation.config.patch_files`` from config.
4. Auto-generate ``config.json`` for the multi_swe_bench harness and write it
   to ``{run_dir}/eval/config.json``.
5. Run the multi_swe_bench harness.

Generated config.json layout
-----------------------------
All harness artefact directories are placed under ``{run_dir}/eval/`` so
every run's output is self-contained:

    {run_dir}/eval/
        config.json          ← generated here
        workdir/             ← harness internal workdir
        output/
            final_report.json  ← primary result
        repos/               ← repos cloned by harness
        logs/                ← harness log files

Standalone evaluation
---------------------
Run only the evaluation step (no agent step) by setting ``run.steps`` to
``[evaluation]`` and providing ``evaluation.config.patch_files`` explicitly
in the YAML.  The step will read that path instead of looking for an agent
result in context.
"""

import json
import os
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
from eval.metrics import summarize_eval_report
from eval.steps.base import Step, StepResult
from eval.steps.setup import Setup
from eval.config import EvaluationStepConfig

logger = logging.getLogger(__name__)


# ─── Step result ──────────────────────────────────────────────────────────────

@dataclass
class EvaluationStepResult(StepResult):
    """
    Artifacts produced by the evaluation step.

    Attributes:
        eval_config_path: Absolute path to the generated harness config.json.
        report_path:      Absolute path to final_report.json produced by the
                          harness.  The file is only present after the harness
                          actually ran (i.e. once the placeholder is replaced).
    """
    eval_config_path: Optional[Path] = None
    report_path: Optional[Path] = None
    metrics_summary: Optional[dict] = None  # from final_report.json

    def to_dict(self) -> dict:
        return {
            **super().to_dict(),
            "eval_config": str(self.eval_config_path) if self.eval_config_path else None,
            "report": str(self.report_path) if self.report_path else None,
            "metrics": {
                "summary": self.metrics_summary if self.metrics_summary is not None else {}
            },
        }


# ─── Step ─────────────────────────────────────────────────────────────────────

class EvaluationStep(Step):
    """Runs the multi_swe_bench evaluation harness."""

    def __init__(self, config: EvaluationStepConfig):
        super().__init__("evaluation")
        self.config = config
        self.dir = Path(config.dir)
        self.setup = Setup(config.setup, self.dir)

    def run(self, run_dir: Path, context: dict) -> EvaluationStepResult:
        """Execute the full evaluation pipeline."""
        try:
            # Step 1: put the repo on the right branch
            self._checkout_branch()

            # Step 2: ensure Python env (creates venv if absent, installs deps)
            self.setup.ensure()

            # Step 3: resolve where fix_patches.jsonl lives
            fix_patches_path = self._resolve_patch_files(context, run_dir)
            logger.info(f"Using fix_patches: {fix_patches_path}")

            # Step 4: generate config.json for the harness
            eval_config_path = self._generate_eval_config(fix_patches_path, run_dir)
            logger.info(f"Generated eval config: {eval_config_path}")

            # Step 5: run the harness (currently a placeholder)
            harness_ran: bool = self._run_harness(eval_config_path, run_dir)

            report_path = run_dir / "eval" / "output" / "final_report.json"
            if harness_ran and not report_path.exists():
                logger.warning(
                    f"Harness ran but final_report.json not found at {report_path}. "
                    "Check harness logs for errors."
                )

            # Read final_report.json and extract pass rate metrics.
            metrics_summary = None
            if report_path.exists():
                with open(report_path, "r", encoding="utf-8") as f:
                    report_data = json.load(f)
                metrics_summary = summarize_eval_report(report_data)
                logger.info(
                    f"Pass rate: {metrics_summary['resolved_instances']}/"
                    f"{metrics_summary['total_instances']} resolved "
                    f"({metrics_summary['pass_rate']:.1f}%)"
                )

            return EvaluationStepResult(
                success=True,
                eval_config_path=eval_config_path.resolve(),
                report_path=report_path.resolve(),
                metrics_summary=metrics_summary,
            )

        except Exception as e:
            logger.error(f"EvaluationStep failed: {e}", exc_info=True)
            return EvaluationStepResult(success=False, error=str(e))

    # ─── Substep implementations ──────────────────────────────────────────────

    def _checkout_branch(self):
        """Checkout the configured git branch inside the multi_swe_bench repo."""
        logger.info(f"Fetching remote refs in {self.dir} ...")
        stdout, stderr, code = run_cli_command("git", ["fetch"], cwd=str(self.dir))
        if code != 0:
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

    def _resolve_patch_files(self, context: dict, run_dir: Path) -> Path:
        """
        Determine the absolute path to ``fix_patches.jsonl``.

        Resolution order:
          1. AgentStepResult.fix_patches_path (when agent step ran in same run).
          2. evaluation.config.patch_files[0] (explicit config; standalone eval).

        Raises RuntimeError if neither source provides a valid path.
        """
        # Local import to avoid a circular import at module level
        from eval.steps.agent import AgentStepResult

        if "agent" in context:
            agent_result: AgentStepResult = context["agent"]
            if agent_result.fix_patches_path and agent_result.fix_patches_path.exists():
                logger.info("Resolved patch_files from agent step result.")
                return agent_result.fix_patches_path
            else:
                logger.warning(
                    "Agent step is in context but produced no fix_patches.jsonl "
                    "(placeholder run?). Falling back to evaluation.config.patch_files."
                )

        # Fallback: explicit config
        if self.config.config.patch_files:
            # TODO: why only the 1st patch extracted?
            patch_file = Path(self.config.config.patch_files[0])
            if not patch_file.exists():
                raise RuntimeError(
                    f"Explicit patch_files path does not exist: {patch_file}\n"
                    "Provide a valid path in evaluation.config.patch_files or "
                    "run the agent step first."
                )
            logger.info(f"Resolved patch_files from explicit config: {patch_file}")
            return patch_file

        raise RuntimeError(
            "Cannot resolve fix_patches.jsonl: the agent step produced no output "
            "and evaluation.config.patch_files is not set in the config."
        )

    def _generate_eval_config(self, fix_patches_path: Path, run_dir: Path) -> Path:
        """
        Auto-generate ``config.json`` for the multi_swe_bench harness.

        The file is written to ``{run_dir}/eval/config.json``.
        All harness sub-directories (workdir, output, repos, logs) are placed
        under ``{run_dir}/eval/`` to keep the run self-contained.
        """
        eval_dir = run_dir / "eval"

        # Repos directory: shared across all runs (run_dir.parent == workdir)
        # or isolated inside this run's eval/ folder.
        # Sharing avoids re-cloning on every run; the harness leaves repos on
        # their main branch with no modifications after evaluation (see
        # multi-swe-bench README), so reuse is safe.
        if self.config.share_repos:
            harness_repos = run_dir.parent / "repos"
        else:
            harness_repos = eval_dir / "repos"

        # Create all subdirectories upfront so the harness finds them ready
        harness_workdir = eval_dir / "workdir"
        harness_output  = eval_dir / "output"
        harness_logs    = eval_dir / "logs"
        for d in (harness_workdir, harness_output, harness_repos, harness_logs):
            d.mkdir(parents=True, exist_ok=True)

        config_dict = {
            "mode": "evaluation",
            "workdir":       str(harness_workdir),
            "patch_files":   [str(fix_patches_path)],
            "dataset_files": self.config.config.dataset_files,
            "force_build":   self.config.config.force_build,
            "output_dir":    str(harness_output),
            "specifics":     self.config.config.specifics,
            "skips":         self.config.config.skips,
            "repo_dir":      str(harness_repos),
            "need_clone":    self.config.config.need_clone,
            "global_env":    [],
            "clear_env":     True,
            "stop_on_error": self.config.config.stop_on_error,
            "max_workers":                self.config.config.max_workers,
            "max_workers_build_image":    self.config.config.max_workers_build_image,
            "max_workers_run_instance":   self.config.config.max_workers_run_instance,
            "log_dir":       str(harness_logs),
            "log_level":     self.config.config.log_level,
        }

        eval_config_path = eval_dir / "config.json"
        with open(eval_config_path, "w", encoding="utf-8") as f:
            json.dump(config_dict, f, indent=4)

        logger.info(f"Harness config written to {eval_config_path}")
        return eval_config_path

    def _run_harness(self, eval_config_path: Path, run_dir: Path) -> bool:
        """
        Run the multi_swe_bench evaluation harness.

        stdout is written to ``{run_dir}/harness.log`` only (not evaluate.log).
        stderr is written to the same file and, when ``stream_output=True``,
        also forwarded to the evaluate.py logger so it appears in evaluate.log.

        Returns:
            True  — harness ran successfully.

        Raises:
            RuntimeError — harness process exited with a non-zero code.
        """
        venv_python = str(self.dir / self.config.setup.venv / "bin" / "python")
        args = [
            "-m", "multi_swe_bench.harness.run_evaluation",
            "--config", str(eval_config_path),
        ]

        env = self.setup.venv_env()
        harness_log = run_dir / "harness.log"

        logger.info(f"Running multi_swe_bench harness: {venv_python} {' '.join(args)}")
        logger.info(f"Harness output → {harness_log}")
        stdout, stderr, code = run_cli_command_streaming(
            venv_python, args,
            cwd=str(self.dir),
            env=env,
            log_file=harness_log,
            stream_stderr=self.config.stream_output,
        )

        if code != 0:
            raise RuntimeError(
                f"multi_swe_bench harness exited with code {code}.\n"
                f"stderr: {stderr.strip()}"
            )

        return True
