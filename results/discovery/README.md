# Evaluations Results

This folder contains evals that discover which benchmarks are aligible (buildable, fixable by the agent) for the final evaluation.

## Evaluations

1. `benchmarks_50_gpt5.4_runs_3`:
    - N: 3
    - model: GPT-5.4
    - benchmarks: 50 (all, multi-swe-bench-mini)
    - per_instance_cost_limit: 4.0
    - temperature: 1.0
    - reasoning_effort: high
    - top_p: omitted
    - goal: получить список instance_id пригодных для общего евала

1. `benchmarks_11_easy_gpt5.4_runs_4`:
    - N: 4
    - model: GPT-5.4
    - benchmarks: 11 (easy, multi-swe-bench-mini)
    - per_instance_cost_limit: 4.0
    - temperature: 1.0
    - reasoning_effort: high
    - top_p: omitted
    - goal: получить buildable easy инстансы для быстрых прогонов

