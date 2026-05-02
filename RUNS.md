# Evaluation Runs


## Checklist


### Runs for 5 benchmarks (small)

| Step                 | Transform | Patches Check | Evaluation (GPT-5.4) | Evaluation (Claude-Sonnet-4.6)     |
|----------------------|-----------|---------------|--------------------------|--------------------------------|
| s0-original          | N/A       | N/A           | next `N=10`              | ❌                             |
| s1-renaming          | ❌        | ❌            | ❌                        | ❌                             |
| s2-structural        | ✅ 1/5    | ❌            | ❌                        | ❌                             |
| s3-problem-statement | ✅ 5/5    | ❌            | ✅ `N=10`                 | ❌                             |
| s4-combined          | ❌        | ❌            | ❌                        | ❌                             |


### Runs for 47 benchmarks (full)

| Step                 | Transform | Patches Check | Evaluation (GPT-5.4) | Evaluation (Claude-Sonnet-4.6)     |
|----------------------|-----------|---------------|--------------------------|--------------------------------|
| s0-original          | N/A       | N/A           | ✅ `N=5`                 | ❌                             |
| s1-renaming          | ❌        | ❌            | ❌                        | ❌                             |
| s2-structural        | ✅ 8/47   | ❌            | ❌                        | ❌                             |
| s3-problem-statement | ✅        | ❌            | ✅ `N=5`                  | ❌                             |
| s4-combined          | ❌        | ❌            | ❌                        | ❌                             |


1. s1-renaming:
1. s2-structural: 8/47 (fully: all files moved), /47 (partially: some files moved, some not)


**Total: 18 runs**



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

1. Transform:
```bash
cd artifacts/benchmarks/eval/s1-renaming

# full (47 benchmarks)
python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s1-renaming/s1_transform.yaml

# small (5 benchmarks)
python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s1-renaming/s1_small_transform.yaml
```


### s2-structural

1. Transform:
```bash
cd artifacts/benchmarks/eval/s2-structural

# small (5 benchmarks)
python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s2-structural/small/s2_small_transform.yaml

# full (47 benchmarks)
python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/transform.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s2-structural/full/s2_transform.yaml
```

1. Patches Check:
```bash
cd artifacts/patches/eval/s2-structural/java_47_s2_runs_3_patches

# full (47 benchmarks)
python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/evaluate.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s2-structural/full/s2_fix_patches.yaml
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

# 5 benchmarks (small)
python /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/scripts/evaluate.py \
    --config /Users/vartiukhov/dev/studies/hse/thesis/thesis-metamorphic-eval/setup/configs/eval/s3-problem-statement/small/s3_small_evaluate.yaml

# 47 benchmarks (full)
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


## Benchmark Instances

47 instances. Sorted by difficulty (easy → medium → hard → unknown), then by baseline score descending.


**Selection of 5 for smaller eval:**

| # | instance_id | baseline (s0) | difficulty |
|---|---|---|---|
| 1 | `fasterxml__jackson-core-1142` | 5/5 | — |
| 2 | `google__gson-1391` | 5/5 | — |
| 3 | `elastic__logstash-14970` | 4/5 | — |
| 4 | `elastic__logstash-14981` | 4/5 | medium |
| 5 | `elastic__logstash-16681` | 3/5 | medium |



**Full table:**

| instance_id | difficulty | baseline (s0) |
|---|:---:|:---:|
| `fasterxml__jackson-core-183`<br>`fasterxml/jackson-core:pr-183` | easy | 1/5 |
| `mockito__mockito-3129`<br>`mockito/mockito:pr-3129` | easy | 1/5 |
| `alibaba__fastjson2-82`<br>`alibaba/fastjson2:pr-82` | easy | 0/5 |
| `fasterxml__jackson-databind-1923`<br>`fasterxml/jackson-databind:pr-1923` | easy | 0/5 |
| `elastic__logstash-14981`<br>`elastic/logstash:pr-14981` | medium | 4/5 |
| `elastic__logstash-16681`<br>`elastic/logstash:pr-16681` | medium | 3/5 |
| `google__gson-1093`<br>`google/gson:pr-1093` | medium | 2/5 |
| `fasterxml__jackson-core-370`<br>`fasterxml/jackson-core:pr-370` | medium | 1/5 |
| `apache__dubbo-11781`<br>`apache/dubbo:pr-11781` | medium | 0/5 |
| `elastic__logstash-13914`<br>`elastic/logstash:pr-13914` | medium | 0/5 |
| `fasterxml__jackson-core-174`<br>`fasterxml/jackson-core:pr-174` | medium | 0/5 |
| `googlecontainertools__jib-4144`<br>`googlecontainertools/jib:pr-4144` | medium | 0/5 |
| `googlecontainertools__jib-4035`<br>`googlecontainertools/jib:pr-4035` | medium | 0/5 |
| `mockito__mockito-3167`<br>`mockito/mockito:pr-3167` | medium | 0/5 |
| `elastic__logstash-17020`<br>`elastic/logstash:pr-17020` | hard | 0/5 |
| `elastic__logstash-16579`<br>`elastic/logstash:pr-16579` | hard | 0/5 |
| `elastic__logstash-14058`<br>`elastic/logstash:pr-14058` | hard | 0/5 |
| `elastic__logstash-14045`<br>`elastic/logstash:pr-14045` | hard | 0/5 |
| `elastic__logstash-14027`<br>`elastic/logstash:pr-14027` | hard | 0/5 |
| `elastic__logstash-14000`<br>`elastic/logstash:pr-14000` | hard | 0/5 |
| `elastic__logstash-13997`<br>`elastic/logstash:pr-13997` | hard | 0/5 |
| `elastic__logstash-13930`<br>`elastic/logstash:pr-13930` | hard | 0/5 |
| `elastic__logstash-13902`<br>`elastic/logstash:pr-13902` | hard | 0/5 |
| `elastic__logstash-13825`<br>`elastic/logstash:pr-13825` | hard | 0/5 |
| `fasterxml__jackson-core-1142`<br>`fasterxml/jackson-core:pr-1142` | - | 5/5 |
| `google__gson-1391`<br>`google/gson:pr-1391` | - | 5/5 |
| `elastic__logstash-14970`<br>`elastic/logstash:pr-14970` | - | 4/5 |
| `google__gson-1555`<br>`google/gson:pr-1555` | - | 2/5 |
| `alibaba__fastjson2-2285`<br>`alibaba/fastjson2:pr-2285` | - | 0/5 |
| `alibaba__fastjson2-2097`<br>`alibaba/fastjson2:pr-2097` | - | 0/5 |
| `alibaba__fastjson2-1245`<br>`alibaba/fastjson2:pr-1245` | - | 0/5 |
| `apache__dubbo-10638`<br>`apache/dubbo:pr-10638` | - | 0/5 |
| `elastic__logstash-17021`<br>`elastic/logstash:pr-17021` | - | 0/5 |
| `elastic__logstash-16094`<br>`elastic/logstash:pr-16094` | - | 0/5 |
| `elastic__logstash-15928`<br>`elastic/logstash:pr-15928` | - | 0/5 |
| `elastic__logstash-15697`<br>`elastic/logstash:pr-15697` | - | 0/5 |
| `elastic__logstash-15000`<br>`elastic/logstash:pr-15000` | - | 0/5 |
| `elastic__logstash-14898`<br>`elastic/logstash:pr-14898` | - | 0/5 |
| `elastic__logstash-14897`<br>`elastic/logstash:pr-14897` | - | 0/5 |
| `elastic__logstash-14878`<br>`elastic/logstash:pr-14878` | - | 0/5 |
| `elastic__logstash-13931`<br>`elastic/logstash:pr-13931` | - | 0/5 |
| `fasterxml__jackson-databind-2036`<br>`fasterxml/jackson-databind:pr-2036` | - | 0/5 |
| `googlecontainertools__jib-2542`<br>`googlecontainertools/jib:pr-2542` | - | 0/5 |
| `mockito__mockito-3424`<br>`mockito/mockito:pr-3424` | - | 0/5 |
| `mockito__mockito-3220`<br>`mockito/mockito:pr-3220` | - | 0/5 |
| `mockito__mockito-3173`<br>`mockito/mockito:pr-3173` | - | 0/5 |
| `mockito__mockito-3133`<br>`mockito/mockito:pr-3133` | - | 0/5 |


## Successfully Transformed Projects

### s2-structural

Projects that resulted in successful transformation: 8/47.


**NOTES**:

1. Only `move-file-into-suggested-directory-transformation/ai` failed.
1. Some runs had several files under transformations -> partial set of files might have been moved (the run would still be deemed as failed).
1. 8 successful runs == 8 instance ids where no transformation, for all files, has failed.

Projects that fully succeeded (8/47):

1. apache__dubbo-10638 (6/47)
1. elastic__logstash-17021 (7/47)
1. elastic__logstash-17020 (8/47)
1. elastic__logstash-16579 (10/47)
1. elastic__logstash-16094 (11/47)
1. elastic__logstash-13914 (27/47) - WARN: no Java files changed!
1. fasterxml__jackson-core-370 (31/47)
1. fasterxml__jackson-databind-1923 (45/47)


Projects that partially succeeded (13/47):

1. `elastic__logstash-14058` (20/47)
1. `elastic__logstash-14045` (21/47) (no base/fix metamorphic patches generated!)
1. `elastic__logstash-14027` (22/47)
1. `elastic__logstash-14000` (23/47)
1. `elastic__logstash-13997` (24/47)
1. `elastic__logstash-13931` (25/47)
1. `elastic__logstash-13930` (26/47)
1. `elastic__logstash-13902` (28/47)
1. `fasterxml__jackson-databind-2036` (34/47)
1. `googlecontainertools__jib-4144` (39/47)
1. `mockito__mockito-3220` (43/47)
1. `mockito__mockito-3133` (46/47)
1. `mockito__mockito-3129` (47/47)

