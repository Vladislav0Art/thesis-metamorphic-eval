"""
Bootstrap script for setting up the metamorphic evaluation environment.

Provides two main subcommands:
1. init: Downloads required repositories (code-coccoon, MSWE-agent, multi-swe-bench)
2. benchmark: Creates filtered benchmark datasets from Multi-SWE-bench
"""

import argparse
import logging
import os
import random
import re
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from common.cli import run_cli_command
from common.logger import configure_logging
from common.fs import read_jsonl, write_jsonl
from default.defaults import DEFAULT_REPO_URLS, BENCHMARK_DATASETS, VALID_DIFFICULTIES

# Configure logging
configure_logging(log_filename="bootstrap.log", level=logging.INFO)

logger = logging.getLogger(__name__)

# Get project root (parent of scripts directory)
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent

COMPONENTS_DIR = PROJECT_ROOT / 'components'
ARTIFACTS_DIR = PROJECT_ROOT / 'artifacts'

# Define target directories relative to project root
DIRS = {
    'code_coccoon': COMPONENTS_DIR / 'code-coccoon',
    'agents': COMPONENTS_DIR / 'agents',
    'swe_bench': COMPONENTS_DIR / 'swe_bench',

    'benchmarks': ARTIFACTS_DIR / 'benchmarks',
    'benchmark_downloads': ARTIFACTS_DIR / 'benchmarks' / 'downloads'
}

_INSTANCE_ID_V1 = re.compile(r'^([^/]+)/([^:]+):pr-(\d+)$')
_INSTANCE_ID_V2 = re.compile(r'^(.+?)__(.+?)-(\d+)$')


def normalize_instance_id(iid: str) -> str:
    """Convert variant 1 (org/repo:pr-N) to variant 2 (org__repo-N). Pass-through otherwise."""
    m = _INSTANCE_ID_V1.match(iid)
    if m:
        org, repo, number = m.groups()
        return f"{org}__{repo}-{number}"
    return iid


def denormalize_instance_id(iid: str) -> str:
    """Convert variant 2 (org__repo-N) to variant 1 (org/repo:pr-N). Pass-through otherwise."""
    m = _INSTANCE_ID_V2.match(iid)
    if m:
        org, repo, number = m.groups()
        return f"{org}/{repo}:pr-{number}"
    return iid


DATASET_ALIASES = {
    'default':              'Multi-SWE-bench',
    'Multi-SWE-bench':      'Multi-SWE-bench',
    'mini':                 'Multi-SWE-bench_mini',
    'Multi-SWE-bench_mini': 'Multi-SWE-bench_mini',
}


def ensure_directories():
    """Create necessary directories if they don't exist."""
    for dir_path in DIRS.values():
        dir_path.mkdir(parents=True, exist_ok=True)
        logger.debug(f"Ensured directory exists: {dir_path}")


def check_git_lfs():
    """Check if git-lfs is installed."""
    stdout, stderr, returncode = run_cli_command('git', ['lfs', 'version'])
    if returncode != 0:
        logger.error("git-lfs is not installed. Please install it first: https://git-lfs.github.com/")
        return False
    logger.info(f"git-lfs is installed: {stdout.strip()}")
    return True


def extract_repo_name(repo_url: str) -> str:
    """
    Extract repository name from Git URL.

    Args:
        repo_url: URL of the repository

    Returns:
        Repository name without .git extension
    """
    # Extract the last part of the URL
    repo_name = repo_url.rstrip('/').split('/')[-1]
    # Remove .git extension if present
    if repo_name.endswith('.git'):
        repo_name = repo_name[:-4]
    return repo_name


def clone_repository(repo_url: str, target_dir: Path):
    """
    Clone a git repository into the target directory.

    Args:
        repo_url: URL of the repository to clone
        target_dir: Directory where the repository should be cloned

    Returns:
        bool: True if successful, False otherwise
    """
    repo_name = extract_repo_name(repo_url)
    repo_path = target_dir / repo_name

    if repo_path.exists() and (repo_path / '.git').exists():
        logger.warning(f"{repo_name} already exists at {repo_path}. Skipping clone.")
        return True

    logger.info(f"Cloning {repo_name} from {repo_url} into {target_dir}...")
    stdout, stderr, returncode = run_cli_command(
        'git',
        ['clone', repo_url, str(repo_path)]
    )

    if returncode != 0:
        logger.error(f"Failed to clone {repo_name}: {stderr}")
        return False

    logger.info(f"Successfully cloned {repo_name}")
    return True


def init_command(args):
    """
    Execute the init subcommand to download required repositories.

    Args:
        args: Parsed command-line arguments
    """
    logger.info("Starting init command...")
    ensure_directories()

    # Get repository URLs from args or defaults
    codecoccoon_url = args.codecoccoon or DEFAULT_REPO_URLS['codecoccoon']
    mswe_agent_url = args.mswe_agent or DEFAULT_REPO_URLS['mswe_agent']
    multi_swe_bench_url = args.multi_swe_bench or DEFAULT_REPO_URLS['multi_swe_bench']

    # Clone repositories
    success = True
    success &= clone_repository(codecoccoon_url, DIRS['code_coccoon'])
    success &= clone_repository(mswe_agent_url, DIRS['agents'])
    success &= clone_repository(multi_swe_bench_url, DIRS['swe_bench'])

    if success:
        logger.info("Init command completed successfully!")
    else:
        logger.error("Init command completed with errors.")
        sys.exit(1)


def download_benchmark_dataset(dataset_name: str) -> Path:
    """
    Download a benchmark dataset from HuggingFace.

    Args:
        dataset_name: Name of the dataset (e.g., 'Multi-SWE-bench' or 'Multi-SWE-bench_mini')

    Returns:
        Path to the downloaded dataset directory
    """
    if dataset_name not in BENCHMARK_DATASETS:
        raise ValueError(f"Unknown dataset: {dataset_name}. Available: {list(BENCHMARK_DATASETS.keys())}")

    if not check_git_lfs():
        raise RuntimeError("`git-lfs` is required to download benchmark datasets (See: https://git-lfs.com)")

    dataset_url = BENCHMARK_DATASETS[dataset_name]
    target_dir = DIRS['benchmark_downloads'] / dataset_name

    if target_dir.exists() and any(target_dir.iterdir()):
        logger.info(f"Dataset {dataset_name} already exists at {target_dir}")
        return target_dir

    logger.info(f"Downloading {dataset_name} from {dataset_url}...")
    stdout, stderr, returncode = run_cli_command(
        'git',
        ['clone', dataset_url, str(target_dir)]
    )

    if returncode != 0:
        raise RuntimeError(f"Failed to download {dataset_name}: {stderr}")

    logger.info(f"Successfully downloaded {dataset_name}")
    return target_dir


def find_jsonl_files(dataset_dir: Path, dataset_name: str, language: str = None) -> list[Path]:
    """
    Find JSONL files in the downloaded dataset directory.

    For mini datasets (flat structure): returns a single JSONL file.
    For the full dataset (nested by language): collects all JSONL files under
    the language subdirectory (or all language subdirectories if language is None).

    Args:
        dataset_dir: Directory containing the dataset
        dataset_name: Name of the dataset
        language: Language subdirectory to search (e.g. 'java'); None means all

    Returns:
        List of paths to JSONL files
    """
    is_mini = dataset_name.endswith('_mini')

    if is_mini:
        expected_filename = dataset_name.replace('-', '_').lower() + '.jsonl'
        jsonl_path = dataset_dir / expected_filename
        if jsonl_path.exists():
            return [jsonl_path]
        jsonl_files = list(dataset_dir.glob('*.jsonl'))
        if jsonl_files:
            logger.warning(f"Expected {expected_filename} not found, using {jsonl_files[0].name}")
            return [jsonl_files[0]]
        raise FileNotFoundError(f"No JSONL file found in {dataset_dir}")

    # Full dataset: nested structure {dataset_dir}/{language}/*.jsonl
    if language:
        lang_dir = dataset_dir / language.lower()
        if not lang_dir.exists():
            raise FileNotFoundError(f"Language directory not found: {lang_dir}")
        jsonl_files = sorted(lang_dir.glob('*.jsonl'))
        if not jsonl_files:
            raise FileNotFoundError(f"No JSONL files found in {lang_dir}")
        logger.info(f"Found {len(jsonl_files)} JSONL files in {lang_dir}")
        return jsonl_files

    # No language filter: collect from all language subdirectories
    jsonl_files = sorted(dataset_dir.glob('*/*.jsonl'))
    if not jsonl_files:
        raise FileNotFoundError(f"No JSONL files found under {dataset_dir}")
    logger.info(f"Found {len(jsonl_files)} JSONL files across all languages")
    return jsonl_files


def filter_entries(entries: list, language: str = None, difficulty: str = None, instance_ids: list = None) -> list:
    """
    Filter benchmark entries by language, difficulty, and instance IDs.

    Args:
        entries: List of benchmark entries
        language: Language to filter by (case-insensitive), None to skip
        difficulty: Difficulty level to filter by (case-insensitive), None to skip
        instance_ids: List of instance IDs to filter by, None to skip

    Returns:
        Filtered list of entries
    """
    filtered = entries

    if language:
        language_lower = language.lower()
        filtered = [e for e in filtered if e.get('language', '').lower() == language_lower]
        logger.info(f"Filtered by language '{language}': {len(filtered)} entries remain")

    if difficulty:
        difficulty_lower = difficulty.lower()
        if difficulty_lower not in VALID_DIFFICULTIES:
            logger.warning(f"Invalid difficulty '{difficulty}'. Valid values: {VALID_DIFFICULTIES}")
        filtered = [e for e in filtered if e.get('difficulty', '').lower() == difficulty_lower]
        logger.info(f"Filtered by difficulty '{difficulty}': {len(filtered)} entries remain")

    if instance_ids:
        instance_ids_set = set(instance_ids)
        filtered = [e for e in filtered if e.get('instance_id') in instance_ids_set]
        logger.info(f"Filtered by instance_ids: {len(filtered)} entries remain")

    return filtered


def _load_dataset_entries(dataset_name: str, language: str | None) -> list:
    """Download (if needed) and read all entries from a dataset.

    For the full dataset, `language` selects the language subdirectory.
    For mini datasets, `language` is ignored at the file level (filter later via filter_entries).
    """
    dataset_dir = download_benchmark_dataset(dataset_name)
    jsonl_files = find_jsonl_files(dataset_dir, dataset_name, language)
    entries = []
    for jsonl_file in jsonl_files:
        logger.info(f"Reading benchmark data from {jsonl_file}...")
        entries.extend(read_jsonl(str(jsonl_file)))
    logger.info(f"Total entries loaded from '{dataset_name}': {len(entries)}")
    return entries


def benchmark_command(args):
    """
    Execute the benchmark subcommand to create filtered benchmark datasets.

    Args:
        args: Parsed command-line arguments
    """
    logger.info("Starting benchmark command...")
    ensure_directories()

    # Validate difficulty
    if args.difficulty and (args.difficulty.lower() not in VALID_DIFFICULTIES):
        logger.error(f"Invalid difficulty '{args.difficulty}'. Must be one of: {VALID_DIFFICULTIES}")
        sys.exit(1)

    # Parse instance_ids if provided
    instance_ids = None
    if args.instance_ids:
        instance_ids = [id.strip() for id in args.instance_ids.split(',')]
        logger.info(f"Filtering by {len(instance_ids)} instance IDs: {instance_ids}")

    # Download and read entries
    try:
        entries = _load_dataset_entries(args.name, args.language)
    except Exception as e:
        logger.error(f"Failed to prepare benchmark dataset: {e}")
        sys.exit(1)

    # For the full (non-mini) dataset, language was already applied at the directory
    # level in find_jsonl_files, so entries have no 'language' field to filter on.
    is_mini = args.name.endswith('_mini')
    filter_language = args.language if is_mini else None
    filtered_entries = filter_entries(entries, filter_language, args.difficulty, instance_ids)

    if not filtered_entries:
        logger.warning("No entries match the specified filters!")
        sys.exit(0)

    # Random sampling if requested (mutually exclusive with instance_ids)
    if args.rand is not None:
        n = args.rand
        if n > len(filtered_entries):
            logger.warning(f"Requested {n} random entries but only {len(filtered_entries)} available")
            n = len(filtered_entries)

        filtered_entries = random.sample(filtered_entries, n)
        logger.info(f"Randomly selected {n} entries")

    # Determine output path
    if args.output:
        output_path = Path(args.output)
    else:
        # Build filename: [language]-[difficulty]-[N].jsonl
        parts = []
        if args.language:
            parts.append(args.language.lower())
        else:
            parts.append("all")

        if args.difficulty:
            parts.append(args.difficulty.lower())

        parts.append(str(len(filtered_entries)))

        if (args.name is not None) and args.name.endswith('_mini'):
            parts.append("mini")

        filename = '_'.join(parts) + '.jsonl' if parts else 'benchmark.jsonl'
        output_path = DIRS['benchmarks'] / filename

    # Ensure output directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Write filtered entries
    write_jsonl(str(output_path), filtered_entries)
    logger.info(f"Benchmark created successfully: {output_path}")


def info_command(args):
    """List filtered benchmark instances together with their difficulty level.

    For the full dataset (which carries no 'difficulty' field), each entry is
    looked up in the mini dataset; '-' is used when no match is found.
    Output is printed as an aligned table and optionally saved to a file.
    """
    logger.info("Starting info command...")
    ensure_directories()

    dataset_name = DATASET_ALIASES[args.dataset]
    is_mini = dataset_name.endswith('_mini')

    instance_ids = None
    if args.instance_ids:
        instance_ids = [normalize_instance_id(iid.strip()) for iid in args.instance_ids.split(',')]

    # Load and filter the requested dataset
    try:
        entries = _load_dataset_entries(dataset_name, args.language)
    except Exception as e:
        logger.error(f"Failed to load dataset '{dataset_name}': {e}")
        sys.exit(1)

    filter_language = args.language if is_mini else None
    filtered = filter_entries(entries, filter_language, difficulty=None, instance_ids=instance_ids)

    if not filtered:
        logger.warning("No entries match the specified filters.")
        sys.exit(0)

    # Build mini difficulty index when using the full dataset.
    # Mini is a subset of the full dataset and carries 'difficulty' per entry.
    mini_difficulty: dict[str, str] = {}
    if not is_mini:
        try:
            mini_entries = _load_dataset_entries('Multi-SWE-bench_mini', language=None)
            mini_difficulty = {e['instance_id']: e.get('difficulty', '-') for e in mini_entries}
            logger.info(f"Loaded {len(mini_difficulty)} entries from mini for difficulty lookup")
        except Exception as e:
            logger.warning(f"Could not load mini dataset for difficulty lookup: {e}")

    # Build rows: (instance_id, difficulty)
    rows = [
        (
            entry.get('instance_id', '?'),
            entry.get('difficulty') or mini_difficulty.get(entry.get('instance_id', ''), '-'),
        )
        for entry in filtered
    ]

    # Summary
    found_ids = {iid for iid, _ in rows}
    if instance_ids is not None:
        not_found = [iid for iid in instance_ids if iid not in found_ids]
        summary = f"Found: {len(rows)}/{len(instance_ids)} instance_ids"
        if not_found:
            summary += f" (not found: {', '.join(not_found)})"
    else:
        summary = f"Total: {len(rows)} instance_ids"

    # Render output
    if args.format == 'json':
        import json
        output = json.dumps(
            [
                {
                    "instance_id": {
                        "agent":      iid,
                        "evaluation": denormalize_instance_id(iid),
                    },
                    "difficulty": diff,
                }
                for iid, diff in rows
            ],
            indent=2,
        )
    else:
        col_width = max(len('instance_id'), max(len(iid) for iid, _ in rows))
        header    = f"{'instance_id':<{col_width}}  difficulty"
        separator = '-' * len(header)
        body      = '\n'.join(f"{iid:<{col_width}}  {diff}" for iid, diff in rows)
        output    = '\n'.join([header, separator, body, separator, summary])

    print(output)
    if args.format == 'json':
        print(summary)

    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output + '\n')
        logger.info(f"Output saved to {args.output}")


def main():
    """Main entry point for the bootstrap script."""
    parser = argparse.ArgumentParser(
        description='Bootstrap script for metamorphic evaluation setup'
    )
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Init subcommand
    init_parser = subparsers.add_parser('init', help='Download required repositories')

    init_parser.add_argument('--codecoccoon', type=str, default=DEFAULT_REPO_URLS["codecoccoon"],
                            help=f'URL for CodeCocoon repository (default: {DEFAULT_REPO_URLS["codecoccoon"]})')
    init_parser.add_argument('--mswe_agent', type=str, default=DEFAULT_REPO_URLS["mswe_agent"],
                             help=f'URL for MSWE-agent repository (default: {DEFAULT_REPO_URLS["mswe_agent"]})')
    init_parser.add_argument('--multi_swe_bench', type=str, default=DEFAULT_REPO_URLS["multi_swe_bench"],
                             help=f'URL for multi-swe-bench repository (default: {DEFAULT_REPO_URLS["multi_swe_bench"]})')


    # Benchmark subcommand
    benchmark_parser = subparsers.add_parser('benchmark', help='Create filtered benchmark dataset')
    benchmark_parser.add_argument('name', choices=list(BENCHMARK_DATASETS.keys()),
                                  help='Benchmark dataset name')
    benchmark_parser.add_argument('--language', type=str, default=None, help='Filter by programming language')
    benchmark_parser.add_argument('--difficulty', type=str, default=None, choices=VALID_DIFFICULTIES,
                                  help='Filter by difficulty level')

    # Create mutually exclusive group for rand and instance_ids
    selection_group = benchmark_parser.add_mutually_exclusive_group()
    selection_group.add_argument('--rand', type=int, metavar='N',
                                  help='Randomly select N entries')
    selection_group.add_argument('--instance_ids', type=str,
                                  help='Comma-separated list of instance IDs to filter (e.g., "id1,id2,id3")')

    benchmark_parser.add_argument('--output', help='Output file path')

    # Info subcommand
    info_parser = subparsers.add_parser(
        'info',
        help='List filtered benchmark instances with difficulty levels',
    )
    info_parser.add_argument(
        '--dataset',
        type=str,
        default='mini',
        choices=list(DATASET_ALIASES.keys()),
        metavar='{default,Multi-SWE-bench,mini,Multi-SWE-bench_mini}',
        help='Dataset to query (default: mini)',
    )
    info_parser.add_argument('--language', type=str, default='java', help='Filter by language (default: java)')
    info_parser.add_argument(
        '--instance_ids', type=str,
        help='Comma-separated list of instance IDs to filter',
    )
    info_parser.add_argument('--output', type=str, help='Optional output file path')
    info_parser.add_argument(
        '--format',
        type=str,
        default='plain',
        choices=['plain', 'json'],
        help='Output format: plain (default) or json',
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Execute appropriate command
    if args.command == 'init':
        init_command(args)
    elif args.command == 'benchmark':
        benchmark_command(args)
    elif args.command == 'info':
        info_command(args)


if __name__ == '__main__':
    main()
