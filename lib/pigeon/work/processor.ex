defmodule Pigeon.Work.Processor do
  @moduledoc """
  Generic work processor for distributed work validation and processing.

  Handles coordination between validator modules and worker nodes,
  providing a unified interface for any type of distributed work processing.
  """

  alias Pigeon.Communication.Hub
  alias Pigeon.Cluster.Manager
  alias Pigeon.Work.Validator

  @doc """
  Process work data using the specified validator module across distributed workers.

  ## Parameters
  - `work_data` - String containing the work data to process
  - `validator_module` - Module implementing `Pigeon.Work.Validator` behavior
  - `opts` - Optional configuration (workers, iterations, timeout)

  ## Examples

      iex> # This would require a running cluster in practice
      iex> # Pigeon.Work.Processor.process_distributed("test_work", MyValidator, workers: 2)
      iex> # {:ok, %{success_rate: 1.0, total_runs: 2, ...}}

  """
  def process_distributed(work_data, validator_module, opts \\ []) do
    with {:ok, :valid} <- Validator.validate_implementation(validator_module),
         {:ok, cluster_status} <- ensure_cluster_ready(opts),
         {:ok, job_id} <- submit_work_job(work_data, validator_module, opts),
         {:ok, results} <- wait_for_results(job_id, opts) do
      {:ok, format_results(results)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Process multiple work items in batch mode using the specified validator.
  """
  def process_batch_distributed(work_items, validator_module, opts \\ []) do
    with {:ok, :valid} <- Validator.validate_implementation(validator_module),
         {:ok, cluster_status} <- ensure_cluster_ready(opts),
         {:ok, job_results} <- process_work_items_batch(work_items, validator_module, opts) do
      {:ok, aggregate_batch_results(job_results)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List available validator modules in the system.
  """
  def list_validators do
    # This would typically scan for modules implementing the Validator behavior
    # For now, return a simple list that can be extended
    validators = [
      "Pigeon.Validators.GExpressionValidator",
      "Pigeon.Validators.JsonValidator",
      "Pigeon.Validators.CodeValidator"
    ]

    loaded_validators =
      Enum.filter(validators, fn validator_name ->
        case Validator.load_validator(validator_name) do
          {:ok, _module} -> true
          {:error, _reason} -> false
        end
      end)

    {:ok, loaded_validators}
  end

  # Private Functions

  defp ensure_cluster_ready(opts) do
    case Manager.get_status() do
      {:ok, status} ->
        if status.active_workers > 0 do
          {:ok, status}
        else
          {:error, "No active workers available"}
        end

      {:error, :no_cluster} ->
        {:error, "No cluster deployed. Run 'pigeon deploy' first."}

      {:error, reason} ->
        {:error, "Cluster status check failed: #{reason}"}
    end
  end

  defp submit_work_job(work_data, validator_module, opts) do
    job_data = %{
      type: :work_processing,
      data: %{
        work_data: work_data,
        validator_module: validator_module,
        iterations: opts[:iterations] || 5,
        worker_count: opts[:workers]
      }
    }

    Hub.submit_job(job_data)
  end

  defp process_work_items_batch(work_items, validator_module, opts) do
    # Process work items in parallel across available workers
    chunk_size = calculate_optimal_chunk_size(work_items, opts)
    chunks = Enum.chunk_every(work_items, chunk_size)

    chunk_jobs =
      Enum.map(chunks, fn chunk ->
        submit_work_job(chunk, validator_module, opts)
      end)

    # Wait for all chunk jobs to complete
    results =
      Enum.map(chunk_jobs, fn {:ok, job_id} ->
        wait_for_results(job_id, opts)
      end)

    {:ok, results}
  end

  defp wait_for_results(job_id, opts) do
    # 5 minutes default
    timeout = opts[:timeout] || 300_000
    # 2 seconds
    poll_interval = 2_000

    wait_for_completion(job_id, timeout, poll_interval)
  end

  defp wait_for_completion(job_id, timeout, poll_interval) do
    start_time = System.monotonic_time(:millisecond)

    Stream.repeatedly(fn -> :poll end)
    |> Enum.reduce_while({:waiting, nil}, fn :poll, {status, _} ->
      case Hub.get_job_status(job_id) do
        {:ok, job_status} ->
          cond do
            job_status.status == :completed ->
              {:halt, {:ok, job_status.results}}

            job_status.status == :failed ->
              {:halt, {:error, "Job failed"}}

            System.monotonic_time(:millisecond) - start_time > timeout ->
              {:halt, {:error, "Job timeout"}}

            true ->
              Process.sleep(poll_interval)
              {:cont, {:waiting, job_status}}
          end

        {:error, reason} ->
          {:halt, {:error, "Failed to get job status: #{reason}"}}
      end
    end)
  end

  defp calculate_optimal_chunk_size(work_items, opts) do
    worker_count = opts[:workers] || 3
    total_items = length(work_items)

    max(1, div(total_items, worker_count))
  end

  defp format_results(results) do
    worker_results = results |> Map.values()

    total_runs = Enum.sum(Enum.map(worker_results, &(&1.iterations || 1)))
    successes = Enum.sum(Enum.map(worker_results, &(&1.successes || 0)))
    errors = Enum.sum(Enum.map(worker_results, &(&1.errors || 0)))

    total_time = Enum.sum(Enum.map(worker_results, &(&1.execution_time_ms || 0)))
    average_time = if total_runs > 0, do: div(total_time, total_runs), else: 0

    %{
      total_runs: total_runs,
      successes: successes,
      errors: errors,
      success_rate: if(total_runs > 0, do: successes / total_runs, else: 0.0),
      average_time_ms: average_time,
      worker_results: format_worker_results(results),
      error_details: extract_error_details(worker_results)
    }
  end

  defp format_worker_results(results) do
    results
    |> Enum.map(fn {worker_id, result} ->
      total = result.iterations || 1
      successes = result.successes || 0

      {worker_id,
       %{
         total: total,
         successes: successes,
         success_rate: if(total > 0, do: successes / total, else: 0.0),
         execution_time_ms: result.execution_time_ms || 0
       }}
    end)
    |> Enum.into(%{})
  end

  defp extract_error_details(worker_results) do
    worker_results
    |> Enum.flat_map(fn result ->
      (result.errors || [])
      |> Enum.map(fn error ->
        %{
          worker: result.worker_id || "unknown",
          message: error.message || inspect(error),
          timestamp: error.timestamp || System.system_time(:second)
        }
      end)
    end)
  end

  defp aggregate_batch_results(job_results) do
    # Aggregate results from multiple batch jobs
    all_results = Enum.map(job_results, fn {:ok, results} -> results end)

    total_runs = Enum.sum(Enum.map(all_results, & &1.total_runs))
    total_successes = Enum.sum(Enum.map(all_results, & &1.successes))
    total_errors = Enum.sum(Enum.map(all_results, & &1.errors))

    %{
      total_runs: total_runs,
      successes: total_successes,
      errors: total_errors,
      success_rate: if(total_runs > 0, do: total_successes / total_runs, else: 0.0),
      batch_count: length(all_results),
      individual_results: all_results
    }
  end
end
