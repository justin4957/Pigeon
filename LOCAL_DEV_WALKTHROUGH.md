# Pigeon Local Development Walkthrough

This guide walks you through running Pigeon locally using Podman containers to simulate distributed worker nodes, allowing you to test the framework without AWS infrastructure.

## Prerequisites

- Elixir 1.15+
- Podman installed and running
- Basic familiarity with containers

## Quick Start

### 1. Install Dependencies

```bash
cd /path/to/pigeon
mix deps.get
```

### 2. Start Local Development Environment

```bash
# Terminal 1: Start the control node
./scripts/dev-start-control.sh

# Terminal 2: Start worker containers
./scripts/dev-start-workers.sh

# Terminal 3: Run tests and experiments
./scripts/dev-test.sh
```

## Detailed Walkthrough

### Step 1: Understanding the Local Architecture

In local development mode, we simulate the distributed architecture:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Control Node  │    │  Podman Worker1 │    │  Podman Worker2 │
│   (Host Elixir) │◄──►│   Port 8081     │    │   Port 8082     │
│   Port 4040     │    │   + Mock Ollama │    │   + Mock Ollama │
│                 │    │                 │    │                 │
│  • Job Queue    │    │  • Work Proc    │    │  • Work Proc    │
│  • Results Agg  │    │  • Validation   │    │  • Validation   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Step 2: Start the Control Node

Start the Pigeon control node in development mode:

```bash
# Set development environment
export MIX_ENV=dev
export PIGEON_MODE=local_dev
export PIGEON_WORKERS=local

# Start the control node
iex -S mix
```

In the IEX console:

```elixir
# Start the control hub
{:ok, _} = Pigeon.Communication.Hub.start_link(port: 4040)

# Verify it's running
Pigeon.Communication.Hub.get_worker_count()
```

### Step 3: Build and Start Worker Containers

Build the worker container image:

```bash
podman build -f containers/local-worker/Dockerfile -t pigeon/local-worker:latest .
```

Start multiple workers:

```bash
# Worker 1
podman run -d --name pigeon-worker-1 \
  -p 8081:8080 \
  -e CONTROL_NODE_HOST=host.containers.internal \
  -e CONTROL_NODE_PORT=4040 \
  -e WORKER_ID=worker-1 \
  pigeon/local-worker:latest

# Worker 2
podman run -d --name pigeon-worker-2 \
  -p 8082:8080 \
  -e CONTROL_NODE_HOST=host.containers.internal \
  -e CONTROL_NODE_PORT=4040 \
  -e WORKER_ID=worker-2 \
  pigeon/local-worker:latest
```

### Step 4: Verify Worker Registration

Back in the IEX console:

```elixir
# Check registered workers
{:ok, status} = Pigeon.Communication.Hub.get_status()
IO.inspect(status.workers)

# Should show 2 registered workers
```

### Step 5: Test Work Processing

Test the G-expression validator:

```elixir
# Load a test G-expression
work_data = """
{
  "g": "app",
  "v": {
    "fn": {"g": "ref", "v": "+"},
    "args": {
      "g": "vec",
      "v": [
        {"g": "lit", "v": 1},
        {"g": "lit", "v": 2}
      ]
    }
  }
}
"""

# Process across workers
{:ok, results} = Pigeon.process_work(
  work_data,
  Pigeon.Validators.GExpressionValidator,
  workers: 2,
  iterations: 3
)

IO.inspect(results)
```

### Step 6: Test Custom Validator

Create and test a simple validator:

```elixir
defmodule LocalDev.JsonValidator do
  @behaviour Pigeon.Work.Validator

  def validate(work_string, _opts) do
    case Jason.decode(work_string) do
      {:ok, data} ->
        {:ok, %{valid: true, keys: Map.keys(data), size: map_size(data)}}
      {:error, reason} ->
        {:error, %{message: "Invalid JSON: #{inspect(reason)}"}}
    end
  end

  def validate_batch(work_items, opts) do
    results = Enum.map(work_items, &validate(&1, opts))
    {:ok, results}
  end

  def metadata do
    %{
      name: "Local JSON Validator",
      version: "1.0.0",
      description: "Validates JSON for local development",
      supported_formats: ["json"]
    }
  end
end

# Test it
test_json = """
{"name": "test", "value": 42, "active": true}
"""

{:ok, result} = Pigeon.process_work(
  test_json,
  LocalDev.JsonValidator,
  workers: 2,
  iterations: 1
)

IO.inspect(result)
```

### Step 7: Monitor and Debug

Monitor worker health:

```elixir
# Get health status
{:ok, health} = Pigeon.Monitoring.HealthMonitor.get_health_status()
IO.inspect(health)

# Check specific worker
{:ok, worker_health} = Pigeon.Monitoring.HealthMonitor.check_worker_health("worker-1")
IO.inspect(worker_health)
```

View worker logs:

```bash
# Check worker logs
podman logs pigeon-worker-1
podman logs pigeon-worker-2

# Follow logs in real-time
podman logs -f pigeon-worker-1
```

## Testing Different Scenarios

### Scenario 1: Worker Failure Handling

Simulate a worker going down:

```bash
# Stop one worker
podman stop pigeon-worker-1
```

Test resilience:

```elixir
# This should still work with remaining worker
{:ok, results} = Pigeon.process_work(
  work_data,
  Pigeon.Validators.GExpressionValidator,
  workers: 1,
  iterations: 2
)
```

Restart the worker:

```bash
podman start pigeon-worker-1
```

### Scenario 2: High Load Testing

Process multiple work items concurrently:

```elixir
# Generate test work items
work_items = Enum.map(1..10, fn i ->
  Jason.encode!(%{"test_id" => i, "data" => "item_#{i}", "timestamp" => System.system_time()})
end)

# Process in batch
{:ok, batch_results} = Pigeon.process_work_batch(
  work_items,
  LocalDev.JsonValidator,
  workers: 2
)

IO.inspect(batch_results)
```

### Scenario 3: Performance Testing

Measure processing time:

```elixir
# Time the processing
{time_micros, {:ok, results}} = :timer.tc(fn ->
  Pigeon.process_work_batch(
    work_items,
    LocalDev.JsonValidator,
    workers: 2,
    iterations: 5
  )
end)

time_ms = time_micros / 1000
IO.puts("Processing took #{time_ms}ms")
IO.inspect(results)
```

## Cleanup

Stop all containers:

```bash
podman stop pigeon-worker-1 pigeon-worker-2
podman rm pigeon-worker-1 pigeon-worker-2
```

Or use the cleanup script:

```bash
./scripts/dev-cleanup.sh
```

## Troubleshooting

### Workers Not Connecting

1. Check if control node is running:
```bash
curl http://localhost:4040/health
```

2. Check worker connectivity:
```bash
podman exec pigeon-worker-1 curl http://host.containers.internal:4040/health
```

3. Check firewall/network settings

### Container Build Issues

1. Ensure Podman is running:
```bash
podman info
```

2. Check container build logs:
```bash
podman build --no-cache -f containers/local-worker/Dockerfile .
```

### Performance Issues

1. Increase worker count:
```bash
# Add more workers
for i in {3..5}; do
  podman run -d --name pigeon-worker-$i \
    -p $((8080+$i)):8080 \
    -e CONTROL_NODE_HOST=host.containers.internal \
    -e CONTROL_NODE_PORT=4040 \
    -e WORKER_ID=worker-$i \
    pigeon/local-worker:latest
done
```

2. Monitor resource usage:
```bash
podman stats
```

## Advanced Usage

### Custom Worker Configuration

Create workers with different capabilities:

```bash
# CPU-optimized worker
podman run -d --name pigeon-worker-cpu \
  --cpus="2.0" \
  -p 8083:8080 \
  -e CONTROL_NODE_HOST=host.containers.internal \
  -e CONTROL_NODE_PORT=4040 \
  -e WORKER_ID=worker-cpu \
  -e WORKER_TYPE=cpu-intensive \
  pigeon/local-worker:latest

# Memory-optimized worker
podman run -d --name pigeon-worker-memory \
  --memory="1g" \
  -p 8084:8080 \
  -e CONTROL_NODE_HOST=host.containers.internal \
  -e CONTROL_NODE_PORT=4040 \
  -e WORKER_ID=worker-memory \
  -e WORKER_TYPE=memory-intensive \
  pigeon/local-worker:latest
```

### Integration with Development Tools

Set up with hot reloading:

```bash
# Start with file watching
iex -S mix phx.server
```

Use with debugger:

```elixir
# Add breakpoints
require IEx; IEx.pry()
```

## Next Steps

1. **Deploy to Production**: Use the AWS deployment features
2. **Create Custom Validators**: Implement your own work validators
3. **Scale Testing**: Test with more workers and larger workloads
4. **Monitoring**: Set up proper logging and metrics

This local development setup gives you a complete testing environment for Pigeon without needing AWS infrastructure!