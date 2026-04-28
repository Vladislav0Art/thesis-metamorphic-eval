# Evaluation Runs

## Checklist

| Step                 | Transform | Patches Check | Evaluation |
|----------------------|-----------|---------------|------------|
| s0-original          | ❌        | ❌            | ❌          |
| s1-renaming          | ❌        | ❌            | ❌          |
| s2-structural        | ❌        | ❌            | ❌          |
| s3-problem-statement | ❌        | ❌            | ❌          |
| s4-combined          | ❌        | ❌            | ❌          |



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

