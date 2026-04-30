import json
import os
from dataclasses import dataclass, field
from typing import Dict, List, NamedTuple, Optional

from common.git import (
    clone_repository,
    diff_between_commits,
    branch_exists,
    delete_branch,
    checkout_branch,
    extract_changed_files,
)
from common.codecocoon import generate_codecocoon_config, execute_rewrite_problem_statement
from transform.models import Patch, MorphResult
from transform.morph import morph, insert_metamorphic_log, parse_transformation_summary

# ─── Internal result types ────────────────────────────────────────────────────

class _CodeMorphingResult(NamedTuple):
    strategy_entry:        Dict
    metamorphic_base_patch: str
    new_morphed_test_patch: str
    new_morphed_fix_patch:  str
    artifacts_dir:         str
    memory_filepath:       str


@dataclass
class _MorphingOutcome:
    result:   Optional[_CodeMorphingResult]
    errors:   List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)

# ─── Helpers ──────────────────────────────────────────────────────────────────

def _check_morph_summary(
    morph_result: MorphResult,
    label: str,
    errors: list[str],
    warnings: list[str],
    logger,
) -> None:
    """Parse the CodeCocoon transformation summary, log it prettily, and extend errors/warnings.

    failed > 0  → error (unsuccessful generation)
    skipped > 0 → warning (not an error)
    """
    if morph_result.codecocoon_result is None:
        return
    summary = parse_transformation_summary(morph_result.codecocoon_result.stdout)
    if summary is None:
        return
    succeeded, failed, skipped = summary
    pretty = f"Transformation summary ({label}): {succeeded} succeeded, {failed} failed, {skipped} skipped"
    logger.info(pretty)
    if failed > 0:
        errors.append(pretty)
    if skipped > 0:
        warnings.append(f"[warn] {pretty}")


def _run_rewrite_problem_statement(
    codecocoon_dir: str,
    input_file: str,
    output_file: str,
    env_vars: Dict[str, str | None],
    logger,
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




def _build_github_url(org: str, repo: str) -> str:
    """Build GitHub repository URL."""
    return f"https://github.com/{org}/{repo}.git"




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
    logger,
) -> _MorphingOutcome:
    """Run all CodeCocoon code-morphing steps (Steps 1–5).

    Covers: cloning the repo, branch management, file extraction, CodeCocoon
    config generation, and the three morph passes (base, test, fix) plus diff
    generation.

    Returns a ``_MorphingOutcome`` where:
    - ``result`` is set on success, ``None`` when skipped or on hard failure
    - ``errors`` is non-empty on hard failures or when CodeCocoon reports
      failed transformations
    - ``warnings`` is non-empty when CodeCocoon reports skipped transformations
    """
    instance_id = entry['instance_id']
    errors:   List[str] = []
    warnings: List[str] = []

    strategy_entry: Dict = {
        "strategy": {
            "name":   strategy,
            "config": transformations_filepath,
        },
    }

    # Step 1: Clone repository
    repo_url = _build_github_url(entry['org'], entry['repo'])
    repo_dir = os.path.join(repos_dir, strategy, instance_id, "repo")
    base_sha = entry['base']['sha']

    if not clone_repository(repo_url, repo_dir, base_sha, logger):
        logger.error(f"Failed to clone repository for {instance_id}")
        return _MorphingOutcome(result=None, errors=[f"clone failed for {entry['org']}/{entry['repo']}"])

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
        return _MorphingOutcome(result=None)  # expected skip, not an error

    if override and (base_exists or test_exists or fix_exists):
        logger.info(f"Override enabled: Deleting existing branches for strategy '{strategy}'")
        if base_exists and not delete_branch(repo_dir, base_branch, logger):
            logger.error(f"Failed to delete base branch '{base_branch}'")
            return _MorphingOutcome(result=None, errors=[f"failed to delete branch '{base_branch}'"])
        if test_exists and not delete_branch(repo_dir, test_branch, logger):
            logger.error(f"Failed to delete test branch '{test_branch}'")
            return _MorphingOutcome(result=None, errors=[f"failed to delete branch '{test_branch}'"])
        if fix_exists and not delete_branch(repo_dir, fix_branch, logger):
            logger.error(f"Failed to delete fix branch '{fix_branch}'")
            return _MorphingOutcome(result=None, errors=[f"failed to delete branch '{fix_branch}'"])

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
        return _MorphingOutcome(result=None)  # expected skip, not an error

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
        return _MorphingOutcome(result=None, errors=[f"checkout failed for base SHA {base_sha[:8]}"])

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
        return _MorphingOutcome(result=None, errors=["CodeCocoon base morph failed"])

    _check_morph_summary(base_morph_result, "base", errors, warnings, logger)

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
        return _MorphingOutcome(result=None, errors=errors + [f"checkout failed for base SHA {base_sha[:8]} (test morph)"], warnings=warnings)

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
        return _MorphingOutcome(result=None, errors=errors + ["CodeCocoon test morph failed"], warnings=warnings)

    _check_morph_summary(test_morph_result, "test", errors, warnings, logger)

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
        return _MorphingOutcome(result=None, errors=errors + ["new_morphed_test_patch generation failed (empty diff)"], warnings=warnings)

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
        return _MorphingOutcome(result=None, errors=errors + [f"checkout failed for base SHA {base_sha[:8]} (fix morph)"], warnings=warnings)

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
        return _MorphingOutcome(result=None, errors=errors + ["CodeCocoon fix morph failed"], warnings=warnings)

    _check_morph_summary(fix_morph_result, "fix", errors, warnings, logger)

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
        return _MorphingOutcome(result=None, errors=errors + ["new_morphed_fix_patch generation failed (empty diff)"], warnings=warnings)

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

    return _MorphingOutcome(
        result=_CodeMorphingResult(
            strategy_entry=strategy_entry,
            metamorphic_base_patch=metamorphic_base_patch,
            new_morphed_test_patch=new_morphed_test_patch,
            new_morphed_fix_patch=new_morphed_fix_patch,
            artifacts_dir=artifacts_dir,
            memory_filepath=memory_filepath,
        ),
        errors=errors,
        warnings=warnings,
    )

