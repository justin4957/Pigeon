# Pigeon Local Development - Quick Start

Get Pigeon running locally with Podman in 5 minutes!

## 🚀 One-Command Setup

```bash
# 1. Clone and setup
cd pigeon
mix deps.get

# 2. Start everything (3 terminals)
./scripts/dev-start-control.sh    # Terminal 1
./scripts/dev-start-workers.sh    # Terminal 2
./scripts/dev-test.sh             # Terminal 3
```

## 🧪 Quick Test

In the IEx session from terminal 3:

```elixir
# Test G-expression processing
work_data = """
{
  "g": "app",
  "v": {
    "fn": {"g": "ref", "v": "+"},
    "args": {
      "g": "vec",
      "v": [{"g": "lit", "v": 1}, {"g": "lit", "v": 2}]
    }
  }
}
"""

{:ok, results} = Pigeon.process_work(
  work_data,
  Pigeon.Validators.GExpressionValidator,
  workers: 2,
  iterations: 3
)

IO.inspect(results)
```

Expected output:
```elixir
%{
  average_time_ms: 75,
  errors: 0,
  success_rate: 1.0,
  total_runs: 3,
  worker_results: %{
    "worker-1" => %{successes: 2, total: 2, success_rate: 1.0},
    "worker-2" => %{successes: 1, total: 1, success_rate: 1.0}
  }
}
```

## 🎯 What Just Happened?

1. **Control Node**: Started on port 4040, coordinates all work
2. **Worker 1**: Podman container on port 8081, processes work
3. **Worker 2**: Podman container on port 8082, processes work
4. **Work Distribution**: G-expression sent to workers, results aggregated

## 🛠️ Troubleshooting

### Workers not connecting?
```bash
# Check control node
curl http://localhost:4040/health

# Check workers
curl http://localhost:8081/health
curl http://localhost:8082/health
```

### Container issues?
```bash
# Check container status
podman ps -a

# View logs
podman logs pigeon-worker-1
podman logs pigeon-worker-2

# Rebuild if needed
./scripts/dev-cleanup.sh
./scripts/dev-start-workers.sh
```

## 🧹 Cleanup

```bash
./scripts/dev-cleanup.sh
```

## 📖 Full Walkthrough

See [LOCAL_DEV_WALKTHROUGH.md](LOCAL_DEV_WALKTHROUGH.md) for detailed explanations and advanced usage.

---

**That's it!** You now have a fully distributed Pigeon cluster running locally. 🎉