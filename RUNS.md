# Evaluation Runs


## Checklist

| Step                 | Transform | Patches Check | Evaluation (GPT-5.4) | Evaluation (Claude-Sonnet-4.6) |
|----------------------|-----------|---------------|--------------------------|--------------------------------|
| s0-original          | N/A       | N/A           | ✅ `N=5` `benchmarks=47`  | ❌                             |
| s1-renaming          | ❌        | ❌            | ❌                        | ❌                             |
| s2-structural        | ❌        | ❌            | ❌                    | ❌                             |
| s3-problem-statement | ✅        | ❌            | ...                   | ❌                             |
| s4-combined          | ❌        | ❌            | ❌                    | ❌                             |

**Total: 18 executions**



### s0-original

1. Evaluation (GPT-5.4):
```bash
cd artifacts/results/eval/s0-original

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/evaluate.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s0-original/s0_evaluate.yaml
```

1. Evaluation (Claude-Sonnet-4.6):
```bash
tbd
```


### s1-renaming


### s2-structural

1. Transform:
```bash
cd artifacts/benchmarks/eval/s2-structural

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s2-structural/s2_transform.yaml
```

1. Patches Check:
```bash

```

1. Evaluation (GPT-5.4):

1. Evaluation (Claude-Sonnet-4.6):


### s3-problem-statement

1. Transform:
```bash
cd artifacts/benchmarks/eval/s3-problem-statement

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s3-problem-statement/s3_transform.yaml
```

1. Patches Check:
```bash

```

1. Evaluation (GPT-5.4):

```bash
cd artifacts/results/eval/s3-problem-statement

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/evaluate.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s3-problem-statement/s3_evaluate.yaml
```

1. Evaluation (Claude-Sonnet-4.6):


### s4-combined




## How To Run

### Transformations

How to run (example with `s1-renaming`):

```bash
. ./venv/bin/activate
# to create transform.py in results folder
cd artifacts/results/eval/s1-renaming

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s1-renaming/s1_transform.yaml
```


### Patches Check

How to run (example with `s0-original`):

1. Generate patches:

```bash
python scripts/convert_model_predictions.py -t benchmark \
    -i artifacts/benchmarks/eval/s0-original/java_s0_original_47.jsonl \
    -o artifacts/patches/eval/s0-original/java_s0_original_47.jsonl
```

2. Run evaluation over patches:

```bash
cd artifacts/results/eval/s0-original

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/evaluate.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s0-original/s0_fix_patches.yaml
```



### Evaluation

How to run (example with `s0-original`):

```bash
cd artifacts/results/eval/s0-original

python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/evaluate.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s0-original/s0_evaluate.yaml
```