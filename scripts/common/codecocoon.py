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
    memory_filepath: str | None = None,
):
    """
    Generate a codecocoon.yml configuration file.

    Arguments:
        - project_root: The root directory of the project to be transformed (e.g., the cloned repository path).
        - files: A list of file paths (relative to project_root) that should be considered for transformations.
        - transformations: A list of transformation configurations to apply (each with an 'id' and 'config'; config should be transformation-specific).
        - output_path: The file path where the generated codecocoon.yml should be saved.
        - memory_filepath: Optional explicit path for the CodeCocoon persistent-memory JSON file.
    """

    config = {
        'projectRoot': project_root,
        'files': files,
        'transformations': transformations
    }

    if memory_filepath is not None:
        config['memoryFilepath'] = memory_filepath

    with open(output_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
        # flushing so that the process where we run CodeCocoon sees this file
        f.flush()
        os.fsync(f.fileno())
        logger.info(f"Generated codecocoon config at {output_path} with content:\n```\n{yaml.dump(config)}\n```")


def execute_transform_metamorphic_texts(
    codecocoon_dir: str,
    memory_file: str,
    input_file: str,
    output_file: str,
    env_vars: Dict[str, str | None],
    logger,
) -> CodeCocoonResult:
    """Execute CodeCocoon transformMetamorphicTexts gradle task to sync rename/move changes into benchmark text fields."""
    logger.info(
        f"Executing transformMetamorphicTexts: memory={memory_file}, input={input_file}, output={output_file}"
    )
    stdout, stderr, code = run_cli_command(
        './gradlew',
        [
            'transformMetamorphicTexts',
            f'-PmemoryFile={memory_file}',
            f'-PinputFile={input_file}',
            f'-PoutputFile={output_file}',
        ],
        cwd=codecocoon_dir,
        env={**os.environ, **env_vars},
    )
    return CodeCocoonResult(stdout=stdout, stderr=stderr, return_code=code)


def execute_rewrite_problem_statement(
    codecocoon_dir: str,
    input_file: str,
    output_file: str,
    env_vars: Dict[str, str | None],
    logger,
) -> CodeCocoonResult:
    """Execute CodeCocoon rewriteProblemStatement gradle task to paraphrase benchmark text fields."""
    logger.info(f"Executing rewriteProblemStatement: input={input_file}, output={output_file}")
    stdout, stderr, code = run_cli_command(
        './gradlew',
        [
            'rewriteProblemStatement',
            f'-PinputFile={input_file}',
            f'-PoutputFile={output_file}',
        ],
        cwd=codecocoon_dir,
        env={**os.environ, **env_vars},
    )
    return CodeCocoonResult(stdout=stdout, stderr=stderr, return_code=code)


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

