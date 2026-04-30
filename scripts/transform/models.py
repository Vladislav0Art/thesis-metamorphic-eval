from dataclasses import dataclass, field
from typing import List, Optional
from common.codecocoon import CodeCocoonResult
import os


@dataclass
class Patch:
    """
    Represents a patch to be applied to the repository.
        - name: str (used for logging purposes to identify the patch)
        - content: str (the actual patch content in git diff format)
    """
    name: str
    content: str


@dataclass
class MorphResult:
    succeeded: bool
    last_commit_sha: Optional[str] = None
    metamorphic_patch: Optional[str] = None
    codecocoon_result: Optional[CodeCocoonResult] = None


@dataclass
class EnvVar:
    name: str
    value: str | None

@dataclass
class EnvEntry:
    instance_id: str
    envs: List[EnvVar]


@dataclass
class TransformConfig:
    # required
    input: str                              # input benchmark JSONL file
    output: str                             # output metamorphic JSONL file (entries appended as processed)
    strategy: str                           # strategy name — used as key in entry["metamorphic"] and as git branch prefix
    codecocoon: str                         # path to CodeCocoon-Plugin repo root (headless mode is invoked)
    repos: str                              # directory into which benchmark repos are cloned
    # optional
    env_filepath: Optional[str] = None                  # dotenv file with ENV vars passed to CodeCocoon (e.g. GRAZIE_TOKEN)
    additional_envs_filepath: Optional[str] = None      # JSON file with per-instance ENV overrides (e.g. per-benchmark JAVA_HOME)
    transformations: Optional[str] = None               # JSON file listing CodeCocoon transformations; falls back to built-in default
    transform_test_files: bool = False                  # also pass test-patch files to CodeCocoon (default: fix-patch files only)
    override: bool = False                              # delete and recreate strategy branches if they already exist
    skip_existing_entries: bool = True                  # skip entries whose instance_id is already present in the output file
    rewrite_problem_statement: bool = False             # run rewriteProblemStatement after all code transformations


def validate_config(config: TransformConfig) -> None:
    """Raise ValueError if any path in config is invalid or missing."""
    if not os.path.exists(config.input):
        raise ValueError(f"Input file does not exist: {config.input}")
    if not os.path.exists(config.codecocoon):
        raise ValueError(f"CodeCocoon directory does not exist: {config.codecocoon}")
    if not os.path.isdir(config.codecocoon):
        raise ValueError(f"CodeCocoon path is not a directory: {config.codecocoon}")
    if config.env_filepath is not None:
        if not os.path.exists(config.env_filepath):
            raise ValueError(f"`env_filepath` does not exist: {config.env_filepath}")
        if not os.path.isfile(config.env_filepath):
            raise ValueError(f"`env_filepath` is not a file: {config.env_filepath}")
    if config.additional_envs_filepath is not None:
        if not os.path.exists(config.additional_envs_filepath):
            raise ValueError(f"`additional_envs_filepath` does not exist: {config.additional_envs_filepath}")
        if not os.path.isfile(config.additional_envs_filepath):
            raise ValueError(f"`additional_envs_filepath` is not a file: {config.additional_envs_filepath}")
