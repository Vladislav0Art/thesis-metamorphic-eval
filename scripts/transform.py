import argparse
import json
import os
import sys
import logging
from pathlib import Path
from typing import Dict, List
from dotenv import dotenv_values
from default.defaults import DEFAULT_CODE_COCCOON_TRANSFORMATIONS
from common.logger import configure_logging
from common.fs import read_jsonl, write_jsonl, make_absolute_path
from common.git import (
    clone_repository,
    diff_between_commits,
    branch_exists,
    delete_branch,
    checkout_branch,
    extract_changed_files,
)
from common.codecocoon import generate_codecocoon_config
from transform.models import (
    Patch,
    MorphResult,
    EnvVar,
    EnvEntry,
)
from transform.morph import (
    morph,
    insert_metamorphic_log,
)


description="""
This script accepts jsonl file with benchmarks and applies transformations via CodeCocoon-Plugin.
The result patches after transformation are added into the entries of the given jsonl file and
save into the output file.

Arguments:
  -i, --input: Path to the input JSONL file containing benchmarks.
  -o, --output: Path to the output jsonl file where transformed benchmarks will be saved.
  -s, --strategy: The transformation strategy name
                  (the resulting transformations will be saved as entry['strategy']['metamorphic_base_patch'] and
                   entry['strategy']['metamorphic_fix_patch']).
  -c, --codecoccoon: Filepath to the Code Codecoccoon repository (its headless mode will be executed).
  -e, --env_filepath: Filepath to a file with key-value pairs defining environment variables to be set when executing CodeCocoon (e.g., to provide credentials for private repositories) (default: None).
  -r, --repos: Filepath which the repositories from the input should be cloned into.
  --transform_test_files: Whether to also transform test files changed in the test patch (`test_patch` field in every benchmark) (default: False).
  --override: Whether to override existing transformation results if branches already exist (default: False).

Usage:
python transform.py -i path/to/input.jsonl -o path/to/output.jsonl -s transformation_strategy_name -c path/to/codecoccoon
"""

# Configure logging
configure_logging(log_filename="transform.log", level=logging.INFO)

logger = logging.getLogger(__name__)



def build_github_url(org: str, repo: str) -> str:
    """Build GitHub repository URL."""
    return f"https://github.com/{org}/{repo}.git"



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
) -> Dict:
    """Process a single entry through the transformation pipeline."""
    instance_id = entry['instance_id']
    logger.info(f"Processing entry: {instance_id}")

    logger.info(f"ENV variables: [{ ', '.join(env_vars.keys()) }]")

    # Initialize metamorphic array if not present
    if "metamorphic" not in entry:
        entry["metamorphic"] = []

    # Strategy entry dict — built up locally and appended to entry["metamorphic"] once
    # we know base morphing succeeded (to avoid partial empty entries on early failures).
    strategy_entry = {
        "strategy": {
            "name": strategy,
            "config": transformations_filepath,
        },
    }

    try:
        # Step 1: Clone repository
        repo_url = build_github_url(entry['org'], entry['repo'])

        # repo_dir=repos_dir/strategy/instance_id/repo
        repo_dir = os.path.join(repos_dir, strategy, instance_id, "repo")
        base_sha = entry['base']['sha']

        if not clone_repository(repo_url, repo_dir, base_sha, logger):
            logger.error(f"Failed to clone repository for {instance_id}")
            return entry

        # Step 1.5: Check if branches exist and handle override
        base_branch = f"{strategy}-base-transformation"
        test_branch = f"{strategy}-test-transformation"
        fix_branch  = f"{strategy}-fix-transformation"

        base_exists = branch_exists(repo_dir, base_branch, logger)
        test_exists = branch_exists(repo_dir, test_branch, logger)
        fix_exists = branch_exists(repo_dir, fix_branch, logger)

        if (base_exists or test_exists or fix_exists) and not override:
            logger.info(
                f"Branches for strategy '{strategy}' already exist. "
                f"Skipping transformation (use --override to regenerate)."
            )
            return entry

        if override and (base_exists or test_exists or fix_exists):
            logger.info(f"Override enabled: Deleting existing branches for strategy '{strategy}'")
            if base_exists and not delete_branch(repo_dir, base_branch, logger):
                logger.error(f"Failed to delete base branch '{base_branch}'")
                return entry
            if test_exists and not delete_branch(repo_dir, test_branch, logger):
                logger.error(f"Failed to delete test branch '{test_branch}'")
                return entry
            if fix_exists and not delete_branch(repo_dir, fix_branch, logger):
                logger.error(f"Failed to delete test branch '{fix_branch}'")
                return entry

        # Step 2: Extract changed files
        # NOTE: based on `transform_test_files` flag, apply transformations to files from either:
        #         1) fix patch only (default behavior)
        #         2) both fix and test patches (if `transform_test_files` is True)
        fix_files  = extract_changed_files(patch=entry.get('fix_patch', '') , logger=logger)
        test_files = extract_changed_files(patch=entry.get('test_patch', ''), logger=logger)

        if transform_test_files:
            # transform files from the test patch as well
            files_to_transform = list(set(fix_files + test_files))
            logger.info(f"Transforming files FROM BOTH FIX AND TEST PATCHES for {instance_id}")
        else:
            # transform only files modified by the fix patch (default behavior)
            files_to_transform = list(set(fix_files))
            logger.info(f"Transforming files modified ONLY BY FIX PATCH for {instance_id}")


        # Filter to .java files only — CodeCocoon only handles Java; non-Java files would pollute the config
        java_files = [f for f in files_to_transform if f.endswith('.java')]
        non_java_files = [f for f in files_to_transform if not f.endswith('.java')]

        if non_java_files:
            non_java_str = ''.join([f"\n     - {f}" for f in non_java_files])
            logger.info(f"Filtered out {len(non_java_files)} non-Java file(s) (not passed to CodeCocoon):{non_java_str}")

        files_to_transform = java_files

        if not files_to_transform:
            logger.warning(f"No files found in patches for {instance_id}")
            return entry

        files_to_transform_joined = ''.join([f"\n     - {file}" for file in files_to_transform])
        logger.info(f"Extracted {len(files_to_transform)} unique changed files:{files_to_transform_joined}")


        # Step 3: Generate CodeCocoon config
        # config_path=repos_dir/strategy/instance_id/codecocoon.yml
        config_path = os.path.join(repos_dir, strategy, instance_id, "codecocoon.yml")
        os.makedirs(os.path.dirname(config_path), exist_ok=True)
        generate_codecocoon_config(
            project_root=repo_dir,
            files=files_to_transform,
            transformations=transformations,
            output_path=config_path,
            logger=logger,
        )

        # Step 4: Apply metamorphic modifications to base commit
        logger.info("=====================================================================")
        logger.info("===== STEP 1: Applying metamorphic modifications to base commit =====")
        logger.info("=====================================================================")

        # Ensure we're on base commit before starting
        if not checkout_branch(repo_dir, base_sha, logger, create=False):
            logger.error(f"Failed to checkout base SHA {base_sha}")
            return entry

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
            return entry

        # assing variables
        metamorphic_base_commit: str = base_morph_result.last_commit_sha
        metamorphic_base_patch: str = base_morph_result.metamorphic_patch

        # Base morph succeeded — commit strategy_entry to the metamorphic array.
        # From this point on any early return still preserves partially-stored fields.
        entry["metamorphic"].append(strategy_entry)

        # Store repo reference (path + branch names) for external tooling / debugging
        strategy_entry["repo"] = {
            "instance_id": instance_id,
            "path": repo_dir,
            "branches": {
                "base": base_branch,
                "test": test_branch,
                "fix": fix_branch,
            },
        }

        # Structured container for all three morph results; populated incrementally below
        strategy_entry["metamorphic_patches"] = {}

        # Store base transformation results
        strategy_entry["metamorphic_patches"]["base"] = {
            "patch": {
                "description": "CodeCocoon transformations applied on the original base commit",
                "value": metamorphic_base_patch,
            },
            "commit": metamorphic_base_commit,
            "branch": base_branch,
        }
        # saving CodeCocoon logs for base transformation
        insert_metamorphic_log(
            strategy_entry=strategy_entry,
            label="base_metamorphic_transformation_log",
            applied_to="base",
            result=base_morph_result.codecocoon_result,
            logger=logger,
        )

        logger.info(f"Base metamorphic transformation complete. Commit: {metamorphic_base_commit}")

        # Step 5: Apply test_patch and then metamorphic modifications
        logger.info("===================================================================")
        logger.info("===== STEP 2: Applying test_patch + metamorphic modifications =====")
        logger.info("===================================================================")

        # Checkout base commit again before applying test patch
        if not checkout_branch(repo_dir, base_sha, logger, create=False):
            logger.error(f"Failed to checkout base SHA {base_sha}")
            return entry

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
            return entry

        metamorphic_test_commit = test_morph_result.last_commit_sha
        _metamorphic_test_patch = test_morph_result.metamorphic_patch

        logger.info(f"Test metamorphic transformation complete. Commit: {metamorphic_test_commit}")

        # Store test transformation results
        strategy_entry["metamorphic_patches"]["test"] = {
            "patch": {
                "description": "CodeCocoon transformations applied on the base commit with original test_patch pre-applied (base + test_patch)",
                "value": _metamorphic_test_patch,
            },
            "commit": metamorphic_test_commit,
            "branch": test_branch,
        }
        # save CodeCocoon logs for test transformation
        insert_metamorphic_log(
            strategy_entry=strategy_entry,
            label="test_metamorphic_transformation_log",
            applied_to="test",
            result=test_morph_result.codecocoon_result,
            logger=logger,
        )

        # Step 3: Generate new_morphed_test_patch as diff between two metamorphic commits
        logger.info("=====================================================")
        logger.info("===== STEP 3: Generating new_morphed_test_patch =====")
        logger.info("=====================================================")

        # NOTE: this patch should be applied instead of test_patch when evaluating
        #       on the metamorphed version of the benchmark.
        # This final `new_morphed_test_patch` represents the difference between
        # the base metamorphic state and the test + metamorphic state.
        new_morphed_test_patch = diff_between_commits(
            repo_dir=repo_dir,
            base=metamorphic_base_commit,
            another=metamorphic_test_commit,
            logger=logger,
        )

        if not new_morphed_test_patch:
            logger.error("Failed to generate new_morphed_test_patch")
            return entry

        # complete the test section with original and morphed patch
        strategy_entry["metamorphic_patches"]["test"]["original_patch"] = test_patch
        strategy_entry["metamorphic_patches"]["test"]["new_morphed_test_patch"] = {
            "description": (
                "Difference between 1) metamorphically transformed base commit and "
                "2) metamorphically transformed base + original test_patch "
                "(replaces original `test_patch` field)"
            ),
            "value": new_morphed_test_patch,
        }

        # Step 4: Apply fix_patch and then metamorphic modifications
        logger.info("==================================================================")
        logger.info("===== STEP 4: Applying fix_patch + metamorphic modifications =====")
        logger.info("==================================================================")

        # Checkout base commit again before applying fix patch
        if not checkout_branch(repo_dir, base_sha, logger, create=False):
            logger.error(f"Failed to checkout base SHA {base_sha}")
            return entry

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
            return entry

        metamorphic_fix_commit = fix_morph_result.last_commit_sha
        _metamorphic_fix_patch = fix_morph_result.metamorphic_patch

        logger.info(f"Fix metamorphic transformation complete. Commit: {metamorphic_fix_commit}")

        # Store fix transformation results
        strategy_entry["metamorphic_patches"]["fix"] = {
            "patch": {
                "description": "CodeCocoon transformations applied on the base commit with original fix_patch pre-applied (base + fix_patch)",
                "value": _metamorphic_fix_patch,
            },
            "commit": metamorphic_fix_commit,
            "branch": fix_branch,
        }
        # save CodeCocoon logs for fix transformation
        insert_metamorphic_log(
            strategy_entry=strategy_entry,
            label="fix_metamorphic_transformation_log",
            applied_to="fix",
            result=fix_morph_result.codecocoon_result,
            logger=logger,
        )

        # Step 5: Generate new_morphed_fix_patch as diff between two metamorphic commits
        logger.info("====================================================")
        logger.info("===== STEP 5: Generating new_morphed_fix_patch =====")
        logger.info("====================================================")

        # This final `new_morphed_fix_patch` represents the difference between
        # the base metamorphic state and the fix + metamorphic state.
        new_morphed_fix_patch = diff_between_commits(
            repo_dir=repo_dir,
            base=metamorphic_base_commit,
            another=metamorphic_fix_commit,
            logger=logger,
        )

        if not new_morphed_fix_patch:
            logger.error("Failed to generate new_morphed_fix_patch")
            return entry

        # complete the fix section with original and morphed patch
        strategy_entry["metamorphic_patches"]["fix"]["original_patch"] = fix_patch
        strategy_entry["metamorphic_patches"]["fix"]["new_morphed_fix_patch"] = {
            "description": (
                "Difference between 1) metamorphically transformed base commit and "
                "2) metamorphically transformed base + original fix_patch "
                "(replaces original `fix_patch` field)"
            ),
            "value": new_morphed_fix_patch,
        }

        logger.info("====================================================================================================================")
        logger.info("===== STEP 6: Replacing test_patch/fix_patch with morphed versions and save metamorphic_base_patch into 'base' =====")
        logger.info("====================================================================================================================")

        # base: sha -> sha + metamorphic_base_patch (MSWE-agent and multi_swe_bench should apply the patch manually)
        # test: test_patch -> new_morphed_test_patch
        # fix:  fix_patch  -> new_morphed_fix_patch
        entry['base']['metamorphic_base_patch'] = metamorphic_base_patch
        entry['test_patch'] = new_morphed_test_patch
        entry['fix_patch'] = new_morphed_fix_patch

        logger.info(f"Successfully completed all transformations for {instance_id}")
        logger.info(f"  Base branch: {base_branch}")
        logger.info(f"  Test branch: {test_branch}")
        logger.info(f"  Fix branch:  {fix_branch}")
        logger.info(f"  Generated new_morphed_test_patch (replaces test_patch)")
        logger.info(f"  Generated new_morphed_fix_patch  (replaces fix_patch)")

    except Exception as e:
        logger.error(f"Failed to process {instance_id}: {e}", exc_info=True)

    return entry



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




def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('-i', '--input', type=str, required=True,
                        help="Path to the input jsonl file containing benchmarks")
    parser.add_argument('-o', '--output', type=str, required=True,
                        help="Path to the output jsonl file where transformed benchmarks will be saved.")
    parser.add_argument('-s', '--strategy', type=str, help="""
        The transformation strategy name (the resulting transformations will be saved as
        entry['strategy']['metamorphic_base_patch'] and entry['strategy']['metamorphic_fix_patch']).
    """)
    parser.add_argument('-c', "--codecoccoon", type=str, help="Filepath to the Code Codecoccoon repository (its headless mode will be executed).")

    parser.add_argument('-e', "--env_filepath", type=str, default=None,
                        help="Filepath to a file with key-value pairs defining environment variables to be set when executing CodeCocoon (e.g., to provide credentials for private repositories) (default: None)")
    # per-benchmark ENV variables (e.g., specific JAVA_HOME)
    parser.add_argument('-d', "--additional_envs_filepath", type=str, default=None,
                        help="Filepath to JSON file with additional benchmark-specific ENVs (per instance id)")

    parser.add_argument('-r', '--repos', type=str, help="Filepath which the repositories from the input should be cloned into")
    parser.add_argument('-t', '--transformations', type=str, default=None, help="Filepath to a JSON file with transformations definitions. The file should contain a list of objects with `id` and `config` entries where the config is transformation-specific. Defaults to a config defined inn `default/defaults.py` when missing.")
    # bool arguments
    parser.add_argument('--transform_test_files', action='store_true', default=False,
                        help="Whether to also transform test files changed in the test patch (`test_patch` field in every benchmark) (default: False)")
    parser.add_argument('--override', action='store_true', default=False,
                        help="Override existing transformation results if branches already exist (default: False)")


    args = parser.parse_args()


    # Convert paths to absolute if they are relative
    args.repos = make_absolute_path(args.repos)
    args.input = make_absolute_path(args.input)
    args.output = make_absolute_path(args.output)
    args.codecoccoon = make_absolute_path(args.codecoccoon)
    if args.env_filepath:
        args.env_filepath = make_absolute_path(args.env_filepath)
    if args.additional_envs_filepath:
        args.additional_envs_filepath = make_absolute_path(args.additional_envs_filepath)
    if args.transformations:
        args.transformations = make_absolute_path(args.transformations)

    # Validate arguments
    if not os.path.exists(args.input):
        logger.error(f"Input file does not exist: {args.input}")
        return

    if not os.path.exists(args.codecoccoon):
        logger.error(f"CodeCocoon directory does not exist: {args.codecoccoon}")
        return

    # Create repos directory if it doesn't exist
    os.makedirs(args.repos, exist_ok=True)

    logger.info(f"""Given arguments (converted to absolute paths if needed):
      --input: {args.input}
      --output: {args.output}
      --strategy: {args.strategy}
      --codecoccoon: {args.codecoccoon}
      --transformations: {args.transformations}
      --repos: {args.repos}
      --env_filepath: {args.env_filepath}
      --additional_envs_filepath: {args.additional_envs_filepath}
      --transform_test_files: {args.transform_test_files}
      --override: {args.override}
    """)

    # CodeCocoon existence check (validate that the provided path is a directory and contains expected files)
    if not os.path.exists(args.codecoccoon):
        raise ValueError(f"CodeCocoon directory does not exist: {args.codecoccoon}. Directory path to the Code Codecoccoon Plugin repository expected (its headless mode will be executed) and should be provided via `--codecoccoon` argument.")
    if not os.path.isdir(args.codecoccoon):
        raise ValueError(f"Provided CodeCocoon path is not a directory: {args.codecoccoon}. Directory path to the Code Codecoccoon Plugin repository expected (its headless mode will be executed) and should be provided via `--codecoccoon` argument.")

    if args.strategy is None or len(args.strategy) <= 0:
        raise ValueError(f"Received malformed transformation strategy: '{args.strategy}'. Transformation strategy name must be provided via `--strategy` argument and should be a non-empty string (e.g., 'default')")

    # loading additional environment variables from the provided file (if any)
    # and setting them in the environment for when we execute CodeCocoon later
    if args.env_filepath is not None:
        if not os.path.exists(args.env_filepath):
            logger.error(f"Provided `env_filepath` does not exist: {args.env_filepath}")
            return
        if not os.path.isfile(args.env_filepath):
            logger.error(f"Provided `env_filepath` is not a file: {args.env_filepath}")
            return
        env_vars = dotenv_values(args.env_filepath)

        env_keys_str = ', '.join(list(env_vars.keys()))
        logger.info(f"Successfully loaded {len(env_vars)} environment variables from {args.env_filepath}: {env_keys_str}")
    else:
        logger.info("`env_filepath` not provided: No additional ENV variables loaded")
        env_vars = {}

    # load per instance id ENVs
    additional_envs: List[EnvEntry] = []

    if args.additional_envs_filepath is not None:
        if not os.path.exists(args.additional_envs_filepath):
            logger.error(f"Provided `additional_envs_filepath` does not exist: {args.additional_envs_filepath}")
            return
        if not os.path.isfile(args.additional_envs_filepath):
            logger.error(f"Provided `additional_envs_filepath` is not a file: {args.additional_envs_filepath}")
            return
        with open(args.additional_envs_filepath) as file:
            import json
            # array of entries defined below
            envs_data = json.load(file)
            logger.info(f"Successfully loaded additional ENVs for instances from {args.additional_envs_filepath}")

            # expected instance format:
            # { "instance_id", "envs": [{ "name": "str", "value": "str" }] }
            for entry in envs_data:
                if ('instance_id' not in entry) or ('envs' not in entry) or (not isinstance(entry['envs'], list)):
                    logger.error(f"Malformed entry in additional ENVs file (missing 'instance_id' or 'envs' list): {entry}")
                    sys.exit(1)

                instance_id = entry['instance_id']
                envs: List[EnvVar] = []
                for env in entry['envs']:
                    if ('name' not in env) or ('value' not in env):
                        logger.error(f"Malformed env entry for instance '{instance_id}' in additional ENVs file (missing 'name' or 'value'): {env}")
                        sys.exit(1)
                    # valid ENV variable
                    envs.append(EnvVar(name=env['name'], value=env['value']))

                # append to the list of additional envs
                additional_envs.append(
                    EnvEntry(
                        instance_id=instance_id,
                        envs=envs,
                    )
                )

    transformations = load_codecoccoon_transformations(from_filepath=args.transformations)
    if transformations is None:
        logger.error("Failed to load transformations, terminating execution.")
        return

    logger.info(f"Creating repos directory if doesn't exist already at: {args.repos}")
    Path(args.repos).mkdir(parents=True, exist_ok=True)

    # Read input entries
    entries = read_jsonl(args.input)

    # Process each entry
    processed_entries = []
    for i, entry in enumerate(entries, 1):
        instance_id = entry["instance_id"]
        logger.info("==========================================================================")
        logger.info(f"====== ⌛ Processing entry '{instance_id}' ({i}/{len(entries)}) ======")

        # Merge common env_vars with per-instance additional envs
        instance_env_vars = dict(env_vars)
        for env_entry in additional_envs:
            if env_entry.instance_id == instance_id:
                for env_var in env_entry.envs:
                    instance_env_vars[env_var.name] = env_var.value
                break


        processed_entry = process_entry(
            entry=entry,
            strategy=args.strategy,
            codecocoon_dir=args.codecoccoon,
            transformations=transformations,
            transformations_filepath=args.transformations,
            repos_dir=args.repos,
            env_vars=instance_env_vars,
            transform_test_files=args.transform_test_files,
            override=args.override,
        )
        processed_entries.append(processed_entry)

        logger.info(f"====== ✅ Completed entry '{instance_id}' ({i}/{len(entries)}) ======")
        logger.info("==========================================================================")

    # Write output
    write_jsonl(args.output, processed_entries)
    logger.info("Processing complete!")


if __name__ == "__main__":
    main()
