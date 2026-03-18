"""
Configuration loader for evaluate.py.

Defines the full dataclass schema that mirrors the YAML config file, and
provides ``load_config()`` which parses the YAML and resolves all paths.

Path resolution
---------------
Every path value in the YAML is resolved relative to the *config file's own
directory* (not the CWD from which evaluate.py is invoked).  Absolute paths
are kept as-is.  This means you can place the config file anywhere and all
``dir:``, ``benchmark_file:`` etc. paths will be interpreted relative to it,
making the config portable within the project tree.

Schema overview (mirrors evaluate.example.yaml)
------------------------------------------------
run:
  workdir:  str
  steps:    List[str]
  N:        int

steps:
  agent:
    dir, branch, setup, keys, runner, config, copy_trajectories
  evaluation:
    dir, branch, setup, config
"""

import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

import yaml

# Ensure scripts/ is on sys.path
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

# SetupConfig lives in steps/setup.py (tightly coupled to the Setup class)
from eval.steps.setup import SetupConfig


# ─── RunConfig ────────────────────────────────────────────────────────────────

@dataclass
class RunConfig:
    """
    Top-level execution settings.

    Attributes:
        workdir: Absolute path where ALL run artifacts are stored.
                 Subdirectory ``run-1/`` (and future ``run-N/``) will be
                 created here automatically.
        steps:   Ordered list of step names to execute.
                 Valid values: ``"agent"``, ``"evaluation"``.
        N:       Number of evaluation runs.  Currently ignored (only run-1
                 is executed); reserved for future multi-run support.
    """
    workdir: str
    steps: List[str]
    N: int = 1


# ─── Agent step config ────────────────────────────────────────────────────────

@dataclass
class KeysConfig:
    """
    Controls generation of the MSWE-agent ``keys.cfg`` file.

    Attributes:
        path:     Path to keys.cfg, relative to the agent dir.
        override: If True, overwrite an existing keys.cfg on every run.
                  If False (default), skip generation when the file exists.
        values:   Dict of ``KEY: "value"`` pairs written as ``KEY="value"``
                  lines, matching the format expected by MSWE-agent.
    """
    path: str
    override: bool
    values: Dict[str, str]


@dataclass
class RunnerConfig:
    """
    Controls which MSWE-agent runner script to use.

    Attributes:
        parallel: False → ``run.py`` (serial).
                  True  → ``multirun.py`` (parallel instances); sets
                  ``RUNNING_THREADS`` env var to ``threads``.
        threads:  Value for ``RUNNING_THREADS`` when ``parallel=True``.
    """
    parallel: bool = False
    threads: int = 16


@dataclass
class AgentRunConfig:
    """
    MSWE-agent ``run.py`` / ``multirun.py`` CLI parameters.
    Field names map 1-to-1 to the corresponding CLI flags.
    All path fields are absolute after loading.
    """
    model_name: str
    benchmark_file: str           # --pr_file
    config_file: str              # --config_file
    per_instance_cost_limit: float
    cache_task_images: bool = True
    pre_build_all_images: bool = True
    remove_image: bool = False
    skip_existing: bool = True
    print_config: bool = False
    max_workers_build_image: int = 16


@dataclass
class AgentStepConfig:
    """Full configuration for the agent step."""
    dir: str                      # absolute path to MSWE-agent repo root
    branch: str                   # git branch to checkout before running
    setup: SetupConfig
    keys: KeysConfig
    runner: RunnerConfig
    config: AgentRunConfig
    copy_trajectories: bool = True  # copy trajectory folder into run_dir


# ─── Evaluation step config ───────────────────────────────────────────────────

@dataclass
class EvalHarnessConfig:
    """
    Parameters for the auto-generated ``multi_swe_bench`` harness config.json.

    ``patch_files`` is intentionally Optional:
      - When the agent step ran first, it is auto-resolved from AgentStepResult.
      - When running the evaluation step standalone, it must be set explicitly.

    All path fields are absolute after loading.
    """
    dataset_files: List[str]
    patch_files: Optional[List[str]] = None   # None = auto-resolve from agent step
    force_build: bool = False
    stop_on_error: bool = True
    need_clone: bool = True
    max_workers: int = 8
    max_workers_build_image: int = 8
    max_workers_run_instance: int = 8
    log_level: str = "DEBUG"
    specifics: List[str] = field(default_factory=list)
    skips: List[str] = field(default_factory=list)


@dataclass
class EvaluationStepConfig:
    """Full configuration for the evaluation step."""
    dir: str                      # absolute path to multi_swe_bench repo root
    branch: str                   # git branch to checkout before running
    setup: SetupConfig
    config: EvalHarnessConfig


# ─── Top-level config ─────────────────────────────────────────────────────────

@dataclass
class StepsConfig:
    """Container for per-step configurations.  Either field may be None if
    the corresponding step is not present in the YAML."""
    agent: Optional[AgentStepConfig] = None
    evaluation: Optional[EvaluationStepConfig] = None


@dataclass
class EvalConfig:
    """Root configuration object returned by ``load_config()``."""
    run: RunConfig
    steps: StepsConfig


# ─── Path helpers ─────────────────────────────────────────────────────────────

def _resolve(path: str, base: Path) -> str:
    """Resolve *path* relative to *base*.  Absolute paths are kept as-is."""
    p = Path(path)
    return str(p if p.is_absolute() else (base / p).resolve())


def _resolve_list(paths: List[str], base: Path) -> List[str]:
    return [_resolve(p, base) for p in paths]


# ─── Loader ───────────────────────────────────────────────────────────────────

def load_config(config_filepath: str) -> EvalConfig:
    """
    Load and validate the YAML config file.

    All relative paths are resolved relative to the config file's directory.

    Args:
        config_filepath: Path to the YAML config file (absolute or relative
                         to the process CWD).

    Returns:
        Fully populated EvalConfig with all paths resolved to absolute form.

    Raises:
        FileNotFoundError: if the config file does not exist.
        KeyError / ValueError: if required fields are missing or malformed.
    """
    config_path = Path(config_filepath).resolve()
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    base = config_path.parent  # all relative paths resolved from here

    with open(config_path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)

    run_raw = raw.get("run", {})
    steps_raw = raw.get("steps", {})

    # ── RunConfig ─────────────────────────────────────────────────────────────
    run_config = RunConfig(
        workdir=_resolve(run_raw["workdir"], base),
        steps=run_raw.get("steps", []),
        N=run_raw.get("N", 1),
    )

    # ── AgentStepConfig ───────────────────────────────────────────────────────
    agent_config = None
    if "agent" in steps_raw:
        a = steps_raw["agent"]
        agent_dir = _resolve(a["dir"], base)

        s = a["setup"]
        k = a["keys"]
        r = a.get("runner", {})
        c = a["config"]

        agent_config = AgentStepConfig(
            dir=agent_dir,
            branch=a["branch"],
            setup=SetupConfig(
                venv=s["venv"],
                prepare=s.get("prepare", []),
                install=s.get("install", []),
            ),
            keys=KeysConfig(
                path=k["path"],
                override=k.get("override", False),
                # values may be a plain dict in YAML
                values=k.get("values", {}),
            ),
            runner=RunnerConfig(
                parallel=r.get("parallel", False),
                threads=r.get("threads", 16),
            ),
            config=AgentRunConfig(
                model_name=c["model_name"],
                benchmark_file=_resolve(c["benchmark_file"], base),
                config_file=_resolve(c["config_file"], base),
                per_instance_cost_limit=float(c["per_instance_cost_limit"]),
                cache_task_images=c.get("cache_task_images", True),
                pre_build_all_images=c.get("pre_build_all_images", True),
                remove_image=c.get("remove_image", False),
                skip_existing=c.get("skip_existing", True),
                print_config=c.get("print_config", False),
                max_workers_build_image=c.get("max_workers_build_image", 16),
            ),
            copy_trajectories=a.get("copy_trajectories", True),
        )

    # ── EvaluationStepConfig ──────────────────────────────────────────────────
    eval_config = None
    if "evaluation" in steps_raw:
        e = steps_raw["evaluation"]
        eval_dir = _resolve(e["dir"], base)

        s = e["setup"]
        c = e["config"]

        patch_files_raw = c.get("patch_files")

        eval_config = EvaluationStepConfig(
            dir=eval_dir,
            branch=e["branch"],
            setup=SetupConfig(
                venv=s["venv"],
                prepare=s.get("prepare", []),
                install=s.get("install", []),
            ),
            config=EvalHarnessConfig(
                dataset_files=_resolve_list(c["dataset_files"], base),
                patch_files=_resolve_list(patch_files_raw, base) if patch_files_raw else None,
                force_build=c.get("force_build", False),
                stop_on_error=c.get("stop_on_error", True),
                need_clone=c.get("need_clone", True),
                max_workers=c.get("max_workers", 8),
                max_workers_build_image=c.get("max_workers_build_image", 8),
                max_workers_run_instance=c.get("max_workers_run_instance", 8),
                log_level=c.get("log_level", "DEBUG"),
                specifics=c.get("specifics", []),
                skips=c.get("skips", []),
            ),
        )

    return EvalConfig(
        run=run_config,
        steps=StepsConfig(agent=agent_config, evaluation=eval_config),
    )
