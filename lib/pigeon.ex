defmodule Pigeon do
  @moduledoc """
  Pigeon - Generic Distributed Work Processing Framework

  A minimal interface for spinning up configurable EC2 instances with
  containerized work processors for concurrent validation and processing
  against a centralized control node.

  ## Architecture

  - **Control Node**: Local development machine coordinating tasks
  - **Worker Nodes**: EC2 instances running containers with work processors
  - **Communication**: Centralized hub-and-spoke pattern
  - **Workload**: Configurable via validator modules

  ## Usage

      # Deploy cluster
      pigeon deploy --nodes 3

      # Process work with G-expression validator
      pigeon process --work-file data.json --validator Pigeon.Validators.GExpressionValidator

      # Process work with custom validator
      pigeon process --work-file code.txt --validator MyApp.CodeValidator --workers 3

  ## Examples

      # Deploy a cluster (requires AWS infrastructure)
      # {:ok, cluster_info} = Pigeon.deploy_cluster(nodes: 2)
      # {:ok, %{control_node: :local@node, workers: [...]}}

      # Process work using a validator (requires running cluster)
      # work_data = "{\\"g\\": \\"lit\\", \\"v\\": 42}"
      # {:ok, results} = Pigeon.process_work(work_data, Pigeon.Validators.GExpressionValidator)
      # {:ok, %{success_rate: 1.0, total_runs: 1, ...}}

      # Validate a validator module
      iex> Pigeon.validate_validator(Pigeon.Validators.GExpressionValidator)
      {:ok, :valid}

      # Submit work for processing
      pigeon process --work-file "data.txt" --validator MyApp.CodeValidator --workers 3

      # Monitor cluster status
      pigeon status

      # Scale cluster
      pigeon scale --nodes 5

      # Shutdown cluster
      pigeon destroy

  ## Validator Modules

  Pigeon accepts any module implementing the `Pigeon.Work.Validator` behavior:

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
  """

  alias Pigeon.Cluster.Manager
  alias Pigeon.Work.Processor
  alias Pigeon.Infrastructure.EC2Manager

  @doc """
  Deploy a cluster of worker nodes.

  ## Options

  - `:nodes` - Number of worker nodes to deploy (default: 2)
  - `:instance_type` - EC2 instance type (default: "t3.medium")
  - `:region` - AWS region (default: "us-west-2")

  ## Examples

      # Deploy cluster with custom options
      # {:ok, cluster_info} = Pigeon.deploy_cluster(nodes: 3, instance_type: "t3.large")
      # {:ok, %{control_node: :node@local, workers: [...], total_workers: 3}}

  """
  def deploy_cluster(opts \\ []) do
    Manager.deploy_cluster(opts)
  end

  @doc """
  Submit work for distributed processing using a validator module.

  ## Parameters

  - `work_data` - String containing the work data to process
  - `validator_module` - Module implementing `Pigeon.Work.Validator` behavior
  - `opts` - Optional configuration (workers, iterations, timeout)

  ## Examples

      # Process work with a validator (requires running cluster)
      # work_data = "{\\"g\\": \\"lit\\", \\"v\\": 42}"
      # {:ok, results} = Pigeon.process_work(work_data, Pigeon.Validators.GExpressionValidator)
      # {:ok, %{success_rate: 1.0, total_runs: 1, errors: 0, ...}}

  """
  def process_work(work_data, validator_module, opts \\ []) do
    Processor.process_distributed(work_data, validator_module, opts)
  end

  @doc """
  Submit batch work for distributed processing.

  ## Parameters

  - `work_items` - List of work data strings to process
  - `validator_module` - Module implementing `Pigeon.Work.Validator` behavior
  - `opts` - Optional configuration (workers, iterations, timeout)

  ## Examples

      # Process batch work (requires running cluster)
      # work_items = ["work1", "work2", "work3"]
      # {:ok, results} = Pigeon.process_work_batch(work_items, MyApp.Validator)
      # {:ok, %{total_runs: 3, success_rate: 1.0, batch_count: 1, ...}}

  """
  def process_work_batch(work_items, validator_module, opts \\ []) do
    Processor.process_batch_distributed(work_items, validator_module, opts)
  end

  @doc """
  Get the current cluster status.

  ## Examples

      # Get cluster status (requires running cluster)
      # {:ok, status} = Pigeon.cluster_status()
      # {:ok, %{cluster_status: :running, active_workers: 3, total_workers: 3, ...}}

  """
  def cluster_status do
    Manager.get_status()
  end

  @doc """
  Scale cluster up or down to the target number of nodes.

  ## Examples

      # Scale cluster (requires running cluster)
      # {:ok, result} = Pigeon.scale_cluster(5)
      # {:ok, %{added: 2, removed: 0, total: 5}}

  """
  def scale_cluster(target_nodes) do
    Manager.scale_to(target_nodes)
  end

  @doc """
  Destroy the entire cluster and clean up resources.

  ## Examples

      # Destroy cluster (requires running cluster)
      # {:ok, _result} = Pigeon.destroy_cluster()
      # {:ok, %{destroyed_workers: 3, cleanup_status: :complete}}

  """
  def destroy_cluster do
    Manager.destroy_cluster()
  end

  @doc """
  List available validator modules in the system.

  ## Examples

      # List available validators
      # {:ok, validators} = Pigeon.list_validators()
      # {:ok, ["Pigeon.Validators.GExpressionValidator", "MyApp.CustomValidator"]}

  """
  def list_validators do
    Processor.list_validators()
  end

  @doc """
  Validate that a module properly implements the `Pigeon.Work.Validator` behavior.

  ## Examples

      iex> Pigeon.validate_validator(Pigeon.Validators.GExpressionValidator)
      {:ok, :valid}

      iex> Pigeon.validate_validator(String)
      {:error, {:missing_callbacks, [validate: 2, validate_batch: 2, metadata: 0]}}

  """
  def validate_validator(module) do
    Pigeon.Work.Validator.validate_implementation(module)
  end
end
