import argparse
import json
import os
import sys
import logging
import yaml
from pathlib import Path
from typing import Dict, List
from dotenv import dotenv_values
from default.defaults import DEFAULT_CODE_COCCOON_TRANSFORMATIONS
from common.logger import configure_logging
from common.fs import read_jsonl, append_jsonl
from common.codecocoon import execute_transform_metamorphic_texts
from transform.models import EnvVar, EnvEntry, TransformConfig, ProcessEntryResult, validate_config
from transform.apply import _run_rewrite_problem_statement, _apply_code_morphing


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
) -> ProcessEntryResult:
    """Process a single entry through the transformation pipeline."""
    instance_id = entry['instance_id']
    errors:   List[str] = []
    warnings: List[str] = []
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
                logger=logger,
            )
            if rps_output is not None:
                for key in ("title", "body", "resolved_issues"):
                    if key in rps_output:
                        entry[key] = rps_output[key]
                logger.info(f"rewriteProblemStatement succeeded: title={entry.get('title', '')[:80]!r}")
            else:
                msg = f"rewriteProblemStatement failed (return_code={rps_raw.return_code})"
                logger.error(f"{msg}; keeping original problem statement")
                errors.append(msg)
        else:
            logger.info("rewrite_problem_statement=false — returning entry unchanged.")
        return ProcessEntryResult(entry=entry, errors=errors, warnings=warnings)

    try:
        morph_outcome = _apply_code_morphing(
            entry=entry,
            strategy=strategy,
            transformations=transformations,
            transformations_filepath=transformations_filepath,
            codecocoon_dir=codecocoon_dir,
            repos_dir=repos_dir,
            env_vars=env_vars,
            transform_test_files=transform_test_files,
            override=override,
            logger=logger,
        )
        errors.extend(morph_outcome.errors)
        warnings.extend(morph_outcome.warnings)

        if morph_outcome.result is None:
            return ProcessEntryResult(entry=entry, errors=errors, warnings=warnings)

        # Commit morphing results to entry.
        morph_result = morph_outcome.result
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
            return ProcessEntryResult(entry=entry, errors=errors, warnings=warnings)

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
                msg = f"transformMetamorphicTexts failed (return_code={tmt_result.return_code})"
                logger.error(f"{msg}; keeping original problem statement")
                errors.append(msg)

            strategy_entry["text_transformations"]["transform_metamorphic_texts"] = tmt_log

        # 7b: rewriteProblemStatement — runs on current_ps_path (may already be renamed)
        if rewrite_problem_statement:
            logger.info(f"Running rewriteProblemStatement on {current_ps_path}")
            rps_raw, rps_output = _run_rewrite_problem_statement(
                codecocoon_dir=codecocoon_dir,
                input_file=current_ps_path,
                output_file=ps_rewritten,
                env_vars=env_vars,
                logger=logger,
            )
            rps_log: Dict = {"applied": rps_raw.return_code == 0, "result": rps_raw.__dict__}
            if rps_output is not None:
                rps_log["output"] = rps_output
                current_ps_path = ps_rewritten
                logger.info("rewriteProblemStatement succeeded")
            else:
                msg = f"rewriteProblemStatement failed (return_code={rps_raw.return_code})"
                logger.error(f"{msg}; keeping current problem statement")
                errors.append(msg)
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
        msg = f"{type(e).__name__}: {e}"
        logger.error(f"Failed to process {instance_id}: {e}", exc_info=True)
        errors.append(msg)

    return ProcessEntryResult(
        entry=entry, errors=errors, warnings=warnings
    )



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

    n_attempted = 0
    failed_entries: list[tuple[str, list[str]]] = []

    for i, entry in enumerate(entries, 1):
        instance_id = entry["instance_id"]
        logger.info("==========================================================================")
        logger.info(f"====== ⌛ Processing entry '{instance_id}' ({i}/{len(entries)}) ======")

        if config.skip_existing_entries and instance_id in already_processed:
            logger.info(f"Skipping '{instance_id}': already present in output file")
            logger.info(f"====== ⏭️  Skipped entry '{instance_id}' ({i}/{len(entries)}) ======")
            logger.info("==========================================================================")
            continue

        n_attempted += 1

        instance_env_vars = dict(env_vars)
        for env_entry in additional_envs:
            if env_entry.instance_id == instance_id:
                for env_var in env_entry.envs:
                    instance_env_vars[env_var.name] = env_var.value
                break

        result = process_entry(
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
        append_jsonl(config.output, result.entry)

        issues = result.errors + result.warnings  # combined for display; errors first
        if result.errors:
            failed_entries.append((instance_id, issues))
            issues_str = ''.join([f"\n     - {e}" for e in issues])
            logger.error(f"====== ❌ Completed entry '{instance_id}' ({i}/{len(entries)}) with errors:{issues_str}")
        elif result.warnings:
            issues_str = ''.join([f"\n     - {w}" for w in result.warnings])
            logger.warning(f"====== ⚠️  Completed entry '{instance_id}' ({i}/{len(entries)}) with warnings:{issues_str}")
        else:
            logger.info(f"====== ✅ Completed entry '{instance_id}' ({i}/{len(entries)}) ======")
        logger.info("==========================================================================")

    n_succeeded = n_attempted - len(failed_entries)
    logger.info("")
    logger.info("==========================================================================")
    logger.info(f"Processing complete! succeeded {n_succeeded}/{n_attempted}, failed {len(failed_entries)}/{n_attempted}")
    if failed_entries:
        logger.error("Failed entries:")
        for fid, fissues in failed_entries:
            issues_str = ''.join([f"\n     - {e}" for e in fissues])
            logger.error(f"  {fid}:{issues_str}")
    logger.info("==========================================================================")


if __name__ == "__main__":
    main()
