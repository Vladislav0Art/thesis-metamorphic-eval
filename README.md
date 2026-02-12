# Metamorphic Eval

```
thesis-metamorphic-eval/
├── datasets/           # Downloaded benchmark instances
├── transformations/    # Your IntelliJ plugin (as submodule?)
├── agents/            # Agent runner scripts
├── results/           # Evaluation outputs
├── scripts/           # Pipeline orchestration
│   ├── transform.sh   # Runs IntelliJ headless
│   ├── run_agent.sh   # Executes agent
│   └── evaluate.sh    # Validates & collects metrics
└── analysis/          # Jupyter notebooks for metrics
```