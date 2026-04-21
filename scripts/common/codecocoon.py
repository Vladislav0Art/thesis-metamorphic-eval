from typing import List, Dict
import yaml
import os
from dataclasses import dataclass
from common.cli import run_cli_command


@dataclass
class CodeCocoonResult:
    stdout: str
    stderr: str
    return_code: int


def generate_codecocoon_config(
    project_root: str,
    files: List[str],
    transformations: List[Dict],
    output_path: str,
    logger,
):
    """
    Generate a codecocoon.yml configuration file.

    Arguments:
        - project_root: The root directory of the project to be transformed (e.g., the cloned repository path).
        - files: A list of file paths (relative to project_root) that should be considered for transformations.
        - transformations: A list of transformation configurations to apply (each with an 'id' and 'config'; config should be transformation-specific).
        - output_path: The file path where the generated codecocoon.yml should be saved.
    """

    config = {
        'projectRoot': project_root,
        'files': files,
        'transformations': transformations
    }

    with open(output_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
        # flushing so that the process where we run CodeCocoon sees this file
        f.flush()
        os.fsync(f.fileno())
        logger.info(f"Generated codecocoon config at {output_path} with content:\n```\n{yaml.dump(config)}\n```")


def execute_codecocoon(
    codecocoon_dir: str,
    config_path: str,
    env_vars: Dict[str, str | None],
    logger,
) -> CodeCocoonResult:
    """Execute CodeCocoon in headless mode."""
    logger.info(f"Executing CodeCocoon with config {config_path}")
    stdout, stderr, code = run_cli_command(
        './gradlew',
        ['headless', f'-Pcodecocoon.config={config_path}'],
        cwd=codecocoon_dir,
        # merge current environment with additional env vars
        env={**os.environ, **env_vars},
    )
    return CodeCocoonResult(
        stdout=stdout,
        stderr=stderr,
        return_code=code,
    )

