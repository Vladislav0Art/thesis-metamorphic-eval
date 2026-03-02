DEFAULT_CODE_COCCOON_TRANSFORMATIONS = [
    {
        'id': 'add-comment-transformation',
        'config': {
            'message': 'Hello from `add-comment-transformation`!'
        }
    }
]

# Default repository URLs for bootstrap init command
DEFAULT_REPO_URLS = {
    'codecoccoon': 'https://github.com/JetBrains-Research/CodeCocoon-Plugin',
    'mswe_agent': 'https://github.com/Vladislav0Art/MSWE-agent',
    'multi_swe_bench': 'https://github.com/Vladislav0Art/multi-swe-bench'
}

# Available benchmark datasets
BENCHMARK_DATASETS = {
    'Multi-SWE-bench': 'https://huggingface.co/datasets/ByteDance-Seed/Multi-SWE-bench',
    'Multi-SWE-bench_mini': 'https://huggingface.co/datasets/ByteDance-Seed/Multi-SWE-bench_mini'
}

# Valid difficulty levels
VALID_DIFFICULTIES = ['easy', 'medium', 'hard']
