# Pigeon 🕊️

**Generic Distributed Work Processing Framework**

Pigeon is a distributed work processing framework that supports both local development with Podman containers and cloud deployment via AWS EC2 instances for scalable concurrent validation and processing.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Control Node  │    │  Worker Node 1  │    │  Worker Node N  │
│   (Local/Cloud) │◄──►│ Podman/EC2 +    │    │ Podman/EC2 +    │
│                 │    │ Ollama + Code   │    │ Ollama + Code   │
│  • Job Queue    │    │                 │    │                 │
│  • Results Agg  │    │  • Work Proc    │ .. │  • Work Proc    │
│  • Coordination │    │  • Validation   │    │  • Validation   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Features

### 🚀 **Development & Deployment**
- **Local Development**: Podman-based containerized environment with hot reload
- **Cloud Deployment**: One-command EC2 cluster deployment
- **Container Orchestration**: Automatic Ollama/CodeLlama setup in both environments
- **Dynamic Scaling**: Add/remove nodes locally or in the cloud

### 🧪 **Generic Work Processing**
- Pluggable validator modules for any work type
- Distributed processing and validation
- Concurrent work execution across multiple nodes
- Built-in result aggregation and error handling

### 🕸️ **Centralized Coordination**
- Hub-and-spoke communication pattern
- Job queue and work distribution
- Real-time status monitoring
- Automatic failover and retry logic

### 📊 **Built-in Analytics**
- Success rate tracking across workers
- Performance timing analysis
- Error aggregation and reporting
- Worker health monitoring

## Quick Start

### Prerequisites
- Elixir 1.15+
- Podman (for local development)
- AWS CLI (for cloud deployment - optional)

### Installation

```bash
git clone https://github.com/your-org/pigeon.git
cd pigeon

# Complete setup (dependencies, config, scripts)
make setup

# OR manual installation:
mix deps.get
mix escript.build
```

## Local Development (Recommended)

Pigeon provides a complete local development environment using Podman containers:

### Start Development Environment

```bash
# Start local development cluster
make dev
# OR
./scripts/dev.sh start

# Start with extended workers (CPU/Memory optimized)
make extended
# OR
./scripts/dev.sh start --extended
```

### Development Workflow

```bash
# Check environment status
make status

# Process work locally
./pigeon process --work-file examples/fibonacci.json --validator Pigeon.Validators.GExpressionValidator --workers 3

# Run CI/CD pipeline locally (before committing)
make ci

# Quick development checks
make check

# View logs from all services
make logs

# Stop environment
make stop
```

### Available Local Services

- **Control Node**: http://localhost:4040 (coordinates work distribution)
- **Worker 1**: http://localhost:8081 (general purpose)
- **Worker 2**: http://localhost:8082 (general purpose)
- **CPU Worker**: http://localhost:8083 (CPU-intensive tasks, extended mode)
- **Memory Worker**: http://localhost:8084 (memory-intensive tasks, extended mode)

### Development Features

- **Hot Reload**: Source code changes are automatically reflected
- **Container Caching**: Fast rebuilds with dependency and build caching
- **Health Monitoring**: Automatic health checks for all workers
- **CI/CD Emulation**: Local pipeline testing before commits
- **Debug Support**: Detailed logging and container inspection tools
- **Profile Support**: Different worker configurations (general, CPU, memory)

## Cloud Deployment (AWS EC2)

For production workloads or when local resources are insufficient:

```bash
# Deploy a 3-node cluster
./pigeon deploy --nodes 3 --instance-type t3.medium --region us-west-2

# Process work using cloud workers
./pigeon process --work-file examples/fibonacci.json --validator Pigeon.Validators.GExpressionValidator --workers 3 --iterations 5

# Check cluster status
./pigeon status --detailed

# Scale up to 5 nodes
./pigeon scale --nodes 5

# Destroy everything
./pigeon destroy --force
```

## Validator Modules

Pigeon accepts any module implementing the `Pigeon.Work.Validator` behavior:

```elixir
defmodule MyApp.CustomValidator do
  @behaviour Pigeon.Work.Validator

  def validate(work_string, opts) do
    # Process work_string and return result
    {:ok, result}
  end

  def validate_batch(work_items, opts) do
    # Process multiple work items
    {:ok, results}
  end

  def metadata() do
    %{
      name: "Custom Validator",
      version: "1.0.0",
      description: "Processes custom work formats",
      supported_formats: ["text", "json"]
    }
  end
end
```

## Use Cases

### 1. **Local G-Expression Validation**
Validate G-expressions using local development environment:

```bash
# Start development environment
make dev

# Process with local workers
./pigeon process \
  --work-file my-function.json \
  --validator Pigeon.Validators.GExpressionValidator \
  --workers 4 \
  --iterations 10
```

### 2. **Custom Code Validation**
Process any type of work with custom validators:

```bash
# Local development
./pigeon process \
  --work-file source-code.txt \
  --validator MyApp.CodeValidator \
  --workers 2  # Uses local workers

# Cloud deployment (for larger workloads)
./pigeon deploy --nodes 6
./pigeon process \
  --work-file source-code.txt \
  --validator MyApp.CodeValidator \
  --workers 6 \
  --iterations 5
```

### 3. **Batch Processing**
Process large datasets - start locally, scale to cloud:

```bash
# Start with local development for testing
make dev
./pigeon process --work-file batch-data-sample.json --validator MyApp.DataProcessor --workers 2

# Scale to cloud for full dataset
./pigeon deploy --nodes 8 --instance-type c5.xlarge
./pigeon process --work-file batch-data-full.json --validator MyApp.DataProcessor --workers 8
```

## Local Development Details

### Development Scripts

Pigeon includes powerful development scripts for container management:

#### `./scripts/dev.sh` - Environment Management
```bash
./scripts/dev.sh start [--extended] [--rebuild] [--no-control]
./scripts/dev.sh stop
./scripts/dev.sh restart [--rebuild]
./scripts/dev.sh status
./scripts/dev.sh logs
./scripts/dev.sh clean
```

#### `./scripts/pod-test.sh` - CI/CD Pipeline
```bash
./scripts/pod-test.sh                    # Full CI/CD pipeline
./scripts/pod-test.sh --skip-tests       # Skip test suite
./scripts/pod-test.sh --debug            # Debug mode
./scripts/pod-test.sh --no-cleanup       # Preserve containers
```

### Makefile Commands

Convenient shortcuts for common tasks:

```bash
make setup      # Initial project setup
make dev        # Start development environment
make ci         # Run CI/CD pipeline locally
make test       # Run local tests
make check      # Quick code quality check
make health     # Check all service health
make clean      # Clean up containers
```

### Container Architecture

- **Network Isolation**: Dedicated `pigeon_network` for service communication
- **Volume Caching**: Persistent `deps_cache` and `build_cache` for faster rebuilds
- **Health Monitoring**: Automatic health checks with 30s intervals
- **Resource Limits**: CPU and memory constraints for specialized workers
- **Profile Support**: Optional extended workers via Docker Compose profiles

### Environment Configuration

Copy `.env.example` to `.env.local` and customize:

```bash
# Worker configuration
WORKER_NODES=pigeon-worker-1:8080,pigeon-worker-2:8080

# Control node settings
CONTROL_NODE_HOST=localhost
CONTROL_NODE_PORT=4040

# Development settings
MIX_ENV=dev
DEBUG=true
```

## Architecture Details

### Reused Components from Grapple
Pigeon adapts several battle-tested components from the Grapple distributed graph database:

- **Cluster Management**: From `Grapple.Distributed.ClusterManager`
- **Node Discovery**: From `Grapple.Distributed.Discovery`
- **Health Monitoring**: From `Grapple.Distributed.HealthMonitor`
- **CLI Framework**: From `Grapple.CLI.Shell`

### Communication Protocol
- **Hub-and-Spoke**: Control node coordinates all worker communication
- **HTTP/JSON**: RESTful API for worker registration and job submission
- **Heartbeat System**: Workers send status updates every 30 seconds
- **Graceful Failures**: Automatic job reassignment on worker failures
- **Environment Agnostic**: Same protocol works for local Podman and AWS EC2 workers

### Container Stack
Each worker node runs (both locally and in cloud):

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    ports: ["11434:11434"]

  pigeon-worker:
    build:
      context: .
      dockerfile: containers/local-worker/Dockerfile  # Local
      # dockerfile: containers/worker/Dockerfile      # Cloud
    ports: ["8080:8080"]
    depends_on: [ollama]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s

  model-init:
    image: ollama/ollama:latest
    command: ["ollama", "pull", "codellama:7b"]
```

## API Reference

### CLI Commands

#### Local Development Commands

**`make dev` / `./scripts/dev.sh start`**
Start local development environment
- `--extended`: Start CPU/Memory optimized workers
- `--rebuild`: Force rebuild containers
- `--no-control`: Don't auto-start control node

**`make ci` / `./scripts/pod-test.sh`**
Run CI/CD pipeline locally
- `--skip-tests`: Skip test suite
- `--debug`: Debug mode with detailed output
- `--no-cleanup`: Preserve containers for inspection

#### Cloud Deployment Commands

**`deploy`**
Deploy EC2 worker cluster
- `--nodes, -n`: Number of worker nodes (default: 2)
- `--instance-type, -t`: EC2 instance type (default: t3.medium)
- `--region, -r`: AWS region (default: us-west-2)
- `--key-name, -k`: EC2 key pair name

#### Universal Commands

**`process`**
Submit work for distributed processing (works with local or cloud workers)
- `--work-file, -f`: File containing work data to process (required)
- `--validator, -v`: Validator module to use for processing (required)
- `--workers, -w`: Number of workers to use for processing
- `--iterations, -i`: Processing iterations per worker (default: 5)

**`status`**
Show cluster status (local or cloud)
- `--detailed, -d`: Show detailed worker information

#### Cloud-Only Commands

**`scale`**
Scale cloud cluster up or down
- `--nodes, -n`: Target number of nodes (required)

**`destroy`**
Destroy cloud cluster
- `--force, -f`: Skip confirmation prompt

### Programmatic API

```elixir
# Deploy cluster
{:ok, cluster_info} = Pigeon.deploy_cluster(nodes: 4, instance_type: "t3.large")

# Process work with validator
{:ok, results} = Pigeon.process_work(work_data, MyApp.Validator, workers: 3, iterations: 10)

# Process batch work
{:ok, results} = Pigeon.process_work_batch(work_items, MyApp.Validator, workers: 3)

# Check status
{:ok, status} = Pigeon.cluster_status()

# Scale cluster
{:ok, _} = Pigeon.scale_cluster(6)

# Cleanup
{:ok, _} = Pigeon.destroy_cluster()
```

### Validator Behavior API

All validators must implement the `Pigeon.Work.Validator` behavior:

```elixir
@callback validate(work_string :: String.t(), opts :: keyword()) ::
  {:ok, result :: any()} | {:error, reason :: any()}

@callback validate_batch(work_items :: [String.t()], opts :: keyword()) ::
  {:ok, results :: [any()]} | {:error, reason :: any()}

@callback metadata() :: %{
  name: String.t(),
  version: String.t(),
  description: String.t(),
  supported_formats: [String.t()]
}

@callback generate_test_cases(count :: integer(), opts :: keyword()) :: [String.t()]
```

## Built-in Validators

### G-Expression Validator
Validates G-expressions (generalized functional program representations):

```bash
./pigeon process \
  --work-file fibonacci.json \
  --validator Pigeon.Validators.GExpressionValidator \
  --workers 3
```

Supports:
- Syntax validation
- Semantic analysis
- Variable binding checks
- Test case generation

## AWS EC2 Cloud Deployment

### AWS Setup
For cloud deployment, configure AWS credentials and permissions:

```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_DEFAULT_REGION=us-west-2
```

### Instance Types
Recommended instance types based on workload:

- **t3.medium**: Light processing (2 vCPU, 4GB RAM)
- **t3.large**: Standard workloads (2 vCPU, 8GB RAM)
- **c5.xlarge**: CPU-intensive tasks (4 vCPU, 8GB RAM)
- **m5.xlarge**: Memory-intensive processing (4 vCPU, 16GB RAM)

### Cloud Deployment Commands

```bash
# Deploy cluster
./pigeon deploy --nodes 3 --instance-type t3.medium --region us-west-2

# Scale cluster
./pigeon scale --nodes 5

# Monitor status
./pigeon status --detailed

# Destroy cluster
./pigeon destroy --force
```

## Testing & Quality Assurance

### Local Testing
```bash
# Run unit tests
make test
# OR
mix test

# Run complete CI/CD pipeline locally
make ci

# Quick quality checks
make check

# Run with coverage
mix test --cover
```

### Integration Testing
```bash
# Run integration tests (requires AWS or local containers)
mix test --include integration

# Test with local containers
./scripts/dev.sh start
mix test --include integration:local
```

### Building Containers
```bash
# Build worker container
podman build -f containers/local-worker/Dockerfile -t pigeon/worker:latest .

# Build development container
podman build -f containers/Dockerfile.dev -t pigeon/dev:latest .

# Build and tag for registry
podman build -t your-registry/pigeon-worker:v1.0 .
podman push your-registry/pigeon-worker:v1.0
```

### Creating Custom Validators

1. Implement the `Pigeon.Work.Validator` behavior
2. Add validation logic for your work type
3. Include metadata describing your validator
4. Optionally implement test case generation

Example:

```elixir
defmodule MyProject.JsonValidator do
  @behaviour Pigeon.Work.Validator

  def validate(json_string, _opts) do
    case Jason.decode(json_string) do
      {:ok, _data} -> {:ok, %{valid: true}}
      {:error, reason} -> {:error, %{message: "Invalid JSON: #{reason}"}}
    end
  end

  def validate_batch(json_strings, opts) do
    results = Enum.map(json_strings, &validate(&1, opts))
    {:ok, results}
  end

  def metadata do
    %{
      name: "JSON Validator",
      version: "1.0.0",
      description: "Validates JSON syntax",
      supported_formats: ["json"]
    }
  end

  def generate_test_cases(count, _opts) do
    Enum.map(1..count, fn i ->
      Jason.encode!(%{"test" => i, "valid" => true})
    end)
  end
end
```

## Recommended Development Workflow

### 1. Setup and Initial Development
```bash
# Initial setup
git clone https://github.com/your-org/pigeon.git
cd pigeon
make setup

# Start local development environment
make dev

# Verify environment health
make health
```

### 2. Code, Test, and Iterate
```bash
# Make your code changes
# ...

# Quick quality check
make check

# Run tests locally
make test

# Run complete CI/CD pipeline (before committing)
make ci
```

### 3. Scale to Cloud (When Needed)
```bash
# Test with more resources or real AWS environment
./pigeon deploy --nodes 3
./pigeon process --work-file large-dataset.json --validator YourValidator --workers 3
./pigeon destroy --force
```

### 4. Development vs Production

| Aspect | Local Development | Cloud Deployment |
|--------|------------------|------------------|
| **Setup Time** | ~30 seconds | ~5-10 minutes |
| **Cost** | Free | AWS EC2 costs |
| **Resources** | Limited by local machine | Scalable |
| **Network** | Local containers | Internet required |
| **Debugging** | Full access, hot reload | Remote debugging |
| **Use Case** | Development, testing, small workloads | Production, large datasets |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. **Run local CI pipeline**: `make ci` (ensures compatibility)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Before Submitting PRs

```bash
# Ensure code quality and tests pass
make ci

# Test with extended workers if relevant
make extended
./pigeon process --work-file test-data.json --validator YourValidator
```

## License

MIT License - see LICENSE file for details.

## Troubleshooting

### Common Issues

**Podman machine not running:**
```bash
podman machine start
```

**Port conflicts:**
```bash
lsof -i :4040  # Control node
lsof -i :8081  # Workers
# Kill conflicting processes or change ports in podman-compose.yml
```

**Container build failures:**
```bash
make clean
make dev --rebuild
```

**Workers not connecting:**
```bash
# Check container logs
make logs

# Check health status
make health

# Debug mode
./scripts/pod-test.sh --debug --no-cleanup
```

## Acknowledgments

- **Grapple**: For distributed infrastructure components
- **Ollama**: For local AI model serving
- **CodeLlama**: For code generation capabilities
- **Podman**: For local container orchestration
- **Melas**: For validation patterns and inspiration