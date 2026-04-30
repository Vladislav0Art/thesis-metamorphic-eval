import argparse
import json
import os
import sys
import logging
import yaml
from pathlib import Path
from typing import Dict, List, NamedTuple
from dotenv import dotenv_values
from default.defaults import DEFAULT_CODE_COCCOON_TRANSFORMATIONS
from common.logger import configure_logging
from common.fs import read_jsonl, write_jsonl, append_jsonl, make_absolute_path
from common.git import (
    clone_repository,
    diff_between_commits,
    branch_exists,
    delete_branch,
    checkout_branch,
    extract_changed_files,
)
from common.codecocoon import (
    generate_codecocoon_config,
    execute_transform_metamorphic_texts,
    execute_rewrite_problem_statement,
)
from transform.models import (
    Patch,
    MorphResult,
    EnvVar,
    EnvEntry,
    TransformConfig,
)
from transform.morph import (
    morph,
    insert_metamorphic_log,
)


description="""
This script accepts a YAML config file and applies CodeCocoon-Plugin metamorphic transformations
to each benchmark entry in the input JSONL file, writing results to the output JSONL file.

Usage:
  python transform.py --config path/to/transform.yaml

See transform.example.yaml in the repository root for a fully annotated config template.
"""

# Configure logging
configure_logging(log_filename="transform.log", level=logging.INFO)

logger = logging.getLogger(__name__)


RENAMING_MOVING_TRANSFORMATION_IDS = {
    "rename-class-transformation",
    "rename-method-transformation",
    "rename-variable-transformation",
    "move-file-into-suggested-directory-transformation/ai",
    "move-file-into-suggested-directory-transformation/config",
}


def has_renaming_or_moving_transformations(transformations: List[Dict]) -> bool:
    return any(t.get('id') in RENAMING_MOVING_TRANSFORMATION_IDS for t in transformations)


# ─── Internal result type ─────────────────────────────────────────────────────

class _CodeMorphingResult(NamedTuple):
    strategy_entry:        Dict
    metamorphic_base_patch: str
    new_morphed_test_patch: str
    new_morphed_fix_patch:  str
    artifacts_dir:         str
    memory_filepath:       str


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _run_rewrite_problem_statement(
    codecocoon_dir: str,
    input_file: str,
    output_file: str,
    env_vars: Dict[str, str | None],
):
    """Execute rewriteProblemStatement and parse the output if successful.

    Returns ``(raw_result, parsed_output_or_None)``.  The caller handles
    logging and result application so it can also build the audit-log dict
    for ``strategy_entry["text_transformations"]``.
    """
    raw = execute_rewrite_problem_statement(
        codecocoon_dir=codecocoon_dir,
        input_file=input_file,
        output_file=output_file,
        env_vars=env_vars,
        logger=logger,
    )
    if raw.return_code == 0:
        with open(output_file) as f:
            return raw, json.load(f)
    return raw, None


def _apply_code_morphing(
    entry: Dict,
    strategy: str,
    transformations: List[Dict],
    transformations_filepath: str | None,
    codecocoon_dir: str,
    repos_dir: str,
    env_vars: Dict[str, str | None],
    transform_test_files: bool,
    override: bool,
) -> _CodeMorphingResult | None:
    """Run all CodeCocoon code-morphing steps (Steps 1–5).

    Covers: cloning the repo, branch management, file extraction, CodeCocoon
    config generation, and the three morph passes (base, test, fix) plus diff
    generation.

    Returns a ``_CodeMorphingResult`` on success, or ``None`` if any step
    fails or is skipped (branches already exist + ``override=False``, no Java
    files found, morph failure, etc.).  The caller writes the results back to
    ``entry``.
    """
    instance_id = entry['instance_id']

    strategy_entry: Dict = {
        "strategy": {
            "name":   strategy,
            "config": transformations_filepath,
        },
    }

    # Step 1: Clone repository
    repo_url = build_github_url(entry['org'], entry['repo'])
    repo_dir = os.path.join(repos_dir, strategy, instance_id, "repo")
    base_sha = entry['base']['sha']

    if not clone_repository(repo_url, repo_dir, base_sha, logger):
        logger.error(f"Failed to clone repository for {instance_id}")
        return None

    # Step 1.5: Check / delete transformation branches
    base_branch = f"{strategy}-base-transformation"
    test_branch = f"{strategy}-test-transformation"
    fix_branch  = f"{strategy}-fix-transformation"

    base_exists = branch_exists(repo_dir, base_branch, logger)
    test_exists = branch_exists(repo_dir, test_branch, logger)
    fix_exists  = branch_exists(repo_dir, fix_branch,  logger)

    if (base_exists or test_exists or fix_exists) and not override:
        logger.info(
            f"Branches for strategy '{strategy}' already exist. "
            "Skipping transformation (use --override to regenerate)."
        )
        return None

    if override and (base_exists or test_exists or fix_exists):
        logger.info(f"Override enabled: Deleting existing branches for strategy '{strategy}'")
        if base_exists and not delete_branch(repo_dir, base_branch, logger):
            logger.error(f"Failed to delete base branch '{base_branch}'")
            return None
        if test_exists and not delete_branch(repo_dir, test_branch, logger):
            logger.error(f"Failed to delete test branch '{test_branch}'")
            return None
        if fix_exists and not delete_branch(repo_dir, fix_branch, logger):
            logger.error(f"Failed to delete fix branch '{fix_branch}'")
            return None

    # Step 2: Extract changed files (Java only — CodeCocoon handles only Java)
    fix_files  = extract_changed_files(patch=entry.get('fix_patch',  ''), logger=logger)
    test_files = extract_changed_files(patch=entry.get('test_patch', ''), logger=logger)

    if transform_test_files:
        files_to_transform = list(set(fix_files + test_files))
        logger.info(f"Transforming files FROM BOTH FIX AND TEST PATCHES for {instance_id}")
    else:
        files_to_transform = list(set(fix_files))
        logger.info(f"Transforming files modified ONLY BY FIX PATCH for {instance_id}")

    java_files     = [f for f in files_to_transform if     f.endswith('.java')]
    non_java_files = [f for f in files_to_transform if not f.endswith('.java')]

    if non_java_files:
        non_java_str = ''.join([f"\n     - {f}" for f in non_java_files])
        logger.info(f"Filtered out {len(non_java_files)} non-Java file(s) (not passed to CodeCocoon):{non_java_str}")

    files_to_transform = java_files

    if not files_to_transform:
        logger.warning(f"No files found in patches for {instance_id}")
        return None

    files_str = ''.join([f"\n     - {f}" for f in files_to_transform])
    logger.info(f"Extracted {len(files_to_transform)} unique changed files:{files_str}")

    # Step 3: Generate CodeCocoon config
    config_path     = os.path.join(repos_dir, strategy, instance_id, "codecocoon.yml")
    artifacts_dir   = os.path.join(repos_dir, strategy, instance_id, ".codecocoon-artifacts")
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    os.makedirs(artifacts_dir, exist_ok=True)
    memory_filepath = os.path.join(artifacts_dir, "memory.json")

    generate_codecocoon_config(
        project_root=repo_dir,
        files=files_to_transform,
        transformations=transformations,
        output_path=config_path,
        memory_filepath=memory_filepath,
        logger=logger,
    )

    # Step 4a: Base morph
    logger.info("=====================================================================")
    logger.info("===== STEP 1: Applying metamorphic modifications to base commit =====")
    logger.info("=====================================================================")

    if not checkout_branch(repo_dir, base_sha, logger, create=False):
        logger.error(f"Failed to checkout base SHA {base_sha}")
        return None

    base_morph_result: MorphResult = morph(
        repo_dir=repo_dir,
        patches=[],
        env_vars=env_vars,
        branch=base_branch,
        metamorphic_commit_msg="[transform.py] Apply metamorphic modifications on: base commit",
        codecocoon_dir=codecocoon_dir,
        config_path=config_path,
        logger=logger,
    )

    if base_morph_result.succeeded is False:
        logger.error("Failed to apply base metamorphic transformations")
        return None

    metamorphic_base_commit: str = base_morph_result.last_commit_sha
    metamorphic_base_patch:  str = base_morph_result.metamorphic_patch

    strategy_entry["repo"] = {
        "instance_id": instance_id,
        "path":        repo_dir,
        "branches":    {"base": base_branch, "test": test_branch, "fix": fix_branch},
    }
    strategy_entry["metamorphic_patches"] = {}
    strategy_entry["metamorphic_patches"]["base"] = {
        "patch": {
            "description": "CodeCocoon transformations applied on the original base commit",
            "value": metamorphic_base_patch,
        },
        "commit": metamorphic_base_commit,
        "branch": base_branch,
    }
    insert_metamorphic_log(
        strategy_entry=strategy_entry, label="base_metamorphic_transformation_log",
        applied_to="base", result=base_morph_result.codecocoon_result, logger=logger,
    )
    logger.info(f"Base metamorphic transformation complete. Commit: {metamorphic_base_commit}")

    # Step 4b: Test morph
    logger.info("===================================================================")
    logger.info("===== STEP 2: Applying test_patch + metamorphic modifications =====")
    logger.info("===================================================================")

    if not checkout_branch(repo_dir, base_sha, logger, create=False):
        logger.error(f"Failed to checkout base SHA {base_sha}")
        return None

    test_patch = entry.get('test_patch', '')
    test_morph_result: MorphResult = morph(
        repo_dir=repo_dir,
        patches=[Patch(name="test_patch", content=test_patch)] if test_patch else [],
        env_vars=env_vars,
        branch=test_branch,
        metamorphic_commit_msg="[transform.py] Apply metamorphic modifications on: base commit + test_patch (pre-committed)",
        codecocoon_dir=codecocoon_dir,
        config_path=config_path,
        logger=logger,
    )

    if test_morph_result.succeeded is False:
        logger.error("Failed to apply test metamorphic transformations")
        return None

    metamorphic_test_commit = test_morph_result.last_commit_sha
    _metamorphic_test_patch = test_morph_result.metamorphic_patch
    logger.info(f"Test metamorphic transformation complete. Commit: {metamorphic_test_commit}")

    strategy_entry["metamorphic_patches"]["test"] = {
        "patch": {
            "description": "CodeCocoon transformations applied on the base commit with original test_patch pre-applied (base + test_patch)",
            "value": _metamorphic_test_patch,
        },
        "commit": metamorphic_test_commit,
        "branch": test_branch,
    }
    insert_metamorphic_log(
        strategy_entry=strategy_entry, label="test_metamorphic_transformation_log",
        applied_to="test", result=test_morph_result.codecocoon_result, logger=logger,
    )

    # Step 4c: Generate new_morphed_test_patch
    logger.info("=====================================================")
    logger.info("===== STEP 3: Generating new_morphed_test_patch =====")
    logger.info("=====================================================")

    new_morphed_test_patch = diff_between_commits(
        repo_dir=repo_dir, base=metamorphic_base_commit,
        another=metamorphic_test_commit, logger=logger,
    )
    if not new_morphed_test_patch:
        logger.error("Failed to generate new_morphed_test_patch")
        return None

    strategy_entry["metamorphic_patches"]["test"]["original_patch"] = test_patch
    strategy_entry["metamorphic_patches"]["test"]["new_morphed_test_patch"] = {
        "description": (
            "Difference between 1) metamorphically transformed base commit and "
            "2) metamorphically transformed base + original test_patch "
            "(replaces original `test_patch` field)"
        ),
        "value": new_morphed_test_patch,
    }

    # Step 4d: Fix morph
    logger.info("==================================================================")
    logger.info("===== STEP 4: Applying fix_patch + metamorphic modifications =====")
    logger.info("==================================================================")

    if not checkout_branch(repo_dir, base_sha, logger, create=False):
        logger.error(f"Failed to checkout base SHA {base_sha}")
        return None

    fix_patch = entry.get('fix_patch', '')
    fix_morph_result: MorphResult = morph(
        repo_dir=repo_dir,
        patches=[Patch(name="fix_patch", content=fix_patch)] if fix_patch else [],
        env_vars=env_vars,
        branch=fix_branch,
        metamorphic_commit_msg="[transform.py] Apply metamorphic modifications on: base commit + fix_patch (pre-committed)",
        codecocoon_dir=codecocoon_dir,
        config_path=config_path,
        logger=logger,
    )

    if fix_morph_result.succeeded is False:
        logger.error("Failed to apply fix metamorphic transformations")
        return None

    metamorphic_fix_commit = fix_morph_result.last_commit_sha
    _metamorphic_fix_patch = fix_morph_result.metamorphic_patch
    logger.info(f"Fix metamorphic transformation complete. Commit: {metamorphic_fix_commit}")

    strategy_entry["metamorphic_patches"]["fix"] = {
        "patch": {
            "description": "CodeCocoon transformations applied on the base commit with original fix_patch pre-applied (base + fix_patch)",
            "value": _metamorphic_fix_patch,
        },
        "commit": metamorphic_fix_commit,
        "branch": fix_branch,
    }
    insert_metamorphic_log(
        strategy_entry=strategy_entry, label="fix_metamorphic_transformation_log",
        applied_to="fix", result=fix_morph_result.codecocoon_result, logger=logger,
    )

    # Step 4e: Generate new_morphed_fix_patch
    logger.info("====================================================")
    logger.info("===== STEP 5: Generating new_morphed_fix_patch =====")
    logger.info("====================================================")

    new_morphed_fix_patch = diff_between_commits(
        repo_dir=repo_dir, base=metamorphic_base_commit,
        another=metamorphic_fix_commit, logger=logger,
    )
    if not new_morphed_fix_patch:
        logger.error("Failed to generate new_morphed_fix_patch")
        return None

    strategy_entry["metamorphic_patches"]["fix"]["original_patch"] = fix_patch
    strategy_entry["metamorphic_patches"]["fix"]["new_morphed_fix_patch"] = {
        "description": (
            "Difference between 1) metamorphically transformed base commit and "
            "2) metamorphically transformed base + original fix_patch "
            "(replaces original `fix_patch` field)"
        ),
        "value": new_morphed_fix_patch,
    }

    logger.info(
        f"Code morphing complete for {instance_id} "
        f"(base: {base_branch}, test: {test_branch}, fix: {fix_branch})"
    )

    return _CodeMorphingResult(
        strategy_entry=strategy_entry,
        metamorphic_base_patch=metamorphic_base_patch,
        new_morphed_test_patch=new_morphed_test_patch,
        new_morphed_fix_patch=new_morphed_fix_patch,
        artifacts_dir=artifacts_dir,
        memory_filepath=memory_filepath,
    )


def build_github_url(org: str, repo: str) -> str:
    """Build GitHub repository URL."""
    return f"https://github.com/{org}/{repo}.git"


def load_transform_config(config_filepath: str) -> TransformConfig:
    """Load and validate a TransformConfig from a YAML file. Relative paths are resolved
    relative to the config file's own directory."""
    config_dir = os.path.dirname(os.path.abspath(config_filepath))

    def resolve(path: str | None) -> str | None:
        if path is None:
            return None
        return path if os.path.isabs(path) else os.path.abspath(os.path.join(config_dir, path))

    with open(config_filepath, 'r') as f:
        raw = yaml.safe_load(f)

    for field in ('input', 'output', 'strategy', 'codecocoon', 'repos'):
        if field not in raw or not raw[field]:
            raise ValueError(f"Missing required field '{field}' in config: {config_filepath}")

    return TransformConfig(
        input=resolve(raw['input']),
        output=resolve(raw['output']),
        strategy=raw['strategy'],
        codecocoon=resolve(raw['codecocoon']),
        repos=resolve(raw['repos']),
        env_filepath=resolve(raw.get('env_filepath')),
        additional_envs_filepath=resolve(raw.get('additional_envs_filepath')),
        transformations=resolve(raw.get('transformations')),
        transform_test_files=raw.get('transform_test_files', False),
        override=raw.get('override', False),
        skip_existing_entries=raw.get('skip_existing_entries', True),
        rewrite_problem_statement=raw.get('rewrite_problem_statement', False),
    )


def load_codecoccoon_transformations(from_filepath: str | None) -> List[Dict] | None:
    def is_transformation_schema(transformation) -> bool:
        # NOTE: if transformation accepts zero config params, its config still needs to be defined
        #       as an empty dict (i.e., "config": {}) to be valid
        return isinstance(transformation, dict) and ('id' in transformation) and ('config' in transformation)

    if from_filepath is None:
        logger.info(
        f"No file with transformations provided, using default transformations:\n{json.dumps(DEFAULT_CODE_COCCOON_TRANSFORMATIONS, indent=3)}")
        return DEFAULT_CODE_COCCOON_TRANSFORMATIONS

    try:
        with open(from_filepath, 'r') as f:
            transformations = json.load(f)
        # validate that it is a list of dicts
        if not isinstance(transformations, list) or not all(is_transformation_schema(t) for t in transformations):
            raise ValueError(f"Transformations file must contain a JSON list of objects, got {transformations}")

        logger.info(f"Loaded transformations from file: {from_filepath}")
        return transformations
    except Exception as e:
        logger.error(f"Failed to load transformations file: {e}")
        return None


def process_entry(
    entry: Dict,
    strategy: str,
    codecocoon_dir: str,
    transformations: List[Dict],
    transformations_filepath: str | None,
    repos_dir: str,
    env_vars: Dict[str, str | None],
    transform_test_files: bool,
    override: bool,
    rewrite_problem_statement: bool,
) -> Dict:
    """Process a single entry through the transformation pipeline."""
    instance_id = entry['instance_id']
    logger.info(f"Processing entry: {instance_id}")
    logger.info(f"ENV variables: [{', '.join(env_vars.keys())}]")

    if "metamorphic" not in entry:
        entry["metamorphic"] = []

    # No code transformations: skip morphing; optionally rewrite problem statement only.
    # The resulting entry is identical to the original except for potentially updated
    # title/body/resolved_issues fields.
    if not transformations:
        logger.info(
            f"No code transformations defined for strategy '{strategy}' — "
            "skipping all CodeCocoon morphing (branch creation, base/test/fix morphing)."
        )
        if rewrite_problem_statement:
            logger.info("=========================================================================================")
            logger.info("===== Problem statement rewrite (no code transformations) =====")
            logger.info("=========================================================================================")
            artifacts_dir = os.path.join(repos_dir, strategy, instance_id, ".codecocoon-artifacts")
            os.makedirs(artifacts_dir, exist_ok=True)
            ps_input     = os.path.join(artifacts_dir, "ps_input.json")
            ps_rewritten = os.path.join(artifacts_dir, "ps_rewritten.json")
            input_record = {k: entry[k] for k in ("title", "body", "resolved_issues") if k in entry}
            with open(ps_input, "w") as f:
                json.dump(input_record, f, indent=2)
            rps_raw, rps_output = _run_rewrite_problem_statement(
                codecocoon_dir=codecocoon_dir,
                input_file=ps_input,
                output_file=ps_rewritten,
                env_vars=env_vars,
            )
            if rps_output is not None:
                for key in ("title", "body", "resolved_issues"):
                    if key in rps_output:
                        entry[key] = rps_output[key]
                logger.info(f"rewriteProblemStatement succeeded: title={entry.get('title', '')[:80]!r}")
            else:
                logger.error(
                    f"rewriteProblemStatement failed (return_code={rps_raw.return_code}); "
                    "keeping original problem statement"
                )
        else:
            logger.info("rewrite_problem_statement=false — returning entry unchanged.")
        return entry

    try:
        morph_result = _apply_code_morphing(
            entry=entry,
            strategy=strategy,
            transformations=transformations,
            transformations_filepath=transformations_filepath,
            codecocoon_dir=codecocoon_dir,
            repos_dir=repos_dir,
            env_vars=env_vars,
            transform_test_files=transform_test_files,
            override=override,
        )

        if morph_result is None:
            return entry

        # Commit morphing results to entry.
        strategy_entry = morph_result.strategy_entry
        entry["metamorphic"].append(strategy_entry)
        if morph_result.metamorphic_base_patch:
            entry['base']['metamorphic_base_patch'] = morph_result.metamorphic_base_patch
        entry['base']['strategy'] = strategy
        entry['test_patch'] = morph_result.new_morphed_test_patch
        entry['fix_patch']  = morph_result.new_morphed_fix_patch

        logger.info("====================================================================================================================")
        logger.info("===== STEP 6: Committed morphed patches and metamorphic_base_patch into 'base' =====")
        logger.info("====================================================================================================================")

        # Step 7: Problem statement text transformations
        has_rename_move = has_renaming_or_moving_transformations(transformations)
        if not has_rename_move and not rewrite_problem_statement:
            return entry

        logger.info("=========================================================================================")
        logger.info("===== STEP 7: Problem statement text transformations =====")
        logger.info("=========================================================================================")

        artifacts_dir   = morph_result.artifacts_dir
        memory_filepath = morph_result.memory_filepath
        ps_input     = os.path.join(artifacts_dir, "ps_input.json")
        ps_renamed   = os.path.join(artifacts_dir, "ps_renamed.json")
        ps_rewritten = os.path.join(artifacts_dir, "ps_rewritten.json")

        input_record = {k: entry[k] for k in ("title", "body", "resolved_issues") if k in entry}
        with open(ps_input, 'w') as f:
            json.dump(input_record, f, indent=2)
        logger.info(f"Wrote problem statement input snapshot to {ps_input}")

        strategy_entry["text_transformations"] = {"input": input_record}
        current_ps_path = ps_input

        # 7a: transformMetamorphicTexts — required when rename/move transforms are present
        # so that renamed identifiers in code are reflected in the problem statement.
        if has_rename_move:
            logger.info("Running transformMetamorphicTexts (rename/move transforms detected — required)")
            tmt_result = execute_transform_metamorphic_texts(
                codecocoon_dir=codecocoon_dir,
                memory_file=memory_filepath,
                input_file=ps_input,
                output_file=ps_renamed,
                env_vars=env_vars,
                logger=logger,
            )
            tmt_log: Dict = {"applied": tmt_result.return_code == 0, "result": tmt_result.__dict__}
            if tmt_result.return_code == 0:
                with open(ps_renamed) as f:
                    tmt_output = json.load(f)
                tmt_log["output"] = tmt_output
                current_ps_path = ps_renamed
                logger.info("transformMetamorphicTexts succeeded")
            else:
                logger.error(
                    f"transformMetamorphicTexts failed (return_code={tmt_result.return_code}); "
                    "keeping original problem statement"
                )
            strategy_entry["text_transformations"]["transform_metamorphic_texts"] = tmt_log

        # 7b: rewriteProblemStatement — runs on current_ps_path (may already be renamed)
        if rewrite_problem_statement:
            logger.info(f"Running rewriteProblemStatement on {current_ps_path}")
            rps_raw, rps_output = _run_rewrite_problem_statement(
                codecocoon_dir=codecocoon_dir,
                input_file=current_ps_path,
                output_file=ps_rewritten,
                env_vars=env_vars,
            )
            rps_log: Dict = {"applied": rps_raw.return_code == 0, "result": rps_raw.__dict__}
            if rps_output is not None:
                rps_log["output"] = rps_output
                current_ps_path = ps_rewritten
                logger.info("rewriteProblemStatement succeeded")
            else:
                logger.error(
                    f"rewriteProblemStatement failed (return_code={rps_raw.return_code}); "
                    "keeping current problem statement"
                )
            strategy_entry["text_transformations"]["rewrite_problem_statement"] = rps_log

        if current_ps_path != ps_input:
            with open(current_ps_path) as f:
                final_ps = json.load(f)
            for key in ("title", "body", "resolved_issues"):
                if key in final_ps:
                    entry[key] = final_ps[key]
            logger.info(
                f"Updated entry text fields from {current_ps_path}: "
                f"title={entry.get('title', '')[:80]!r}"
            )

    except Exception as e:
        logger.error(f"Failed to process {instance_id}: {e}", exc_info=True)

    return entry




def load_additional_envs(filepath: str | None) -> List[EnvEntry]:
    """Parse a JSON file of per-instance ENV overrides into a list of EnvEntry objects.
    Returns an empty list when filepath is None."""
    if filepath is None:
        return []

    with open(filepath) as f:
        envs_data = json.load(f)
    logger.info(f"Loaded additional per-instance ENVs from {filepath}")

    result: List[EnvEntry] = []
    for entry in envs_data:
        if ('instance_id' not in entry) or ('envs' not in entry) or (not isinstance(entry['envs'], list)):
            logger.error(f"Malformed entry in additional ENVs file (missing 'instance_id' or 'envs' list): {entry}")
            sys.exit(1)
        instance_id = entry['instance_id']
        envs: List[EnvVar] = []
        for env in entry['envs']:
            if ('name' not in env) or ('value' not in env):
                logger.error(f"Malformed env entry for '{instance_id}' (missing 'name' or 'value'): {env}")
                sys.exit(1)
            envs.append(EnvVar(name=env['name'], value=env['value']))
        result.append(EnvEntry(instance_id=instance_id, envs=envs))
    return result


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


def main():
    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--config', type=str, required=True,
                        help="Path to the YAML config file (see transform.example.yaml)")
    args = parser.parse_args()

    config: TransformConfig = load_transform_config(args.config)

    logger.info(f"""Config loaded from {args.config}:
      input:                     {config.input}
      output:                    {config.output}
      strategy:                  {config.strategy}
      codecocoon:                {config.codecocoon}
      transformations:           {config.transformations}
      repos:                     {config.repos}
      env_filepath:              {config.env_filepath}
      additional_envs_filepath:  {config.additional_envs_filepath}
      transform_test_files:      {config.transform_test_files}
      override:                  {config.override}
      skip_existing_entries:     {config.skip_existing_entries}
      rewrite_problem_statement: {config.rewrite_problem_statement}
    """)

    try:
        validate_config(config)
    except ValueError as e:
        logger.error(f"Config validation failed: {e}")
        return

    # Load common ENV variables from env file (if provided)
    if config.env_filepath is not None:
        env_vars = dotenv_values(config.env_filepath)
        logger.info(f"Loaded {len(env_vars)} ENV variable(s) from {config.env_filepath}: {', '.join(env_vars.keys())}")
    else:
        logger.info("`env_filepath` not provided: no additional ENV variables loaded")
        env_vars = {}

    additional_envs: List[EnvEntry] = load_additional_envs(config.additional_envs_filepath)

    transformations = load_codecoccoon_transformations(from_filepath=config.transformations)
    if transformations is None:
        logger.error("Failed to load transformations, terminating execution.")
        return

    logger.info(f"Creating repos directory if it doesn't exist: {config.repos}")
    Path(config.repos).mkdir(parents=True, exist_ok=True)

    entries = read_jsonl(config.input)

    already_processed: set[str] = set()
    if config.skip_existing_entries and os.path.exists(config.output):
        existing = read_jsonl(config.output)
        already_processed = {e["instance_id"] for e in existing if "instance_id" in e}
        logger.info(f"Resuming: {len(already_processed)} already-processed entries found in {config.output}")

    for i, entry in enumerate(entries, 1):
        instance_id = entry["instance_id"]
        logger.info("==========================================================================")
        logger.info(f"====== ⌛ Processing entry '{instance_id}' ({i}/{len(entries)}) ======")

        if config.skip_existing_entries and instance_id in already_processed:
            logger.info(f"Skipping '{instance_id}': already present in output file")
            logger.info(f"====== ⏭️  Skipped entry '{instance_id}' ({i}/{len(entries)}) ======")
            logger.info("==========================================================================")
            continue

        instance_env_vars = dict(env_vars)
        for env_entry in additional_envs:
            if env_entry.instance_id == instance_id:
                for env_var in env_entry.envs:
                    instance_env_vars[env_var.name] = env_var.value
                break

        processed_entry = process_entry(
            entry=entry,
            strategy=config.strategy,
            codecocoon_dir=config.codecocoon,
            transformations=transformations,
            transformations_filepath=config.transformations,
            repos_dir=config.repos,
            env_vars=instance_env_vars,
            transform_test_files=config.transform_test_files,
            override=config.override,
            rewrite_problem_statement=config.rewrite_problem_statement,
        )
        append_jsonl(config.output, processed_entry)

        logger.info(f"====== ✅ Completed entry '{instance_id}' ({i}/{len(entries)}) ======")
        logger.info("==========================================================================")

    logger.info("Processing complete!")


if __name__ == "__main__":
    main()
