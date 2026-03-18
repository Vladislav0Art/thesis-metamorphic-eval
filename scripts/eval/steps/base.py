"""
Base classes for the evaluation pipeline steps.

Each step is a self-contained phase orchestrated by evaluate.py:
  - AgentStep    : setup + run MSWE-agent + convert output to multi_swe_bench format
  - EvaluationStep: setup + generate config.json + run multi_swe_bench harness

Steps communicate via the `context` dict passed to `run()`. Each step deposits
its StepResult into the context so later steps can read the artifacts it produced
(e.g., EvaluationStep reads fix_patches_path from AgentStepResult).
"""

import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

# Ensure scripts/ is on sys.path so sibling packages (common/, eval/) are importable
# regardless of whether this file is run directly or imported as a module.
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import logging

logger = logging.getLogger(__name__)


# ─── Result ───────────────────────────────────────────────────────────────────

@dataclass
class StepResult:
    """
    Base result returned by every pipeline step.

    Attributes:
        success: Whether the step completed without errors.
        error:   Human-readable error message if success=False; empty string otherwise.
    """
    success: bool
    error: str = ""

    def to_dict(self) -> dict:
        """Serialize to a JSON-safe dict for inclusion in result.json."""
        return {"success": self.success, "error": self.error}


# ─── Abstract step ────────────────────────────────────────────────────────────

class Step(ABC):
    """
    Abstract base class for all evaluation pipeline steps.

    Concrete subclasses must implement `run()`. All Path arguments are absolute.
    """

    def __init__(self, name: str):
        self.name = name

    @abstractmethod
    def run(self, run_dir: Path, context: dict[str, StepResult]) -> StepResult:
        """
        Execute this step.

        Args:
            run_dir:  Absolute path to the current run's artifact directory,
                      e.g. {workdir}/run-1/. Created by the orchestrator before
                      this method is called.
            context:  Results from previously executed steps, keyed by step name.
                      Steps that depend on earlier output (e.g. EvaluationStep
                      reading fix_patches_path from AgentStepResult) look here
                      before falling back to their own config.

        Returns:
            A StepResult (or concrete subclass) describing success/failure and
            the artifacts produced by this step.
        """
        ...
