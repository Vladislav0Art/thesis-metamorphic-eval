# Metamorphic Eval

```
thesis-metamorphic-eval/
├── agents/
├── benchmarks/
├── code-coccoon/
├── swe_bench/
├── scripts/
│   ├── bootstrap.py
```

## Bootstrap Script

The `bootstrap.py` script sets up the evaluation environment.

### Commands

#### 1. Init
Downloads required repositories:
```bash
python scripts/bootstrap.py init
# Or with custom URLs:
python scripts/bootstrap.py init --codecoccoon <url> --mswe_agent <url> --multi_swe_bench <url>
```

#### 2. Benchmark
Creates filtered benchmark datasets:
```bash
# Basic usage
python scripts/bootstrap.py benchmark Multi-SWE-bench_mini --language python --difficulty easy

# With random sampling
python scripts/bootstrap.py benchmark Multi-SWE-bench --language java --difficulty medium --rand 100

# With custom output path
python scripts/bootstrap.py benchmark Multi-SWE-bench_mini --language python --output my-benchmark.jsonl
```

