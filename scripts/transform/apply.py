import json
import os
from dataclasses import dataclass, field
from typing import Dict, List, NamedTuple, Optional, Tuple

from common.git import (
    build_github_url,
    clone_repository,
    diff_between_commits,
    branch_exists,
    delete_branch,
    checkout_branch,
    extract_changed_files,
    commit_all_changes,
    get_head_sha,
)
from common.codecocoon import (
    generate_codecocoon_config,
    execute_rewrite_problem_statement,
    execute_agent_fix_hunks,
)
from transform.models import Patch, MorphResult
from transform.morph import morph, insert_metamorphic_log, parse_transformation_summary
from transform.patch_filter import collect_unwanted_hunks

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

    header = (
        f"Transformation summary ({label}): "
        f"{summary.succeeded} succeeded, {summary.failed} failed, {summary.skipped} skipped"
    )
    lines = [header]
    if summary.succeeded_ids:
        lines.append(f"  succeeded: {', '.join(summary.succeeded_ids)}")
    if summary.failed_ids:
        lines.append(f"  failed:    {', '.join(summary.failed_ids)}")
    if summary.skipped_ids:
        lines.append(f"  skipped:   {', '.join(summary.skipped_ids)}")
    pretty = '\n'.join(lines)

    logger.info(pretty)
    if summary.failed > 0:
        errors.append(pretty)
    if summary.skipped > 0:
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




def _fix_import_hunks_with_agent(
    repo_dir: str,
    artifacts_dir: str,
    morph_patch: str,
    morph_commit: str,
    patch_label: str,
    codecocoon_dir: str,
    env_vars: Dict[str, str | None],
    logger,
    diff_anchor: Optional[str] = None,
    batch_size: int = 10,
    max_agent_iterations: int = 70,
    max_retries: int = 3,
    fix_hunks_override: bool = False,
) -> Tuple[str, str, Dict]:
    """Revert IntelliJ import noise from the current branch using an AI agent.

    Collects import-noise hunks from *morph_patch* (each assigned a stable
    ``hunk-N`` ID) and runs up to ``max_retries + 1`` incremental attempts.
    Each attempt feeds only the yet-unfixed hunks to ``agentFixHunks``; the
    Gradle task reports which IDs it fixed via an output JSON file, and the next
    attempt receives only the remainder.  File changes accumulate on disk across
    attempts and are committed once after the loop.

    The diff anchor used to recompute the patch after the final commit is:
      - ``diff_anchor`` when explicitly provided (cross-branch passes)
      - ``{morph_commit}~1`` otherwise (parent of the CodeCocoon commit)

    Returns ``(updated_commit_sha, updated_patch, agent_log_dict)``.
    On skip (no noise) or when no file changes are committed, the original
    commit and patch are returned unchanged.
    """
    agent_log: Dict = {
        "patch_label": patch_label,
        "skipped": False,
        "unwanted_hunk_count": 0,
        "hunks_file": None,
        "total_attempts": 0,
        "agent_return_code": None,
        "agent_stdout": None,
        "agent_stderr": None,
        "original_commit": morph_commit,
        "corrected_commit": None,
    }

    try:
        hunks_file = os.path.join(artifacts_dir, f"{patch_label}_unwanted_hunks.json")
        clean_patch_file = os.path.join(artifacts_dir, f"{patch_label}_cleaned_patch.patch")
        _clean_patch_legacy = os.path.join(artifacts_dir, f"{patch_label}_cleaned_patch.txt")
        _existing_clean = (
            clean_patch_file if os.path.exists(clean_patch_file)
            else _clean_patch_legacy if os.path.exists(_clean_patch_legacy)
            else None
        )

        if not fix_hunks_override and os.path.exists(hunks_file):
            if _existing_clean is not None:
                logger.info(
                    f"[{patch_label}] Cached clean patch found ({_existing_clean}); "
                    "returning cached result (fix_hunks_override=False)."
                )
                with open(_existing_clean) as f:
                    cached_patch = f.read()
                agent_log["skipped"] = True
                agent_log["skip_reason"] = "cached_output_exists"
                return morph_commit, cached_patch, agent_log
            logger.info(
                f"[{patch_label}] Master hunks file found but no cached clean patch — "
                "running agent."
            )

        unwanted = collect_unwanted_hunks(morph_patch, logger)
        agent_log["unwanted_hunk_count"] = len(unwanted)

        if not unwanted:
            logger.info(f"[{patch_label}] No import noise detected — skipping agentFixHunks.")
            agent_log["skipped"] = True
            return morph_commit, morph_patch, agent_log

        logger.info(
            f"[{patch_label}] Detected {len(unwanted)} import-noise hunk(s) in "
            f"{len({h['file'] for h in unwanted})} file(s). Preparing agent input..."
        )

        # Build ID→hunk lookup; track which hunks remain unfixed across attempts.
        hunk_by_id: Dict[str, Dict] = {h["id"]: h for h in unwanted}
        unfixed_ids: set = {h["id"] for h in unwanted}

        # Shared description field reused across all attempt-specific input files.
        _agent_description = (
            "These hunks are side-effects of IntelliJ's import optimizer running inside "
            "CodeCocoon. They must be reverted so the metamorphic patch contains only "
            "intentional transformations. "
            "For 'import_reorder': restore the original import order shown in "
            "'original_import_block' (the order BEFORE CodeCocoon reordered them); "
            "the file currently contains the order shown in 'current_import_block'. "
            "For 'wildcard_import_removal': add back every entry in 'removed_wildcards' "
            "(empty-string entries are blank separator lines). "
            "For 'import_cross_hunk_move': the optimizer moved an import between two "
            "distant positions, producing two separate hunks. The 'spurious_addition' "
            "hunk must have its import removed; the 'missing_import' hunk must have its "
            "import added back. The 'action' field for each hunk gives the exact instruction."
        )

        # Write master file (all hunks) for reference in audit logs.
        with open(hunks_file, 'w') as f:
            json.dump({"repo_root": repo_dir, "patch_label": patch_label,
                       "description": _agent_description, "hunks": unwanted}, f, indent=2)
        agent_log["hunks_file"] = hunks_file
        logger.info(f"[{patch_label}] Master agent input JSON ({len(unwanted)} hunk(s)) written to: {hunks_file}")

        # Incremental retry loop.
        # Each attempt feeds only the yet-unfixed hunks; file changes accumulate on disk
        # across attempts and are committed once after the loop completes.
        total_attempts = max_retries + 1

        for attempt in range(1, total_attempts + 1):
            attempt_tag = f"attempt {attempt}/{total_attempts}"

            # Write attempt-specific input with only the unfixed subset.
            attempt_input_file  = os.path.join(artifacts_dir, f"{patch_label}_unwanted_hunks_attempt_{attempt}.json")
            attempt_output_file = os.path.join(artifacts_dir, f"{patch_label}_fixed_hunks_attempt_{attempt}.json")
            unfixed_hunks = [hunk_by_id[hid] for hid in sorted(unfixed_ids)]
            with open(attempt_input_file, 'w') as f:
                json.dump({"repo_root": repo_dir, "patch_label": patch_label,
                           "description": _agent_description, "hunks": unfixed_hunks}, f, indent=2)

            logger.info(
                f"[{patch_label}] Running agentFixHunks ({attempt_tag}, "
                f"{len(unfixed_ids)} unfixed hunk(s), "
                f"batchSize={batch_size}, maxAgentIterations={max_agent_iterations})..."
            )

            agent_result = execute_agent_fix_hunks(
                codecocoon_dir=codecocoon_dir,
                input_file=attempt_input_file,
                env_vars=env_vars,
                logger=logger,
                batch_size=batch_size,
                max_agent_iterations=max_agent_iterations,
                output_file=attempt_output_file,
            )
            # Always store the last attempt's stdout/stderr for the audit log.
            agent_log["agent_return_code"] = agent_result.return_code
            agent_log["agent_stdout"]      = agent_result.stdout
            agent_log["agent_stderr"]      = agent_result.stderr
            agent_log["total_attempts"]    = attempt

            logger.info(
                f"[{patch_label}] agentFixHunks finished ({attempt_tag}, "
                f"return_code={agent_result.return_code}). "
                "stdout/stderr stored in metamorphic entry agent_fix_log."
            )

            if agent_result.return_code != 0:
                logger.warning(
                    f"[{patch_label}] agentFixHunks returned non-zero exit code "
                    f"{agent_result.return_code} ({attempt_tag}). "
                    "Committing any partial writes accumulated so far and stopping retries."
                )
                break

            # Read agent output to determine which hunk IDs were fixed this attempt.
            fixed_this_attempt: set = set()
            if os.path.exists(attempt_output_file):
                try:
                    with open(attempt_output_file) as f:
                        fixed_this_attempt = set(json.load(f).get("fixed", []))
                except Exception as e:
                    logger.warning(
                        f"[{patch_label}] Failed to read agent output file "
                        f"{attempt_output_file}: {e}. Treating as no progress this attempt."
                    )
            else:
                logger.warning(
                    f"[{patch_label}] Agent output file not found: {attempt_output_file}. "
                    "Treating as no progress this attempt."
                )

            unfixed_ids -= fixed_this_attempt

            if not unfixed_ids:
                logger.info(f"[{patch_label}] All {len(unwanted)} hunk(s) fixed after {attempt_tag}.")
                break

            if fixed_this_attempt:
                logger.info(
                    f"[{patch_label}] {len(fixed_this_attempt)} hunk(s) fixed on {attempt_tag}. "
                    f"{len(unfixed_ids)} remain: {sorted(unfixed_ids)}."
                )
            else:
                logger.warning(
                    f"[{patch_label}] No hunks fixed on {attempt_tag}. "
                    f"{total_attempts - attempt} attempt(s) left."
                )

            if attempt == total_attempts:
                logger.warning(
                    f"[{patch_label}] Retry limit reached. "
                    f"{len(unfixed_ids)} hunk(s) remain unfixed: {sorted(unfixed_ids)}."
                )

        # Post-loop: commit all file changes accumulated across every attempt.
        agent_log["unfixed_ids"] = sorted(unfixed_ids)
        if unfixed_ids:
            unfixed_files = sorted({hunk_by_id[hid]["file"] for hid in unfixed_ids})
            logger.warning(
                f"[{patch_label}] {len(unfixed_ids)}/{len(unwanted)} import-noise hunk(s) "
                f"remain unfixed after all {total_attempts} attempt(s): {sorted(unfixed_ids)}. "
                f"Affected file(s): {unfixed_files}"
            )

        sha_before_commit = get_head_sha(repo_dir, logger) or morph_commit
        commit_all_changes(
            repo_dir,
            f"[filter] Agent fix import noise ({patch_label})",
            logger,
        )
        sha_after_commit = get_head_sha(repo_dir, logger)

        if not sha_after_commit or sha_after_commit == sha_before_commit:
            logger.warning(
                f"[{patch_label}] No file changes committed after all attempts. "
                "Original patches retained."
            )
            with open(clean_patch_file, 'w') as f:
                f.write(morph_patch)
            return morph_commit, morph_patch, agent_log

        agent_log["corrected_commit"] = sha_after_commit
        n_fixed = len(unwanted) - len(unfixed_ids)
        logger.info(
            f"[{patch_label}] Agent fixes committed: {sha_after_commit} "
            f"(was: {morph_commit}, {n_fixed}/{len(unwanted)} hunk(s) fixed)."
        )

        # Recompute the morph patch from the anchor to the corrected commit.
        # Default anchor: '{morph_commit}~1' (parent of the CodeCocoon commit).
        # Cross-branch callers supply an explicit anchor instead.
        actual_anchor = diff_anchor if diff_anchor is not None else f"{morph_commit}~1"
        new_patch = diff_between_commits(repo_dir, actual_anchor, sha_after_commit, logger)
        if not new_patch:
            logger.warning(
                f"[{patch_label}] Recomputed patch is empty after agent fix — "
                "this is unexpected. Retaining original patch."
            )
            with open(clean_patch_file, 'w') as f:
                f.write(morph_patch)
            return sha_after_commit, morph_patch, agent_log

        logger.info(
            f"[{patch_label}] Patch recomputed: {len(new_patch)} chars "
            f"(was {len(morph_patch)} chars before agent fix)."
        )
        with open(clean_patch_file, 'w') as f:
            f.write(new_patch)
        return sha_after_commit, new_patch, agent_log

    except Exception as e:
        logger.warning(
            f"[{patch_label}] _fix_import_hunks_with_agent raised an unexpected exception: "
            f"{type(e).__name__}: {e}. Returning original patches unchanged.",
            exc_info=True,
        )
        agent_log["error"] = f"{type(e).__name__}: {e}"
        return morph_commit, morph_patch, agent_log


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
    fix_import_hunks_with_agent: bool,
    logger,
    fix_hunks_batch_size: int = 10,
    fix_hunks_max_agent_iterations: int = 70,
    fix_hunks_max_retries: int = 3,
    fix_hunks_override: bool = False,
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
    repo_url = build_github_url(entry['org'], entry['repo'])
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

    # Step 1b: Agent fix for base patch (optional)
    # DISABLED: per-branch fixes are skipped — noise in metamorphic_base_patch cancels out
    # in the cross-branch diffs when CodeCocoon applies the same reordering on all branches.
    # Cross-branch noise (when CodeCocoon reorders on base but is a no-op on test/fix) is
    # caught by steps 3b and 5b instead.  Re-enable if metamorphic_base_patch noise matters.
    # if fix_import_hunks_with_agent:
    #     logger.info("=================================================================================")
    #     logger.info("===== STEP 1b: agentFixHunks — revert import noise in metamorphic_base_patch =====")
    #     logger.info("=================================================================================")
    #     metamorphic_base_commit, metamorphic_base_patch, agent_fix_base_log = _fix_import_hunks_with_agent(
    #         repo_dir=repo_dir,
    #         artifacts_dir=artifacts_dir,
    #         morph_patch=metamorphic_base_patch,
    #         morph_commit=metamorphic_base_commit,
    #         patch_label="base",
    #         codecocoon_dir=codecocoon_dir,
    #         env_vars=env_vars,
    #         logger=logger,
    #         batch_size=fix_hunks_batch_size,
    #         max_agent_iterations=fix_hunks_max_agent_iterations,
    #     )
    #     strategy_entry["metamorphic_patches"]["base"]["patch"]["value"] = metamorphic_base_patch
    #     strategy_entry["metamorphic_patches"]["base"]["commit"] = metamorphic_base_commit
    #     strategy_entry["metamorphic_patches"]["base"]["agent_fix_log"] = agent_fix_base_log
    #     logger.info(
    #         f"Base agent fix complete. "
    #         f"Corrected commit: {metamorphic_base_commit} "
    #         f"({'changed' if not agent_fix_base_log.get('skipped') and agent_fix_base_log.get('corrected_commit') else 'unchanged'})"
    #     )

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

    # Step 2b: Agent fix for test patch (optional)
    # DISABLED: see step 1b comment — per-branch fixes skipped; 3b catches cross-branch noise.
    # if fix_import_hunks_with_agent:
    #     logger.info("==================================================================================")
    #     logger.info("===== STEP 2b: agentFixHunks — revert import noise in metamorphic_test_patch =====")
    #     logger.info("==================================================================================")
    #     metamorphic_test_commit, _metamorphic_test_patch, agent_fix_test_log = _fix_import_hunks_with_agent(
    #         repo_dir=repo_dir,
    #         artifacts_dir=artifacts_dir,
    #         morph_patch=_metamorphic_test_patch,
    #         morph_commit=metamorphic_test_commit,
    #         patch_label="test",
    #         codecocoon_dir=codecocoon_dir,
    #         env_vars=env_vars,
    #         logger=logger,
    #         batch_size=fix_hunks_batch_size,
    #         max_agent_iterations=fix_hunks_max_agent_iterations,
    #     )
    #     strategy_entry["metamorphic_patches"]["test"]["patch"]["value"] = _metamorphic_test_patch
    #     strategy_entry["metamorphic_patches"]["test"]["commit"] = metamorphic_test_commit
    #     strategy_entry["metamorphic_patches"]["test"]["agent_fix_log"] = agent_fix_test_log
    #     logger.info(
    #         f"Test agent fix complete. "
    #         f"Corrected commit: {metamorphic_test_commit} "
    #         f"({'changed' if not agent_fix_test_log.get('skipped') and agent_fix_test_log.get('corrected_commit') else 'unchanged'})"
    #     )

    # Step 4c: Generate new_morphed_test_patch
    # NOTE: metamorphic_base_commit and metamorphic_test_commit are NOT pre-corrected
    #       (per-branch fixes 1b/2b are disabled). Cross-branch noise is caught by step 3b.
    logger.info("=====================================================")
    logger.info("===== STEP 3: Generating new_morphed_test_patch =====")
    logger.info("=====================================================")
    logger.info(
        f"Computing diff: metamorphic_base_commit ({metamorphic_base_commit}) "
        f"→ metamorphic_test_commit ({metamorphic_test_commit})"
    )

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

    # Step 3b: Agent fix for cross-branch test noise (optional)
    # Catches reorderings that appear in the cross-branch diff but NOT in either
    # individual metamorphic patch (e.g. when CodeCocoon reordered on base but
    # the test_patch already had the "wrong" order and CodeCocoon was a no-op there).
    if fix_import_hunks_with_agent:
        logger.info("==============================================================================================")
        logger.info("===== STEP 3b: agentFixHunks — revert cross-branch import noise in new_morphed_test_patch =====")
        logger.info("==============================================================================================")
        metamorphic_test_commit, new_morphed_test_patch, cross_test_log = _fix_import_hunks_with_agent(
            repo_dir=repo_dir,
            artifacts_dir=artifacts_dir,
            morph_patch=new_morphed_test_patch,
            morph_commit=metamorphic_test_commit,
            patch_label="test_cross",
            codecocoon_dir=codecocoon_dir,
            env_vars=env_vars,
            logger=logger,
            diff_anchor=metamorphic_base_commit,
            batch_size=fix_hunks_batch_size,
            max_agent_iterations=fix_hunks_max_agent_iterations,
            max_retries=fix_hunks_max_retries,
            fix_hunks_override=fix_hunks_override,
        )
        strategy_entry["metamorphic_patches"]["test"]["commit"] = metamorphic_test_commit
        strategy_entry["metamorphic_patches"]["test"]["new_morphed_test_patch"]["value"] = new_morphed_test_patch
        strategy_entry["metamorphic_patches"]["test"]["cross_branch_agent_fix_log"] = cross_test_log
        logger.info(
            f"Test cross-branch fix complete. "
            f"Corrected commit: {metamorphic_test_commit} "
            f"({'changed' if not cross_test_log.get('skipped') and cross_test_log.get('corrected_commit') else 'unchanged'})"
        )

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

    # Step 4b: Agent fix for fix patch (optional)
    # DISABLED: see step 1b comment — per-branch fixes skipped; 5b catches cross-branch noise.
    # if fix_import_hunks_with_agent:
    #     logger.info("=================================================================================")
    #     logger.info("===== STEP 4b: agentFixHunks — revert import noise in metamorphic_fix_patch =====")
    #     logger.info("=================================================================================")
    #     metamorphic_fix_commit, _metamorphic_fix_patch, agent_fix_fix_log = _fix_import_hunks_with_agent(
    #         repo_dir=repo_dir,
    #         artifacts_dir=artifacts_dir,
    #         morph_patch=_metamorphic_fix_patch,
    #         morph_commit=metamorphic_fix_commit,
    #         patch_label="fix",
    #         codecocoon_dir=codecocoon_dir,
    #         env_vars=env_vars,
    #         logger=logger,
    #         batch_size=fix_hunks_batch_size,
    #         max_agent_iterations=fix_hunks_max_agent_iterations,
    #     )
    #     strategy_entry["metamorphic_patches"]["fix"]["patch"]["value"] = _metamorphic_fix_patch
    #     strategy_entry["metamorphic_patches"]["fix"]["commit"] = metamorphic_fix_commit
    #     strategy_entry["metamorphic_patches"]["fix"]["agent_fix_log"] = agent_fix_fix_log
    #     logger.info(
    #         f"Fix agent fix complete. "
    #         f"Corrected commit: {metamorphic_fix_commit} "
    #         f"({'changed' if not agent_fix_fix_log.get('skipped') and agent_fix_fix_log.get('corrected_commit') else 'unchanged'})"
    #     )

    # Step 4e: Generate new_morphed_fix_patch
    # NOTE: metamorphic_base_commit and metamorphic_fix_commit are NOT pre-corrected
    #       (per-branch fixes 1b/2b/4b are disabled). Cross-branch noise is caught by step 5b.
    logger.info("====================================================")
    logger.info("===== STEP 5: Generating new_morphed_fix_patch =====")
    logger.info("====================================================")
    logger.info(
        f"Computing diff: metamorphic_base_commit ({metamorphic_base_commit}) "
        f"→ metamorphic_fix_commit ({metamorphic_fix_commit})"
    )

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

    # Step 5b: Agent fix for cross-branch fix noise (optional)
    # Catches reorderings that appear in the cross-branch diff but NOT in either
    # individual metamorphic patch (e.g. when CodeCocoon reordered on base but
    # the fix_patch already had the "wrong" order and CodeCocoon was a no-op there).
    if fix_import_hunks_with_agent:
        logger.info("=============================================================================================")
        logger.info("===== STEP 5b: agentFixHunks — revert cross-branch import noise in new_morphed_fix_patch =====")
        logger.info("=============================================================================================")
        metamorphic_fix_commit, new_morphed_fix_patch, cross_fix_log = _fix_import_hunks_with_agent(
            repo_dir=repo_dir,
            artifacts_dir=artifacts_dir,
            morph_patch=new_morphed_fix_patch,
            morph_commit=metamorphic_fix_commit,
            patch_label="fix_cross",
            codecocoon_dir=codecocoon_dir,
            env_vars=env_vars,
            logger=logger,
            diff_anchor=metamorphic_base_commit,
            batch_size=fix_hunks_batch_size,
            max_agent_iterations=fix_hunks_max_agent_iterations,
            max_retries=fix_hunks_max_retries,
            fix_hunks_override=fix_hunks_override,
        )
        strategy_entry["metamorphic_patches"]["fix"]["commit"] = metamorphic_fix_commit
        strategy_entry["metamorphic_patches"]["fix"]["new_morphed_fix_patch"]["value"] = new_morphed_fix_patch
        strategy_entry["metamorphic_patches"]["fix"]["cross_branch_agent_fix_log"] = cross_fix_log
        logger.info(
            f"Fix cross-branch fix complete. "
            f"Corrected commit: {metamorphic_fix_commit} "
            f"({'changed' if not cross_fix_log.get('skipped') and cross_fix_log.get('corrected_commit') else 'unchanged'})"
        )

    logger.info(
        f"Code morphing complete for {instance_id} "
        f"(base: {base_branch}, test: {test_branch}, fix: {fix_branch})"
    )

    patches_dir = os.path.join(artifacts_dir, "patches")
    os.makedirs(patches_dir, exist_ok=True)
    for _fname, _content in [
        ("metamorphic_base.patch", metamorphic_base_patch),
        ("new_morphed_test.patch", new_morphed_test_patch),
        ("new_morphed_fix.patch",  new_morphed_fix_patch),
    ]:
        with open(os.path.join(patches_dir, _fname), 'w') as _f:
            _f.write(_content)

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

