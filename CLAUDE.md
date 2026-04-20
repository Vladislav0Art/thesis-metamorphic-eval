# Metamorphic Eval

## What This Project Does

This is a thesis research project that measures the drop in AI agent pass rates when metamorphic transformations are applied to Java software engineering benchmarks. The hypothesis is that agents relying on memorized training data will perform worse on semantically equivalent but syntactically different code.

The pipeline takes Java instances from [Multi-SWE-bench](https://github.com/Vladislav0Art/multi-swe-bench), applies source-level metamorphic transformations via [CodeCocoon-Plugin](https://github.com/JetBrains-Research/CodeCocoon-Plugin), runs [MSWE-agent](https://github.com/Vladislav0Art/MSWE-agent) (a fork of SWE-agent) on both the original and transformed benchmarks, and compares pass rates.

## Pipeline Overview

```
1. bootstrap.py init          Clone CodeCocoon-Plugin, MSWE-agent, multi-swe-bench
2. bootstrap.py benchmark     Download and filter Multi-SWE-bench → benchmark JSONL
3. transform.py               Apply metamorphic transformations → metamorphic JSONL
4. evaluate.py                Run MSWE-agent + multi_swe_bench harness → final_report.json
```

Steps 3 and 4 can be run independently. `evaluate.py` also handles the agent-only or evaluation-only subsets of step 4.

## Scripts

### `scripts/evaluate.py` — primary orchestrator

Ties together the full eval pipeline via a YAML config file.

```bash
python scripts/evaluate.py --config path/to/evaluate.yaml
```

See `evaluate.example.yaml` for a fully annotated config. The config declares which steps to run (`agent`, `evaluation`, or both) and all paths/parameters for each step.

**Pipeline steps:**

- `agent` — checks out the MSWE-agent branch, sets up its venv, writes `keys.cfg`, runs the agent (serially via `run.py` or in parallel via `multirun.py`), discovers the trajectory folder, optionally copies it into the run archive, and converts `all_preds.jsonl` → `fix_patches.jsonl`.
- `evaluation` — checks out the multi_swe_bench branch, sets up its venv, resolves `fix_patches.jsonl` (from agent step or explicit config), auto-generates `config.json`, and runs the harness.

**Artefacts per run** are written under `{workdir}/run-{N}/`:
- `result.json` — manifest with paths to every produced artefact and per-step success/error
- `predictions/fix_patches.jsonl`
- `trajectories/` (optional copy)
- `eval/output/final_report.json` — primary pass-rate metric

After all N runs, `{workdir}/metrics_summary.json` is written with pooled cost/token stats and averaged pass rates.

**Internal modules** (under `scripts/eval/`):
- `config.py` — dataclasses + `load_config()` (YAML → `EvalConfig`)
- `metrics.py` — pure math functions; importable directly in Jupyter notebooks
- `steps/base.py` — `Step` ABC + `StepResult`
- `steps/agent.py` — `AgentStep`
- `steps/evaluation.py` — `EvaluationStep`
- `steps/setup.py` — idempotent venv setup helper

---

### `scripts/transform.py` — metamorphic transformation

Applies CodeCocoon-Plugin transformations to each benchmark entry in a JSONL file, producing a new metamorphic JSONL.

```bash
python scripts/transform.py \
    -i benchmarks/input.jsonl \
    -o benchmarks/metamorphic.jsonl \
    -s MyStrategy \
    -c code-coccoon/CodeCocoon-Plugin \
    -r repos/ \
    -t transformations/sample.json \
    [-e path/to/.env] \
    [--override] \
    [--transform_test_files]
```

**What it does per benchmark entry:**

1. Clones the repo at `repos/{strategy}/{instance_id}/repo/` and checks out `base.sha`
2. Generates a `codecocoon.yml` config pointing at files changed by the fix patch (and optionally test patch)
3. Runs CodeCocoon in headless mode three times — on `base`, on `base + test_patch`, on `base + fix_patch` — each on its own branch (`{strategy}-base-transformation`, etc.)
4. Computes diffs between the metamorphic commits
5. Writes results back into the entry:
   - `base.metamorphic_base_patch` — transformation diff on the raw base commit
   - `test_patch` — replaced with `new_morphed_test_patch` (diff between morphed-base and morphed-base+test)
   - `fix_patch` — replaced with `new_morphed_fix_patch` (diff between morphed-base and morphed-base+fix)
   - `metamorphic[strategy]` — full audit trail (patches, commits, CodeCocoon logs)

MSWE-agent and multi_swe_bench both apply `base.metamorphic_base_patch` during Docker image build (requires their `vartiukhov/metamorphic-testing` branch).

---

### `scripts/bootstrap.py` — one-time setup

```bash
# Clone all three external repos into agents/, code-coccoon/, swe_bench/
python scripts/bootstrap.py init

# Download Multi-SWE-bench_mini and filter to a JSONL subset
python scripts/bootstrap.py benchmark Multi-SWE-bench_mini \
    --language java --difficulty easy [--rand 10] [--instance_ids id1 id2]
```

Output benchmark files land in `benchmarks/` with names like `java_easy_11_mini.jsonl`.

---

### `scripts/convert_model_predictions.py`

Converts MSWE-agent's `all_preds.jsonl` output to the format expected by multi_swe_bench.

```bash
python scripts/convert_model_predictions.py \
    -i agents/MSWE-agent/trajectories/.../all_preds.jsonl \
    -o results/predictions/fix_patches.jsonl
```

Parses `instance_id` of form `org__repo-number` to extract `org`, `repo`, `number`.

---

### `scripts/extract_patches.py`

Extracts per-instance patches (base, fix, test) from a metamorphic JSONL into separate files in a directory tree. Useful for manual inspection or debugging individual benchmark entries.

---

### `scripts/collect_swe_java_benchmarks.py`

Merges multiple JSONL files from a directory into a single output file.

---

## Configuration

### `evaluate.example.yaml`

Annotated template for `evaluate.py`. Copy and edit before running:

```yaml
run:
  workdir: ../results/my_eval_run   # all artefacts go here
  steps: [agent, evaluation]        # or just [agent] or [evaluation]
  N: 1                              # number of independent runs

steps:
  agent:
    dir: ../agents/MSWE-agent
    branch: vartiukhov/metamorphic-testing
    setup:
      venv: ./.venv
      prepare: ["uv venv"]          # runs WITHOUT venv
      install: ["uv pip install -r requirements.txt"]  # runs WITH venv
    keys:
      path: ./keys.cfg
      values:
        OPENAI_API_KEY: "..."
    runner:
      parallel: false               # true → multirun.py
      threads: 16
    copy_trajectories: true
    config:
      model_name: gpt4o
      benchmark_file: ../benchmarks/java_easy_11_mini.jsonl
      per_instance_cost_limit: 5.0
      temperature: 0.0
      skip_existing: true

  evaluation:
    dir: ../swe_bench/multi-swe-bench
    branch: vartiukhov/metamorphic-testing
    setup:
      venv: ./venv
      prepare: ["python3 -m venv ./venv"]
      install: ["make install"]
    share_repos: true
    config:
      dataset_files:
        - ../benchmarks/java_easy_11_mini.jsonl
      # patch_files: auto-resolved from agent step; set explicitly for eval-only runs
```

### `transformations/sample.json`

JSON list of CodeCocoon transformation objects passed to `transform.py -t`:

```json
[
  {
    "id": "add-comment-transformation",
    "config": {
      "message": "Comment text added to each file."
    }
  }
]
```

---

## Key Conventions

- **All relative paths in `evaluate.yaml`** are resolved relative to the config file's own directory, not the CWD.
- **Benchmark dataset filename must contain the word `java`** for multi_swe_bench to select the correct evaluation environment.
- **MSWE-agent and multi_swe_bench must both be on branch `vartiukhov/metamorphic-testing`** to handle `base.metamorphic_base_patch` correctly.
- **`transform.py` branches** inside each cloned repo follow the pattern `{strategy}-base-transformation`, `{strategy}-test-transformation`, `{strategy}-fix-transformation`. Re-running with `--override` deletes and recreates them.
- **CodeCocoon** requires `GRAZIE_TOKEN` for some transformations. Supply it via `-e path/to/.env` (a dotenv file with `GRAZIE_TOKEN=...`).
- **`skip_existing: true`** in the agent config means runs 2..N of a multi-run evaluation will skip already-processed instances. Set to `false` when each run must process all instances independently.
- **`result.json`** is written after every step so partial results survive failures.
- **`metrics_summary.json`** at the workdir root aggregates pooled cost/token stats and pass rates across all N runs. Functions in `scripts/eval/metrics.py` are directly importable in Jupyter notebooks.
