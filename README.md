# Pigeon 🕊️

**Generic Distributed Work Processing Framework**

Pigeon is a minimal CLI interface for spinning up configurable EC2 instances with containerized work processors for concurrent validation and processing against a centralized control node.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Control Node  │    │  Worker Node 1  │    │  Worker Node N  │
│   (Local Dev)   │◄──►│   EC2 + Ollama  │    │   EC2 + Ollama  │
│                 │    │   + CodeLlama   │    │   + CodeLlama   │
│  • Job Queue    │    │                 │    │                 │
│  • Results Agg  │    │  • Work Proc    │ .. │  • Work Proc    │
│  • Coordination │    │  • Validation   │    │  • Validation   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Features

### 🚀 **Infrastructure Management**
- One-command EC2 cluster deployment
- Automatic Ollama/CodeLlama container setup
- Dynamic scaling (add/remove nodes)
- Terraform-like infrastructure as code

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
- AWS CLI configured with appropriate permissions
- Elixir 1.15+
- Docker/Podman (for local development)

### Installation

```bash
git clone https://github.com/your-org/pigeon.git
cd pigeon
mix deps.get
mix escript.build
```

### Basic Usage

```bash
# Deploy a 3-node cluster
./pigeon deploy --nodes 3 --instance-type t3.medium --region us-west-2

# Process work using G-expression validator
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

### 1. **G-Expression Validation**
Validate G-expressions (functional program representations):

```bash
./pigeon process \
  --work-file my-function.json \
  --validator Pigeon.Validators.GExpressionValidator \
  --workers 4 \
  --iterations 10
```

### 2. **Custom Code Validation**
Process any type of work with custom validators:

```bash
./pigeon process \
  --work-file source-code.txt \
  --validator MyApp.CodeValidator \
  --workers 6 \
  --iterations 5
```

### 3. **Batch Processing**
Process large datasets in parallel:

```bash
./pigeon process \
  --work-file batch-data.json \
  --validator MyApp.DataProcessor \
  --workers 8
```

## Configuration

### AWS Setup
Pigeon requires AWS credentials and permissions for EC2, VPC, and Security Groups:

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

### Container Stack
Each worker node runs:

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    ports: ["11434:11434"]

  pigeon-worker:
    build: containers/worker
    ports: ["8080:8080"]
    depends_on: [ollama]

  model-init:
    image: ollama/ollama:latest
    command: ["ollama", "pull", "codellama:7b"]
```

## API Reference

### CLI Commands

#### `deploy`
Deploy EC2 worker cluster
- `--nodes, -n`: Number of worker nodes (default: 2)
- `--instance-type, -t`: EC2 instance type (default: t3.medium)
- `--region, -r`: AWS region (default: us-west-2)
- `--key-name, -k`: EC2 key pair name

#### `process`
Submit work for distributed processing
- `--work-file, -f`: File containing work data to process (required)
- `--validator, -v`: Validator module to use for processing (required)
- `--workers, -w`: Number of workers to use for processing
- `--iterations, -i`: Processing iterations per worker (default: 5)

#### `status`
Show cluster status
- `--detailed, -d`: Show detailed worker information

#### `scale`
Scale cluster up or down
- `--nodes, -n`: Target number of nodes (required)

#### `destroy`
Destroy entire cluster
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

## Development

### Running Locally
For development and testing without AWS:

```bash
# Start control node
mix run --no-halt

# In separate terminal, simulate workers
docker-compose -f containers/compose.yml up
```

### Testing
```bash
# Run unit tests
mix test

# Run integration tests (requires AWS)
mix test --include integration

# Run with coverage
mix test --cover

# Generate documentation
mix docs
```

### Building Containers
```bash
# Build worker container
docker build -f containers/worker/Dockerfile -t pigeon/worker:latest .

# Build and push to registry
docker build -t your-registry/pigeon-worker:v1.0 .
docker push your-registry/pigeon-worker:v1.0
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

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- **Grapple**: For distributed infrastructure components
- **Ollama**: For local AI model serving
- **CodeLlama**: For code generation capabilities
- **Melas**: For validation patterns and inspiration