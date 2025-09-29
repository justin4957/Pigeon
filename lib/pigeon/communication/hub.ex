defmodule Pigeon.Communication.Hub do
  @moduledoc """
  Centralized communication hub for coordinating with worker nodes.
  Implements hub-and-spoke pattern for distributed work processing.
  """

  use GenServer
  require Logger

  alias Pigeon.Communication.Protocol
  alias Pigeon.Jobs.JobManager
  alias Pigeon.Resilience.CircuitBreaker
  alias Pigeon.Resilience.Retry
  alias Pigeon.Resilience.FailureDetector

  defstruct [
    :control_node,
    :workers,
    :active_jobs,
    :job_queue,
    :message_handlers,
    :failed_jobs,
    :circuit_breakers
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_worker(worker_info) do
    GenServer.call(__MODULE__, {:register_worker, worker_info})
  end

  def submit_job(job_data) do
    GenServer.call(__MODULE__, {:submit_job, job_data})
  end

  def get_job_status(job_id) do
    GenServer.call(__MODULE__, {:get_job_status, job_id})
  end

  def distribute_work(work_items) do
    GenServer.call(__MODULE__, {:distribute_work, work_items})
  end

  def worker_result(worker_id, job_id, result) do
    GenServer.cast(__MODULE__, {:worker_result, worker_id, job_id, result})
  end

  def worker_heartbeat(worker_id, status) do
    GenServer.cast(__MODULE__, {:worker_heartbeat, worker_id, status})
  end

  # GenServer Implementation

  def init(opts) do
    control_node = node()

    state = %__MODULE__{
      control_node: control_node,
      workers: %{},
      active_jobs: %{},
      job_queue: :queue.new(),
      message_handlers: %{},
      failed_jobs: %{},
      circuit_breakers: %{}
    }

    # Start failure detector and register failure callback
    {:ok, _} = FailureDetector.start_link()
    FailureDetector.add_failure_callback(&handle_worker_failure/2)

    # Start HTTP server for worker communication
    start_communication_server(opts)

    Logger.info("Pigeon Communication Hub started on #{control_node}")
    {:ok, state}
  end

  def handle_call({:register_worker, worker_info}, _from, state) do
    worker_id = worker_info.worker_id

    updated_worker =
      Map.merge(worker_info, %{
        registered_at: System.system_time(:second),
        last_heartbeat: System.system_time(:second),
        status: :idle
      })

    new_workers = Map.put(state.workers, worker_id, updated_worker)

    # Register worker with failure detector
    FailureDetector.register_worker(worker_id, worker_info)

    # Create circuit breaker for this worker
    circuit_breaker_name = "worker_#{worker_id}"
    {:ok, _} = CircuitBreaker.start_link(name: circuit_breaker_name, failure_threshold: 3)

    new_circuit_breakers = Map.put(state.circuit_breakers, worker_id, circuit_breaker_name)
    new_state = %{state | workers: new_workers, circuit_breakers: new_circuit_breakers}

    Logger.info("Worker registered: #{worker_id} at #{worker_info.endpoint}")

    # Send welcome message to worker with retry
    send_worker_message_with_resilience(
      worker_info.endpoint,
      :welcome,
      %{
        control_node: state.control_node,
        worker_id: worker_id,
        assigned_at: System.system_time(:second)
      },
      worker_id
    )

    {:reply, {:ok, :registered}, new_state}
  end

  def handle_call({:submit_job, job_data}, _from, state) do
    job_id = generate_job_id()

    job = %{
      id: job_id,
      type: job_data.type,
      data: job_data.data,
      submitted_at: System.system_time(:second),
      status: :pending,
      assigned_workers: [],
      results: %{}
    }

    new_jobs = Map.put(state.active_jobs, job_id, job)
    new_queue = :queue.in(job, state.job_queue)

    new_state = %{state | active_jobs: new_jobs, job_queue: new_queue}

    # Try to assign job immediately
    updated_state = assign_pending_jobs(new_state)

    {:reply, {:ok, job_id}, updated_state}
  end

  def handle_call({:get_job_status, job_id}, _from, state) do
    case Map.get(state.active_jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      job ->
        status = build_job_status(job)
        {:reply, {:ok, status}, state}
    end
  end

  def handle_call({:distribute_work, work_items}, _from, state) do
    case distribute_work_items(work_items, state) do
      {:ok, assignments} ->
        {:reply, {:ok, assignments}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_cast({:worker_result, worker_id, job_id, result}, state) do
    case Map.get(state.active_jobs, job_id) do
      nil ->
        Logger.warn("Received result for unknown job: #{job_id}")
        {:noreply, state}

      job ->
        # Update job with worker result
        updated_results = Map.put(job.results, worker_id, result)
        updated_job = %{job | results: updated_results}

        # Check if job is complete
        final_job =
          if job_complete?(updated_job) do
            %{updated_job | status: :completed, completed_at: System.system_time(:second)}
          else
            updated_job
          end

        new_jobs = Map.put(state.active_jobs, job_id, final_job)
        new_state = %{state | active_jobs: new_jobs}

        Logger.info("Received result from worker #{worker_id} for job #{job_id}")

        {:noreply, new_state}
    end
  end

  def handle_cast({:worker_heartbeat, worker_id, status}, state) do
    case Map.get(state.workers, worker_id) do
      nil ->
        Logger.warn("Heartbeat from unregistered worker: #{worker_id}")
        {:noreply, state}

      worker ->
        updated_worker = %{worker | status: status, last_heartbeat: System.system_time(:second)}

        # Update failure detector with heartbeat
        FailureDetector.heartbeat(worker_id, %{status: status})

        new_workers = Map.put(state.workers, worker_id, updated_worker)
        new_state = %{state | workers: new_workers}

        {:noreply, new_state}
    end
  end

  # Private Functions

  defp start_communication_server(opts) do
    port = opts[:port] || 4040

    # Start the HTTP server using Bandit
    case Bandit.start_link(plug: Pigeon.Communication.Router, port: port) do
      {:ok, _pid} ->
        Logger.info("Communication server started on port #{port}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start communication server: #{reason}")
        {:error, reason}
    end
  end

  defp assign_pending_jobs(state) do
    available_workers = get_available_workers(state.workers)

    if length(available_workers) > 0 and not :queue.is_empty(state.job_queue) do
      case :queue.out(state.job_queue) do
        {{:value, job}, remaining_queue} ->
          case assign_job_to_workers(job, available_workers) do
            {:ok, assigned_workers} ->
              updated_job = %{
                job
                | status: :running,
                  assigned_workers: assigned_workers,
                  started_at: System.system_time(:second)
              }

              new_jobs = Map.put(state.active_jobs, job.id, updated_job)
              new_state = %{state | active_jobs: new_jobs, job_queue: remaining_queue}

              # Continue assigning more jobs if possible
              assign_pending_jobs(new_state)

            {:error, _reason} ->
              # Keep job in queue
              state
          end

        {:empty} ->
          state
      end
    else
      state
    end
  end

  defp get_available_workers(workers) do
    workers
    |> Map.values()
    |> Enum.filter(&(&1.status == :idle))
  end

  defp assign_job_to_workers(job, available_workers) do
    # For distributed processing, we might want multiple workers
    workers_needed = min(length(available_workers), 3)
    selected_workers = Enum.take(available_workers, workers_needed)

    # Send job to each selected worker
    assignments =
      Enum.map(selected_workers, fn worker ->
        task_data = %{
          job_id: job.id,
          task_type: job.type,
          data: job.data,
          worker_id: worker.worker_id
        }

        case send_worker_message_with_resilience(
               worker.endpoint,
               :task_assignment,
               task_data,
               worker.worker_id
             ) do
          :ok ->
            %{worker_id: worker.worker_id, status: :assigned}

          {:error, reason} ->
            Logger.warn("Failed to assign job to worker #{worker.worker_id}: #{reason}")
            %{worker_id: worker.worker_id, status: :failed}
        end
      end)

    successful_assignments = Enum.filter(assignments, &(&1.status == :assigned))

    if length(successful_assignments) > 0 do
      {:ok, successful_assignments}
    else
      {:error, "No workers could accept the job"}
    end
  end

  defp distribute_work_items(work_items, state) do
    available_workers = get_available_workers(state.workers)

    if length(available_workers) == 0 do
      {:error, "No available workers"}
    else
      # Round-robin distribution
      assignments =
        work_items
        |> Enum.with_index()
        |> Enum.map(fn {work_item, index} ->
          worker = Enum.at(available_workers, rem(index, length(available_workers)))
          {work_item, worker}
        end)

      # Send work to each assigned worker
      results =
        Enum.map(assignments, fn {work_item, worker} ->
          case send_worker_message_with_resilience(
                 worker.endpoint,
                 :work_item,
                 work_item,
                 worker.worker_id
               ) do
            :ok ->
              %{work_item_id: work_item.id, worker_id: worker.worker_id, status: :sent}

            {:error, reason} ->
              %{
                work_item_id: work_item.id,
                worker_id: worker.worker_id,
                status: :failed,
                reason: reason
              }
          end
        end)

      {:ok, results}
    end
  end

  defp send_worker_message(endpoint, message_type, data) do
    url = "#{endpoint}/api/message"

    payload = %{
      type: message_type,
      data: data,
      timestamp: System.system_time(:second)
    }

    case Req.post(url, json: payload, receive_timeout: 30_000) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_worker_message_with_resilience(endpoint, message_type, data, worker_id) do
    circuit_breaker_name = "worker_#{worker_id}"
    start_time = System.monotonic_time(:millisecond)

    result =
      CircuitBreaker.call(circuit_breaker_name, fn ->
        Retry.with_http_retry(
          fn ->
            send_worker_message(endpoint, message_type, data)
          end,
          max_retries: 3,
          base_delay: 1000
        )
      end)

    execution_time = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} ->
        FailureDetector.record_success(worker_id, message_type, execution_time)
        :ok

      {:error, reason} ->
        FailureDetector.record_failure(worker_id, message_type, reason, execution_time)
        {:error, reason}
    end
  end

  defp job_complete?(job) do
    # Job is complete when all assigned workers have submitted results
    assigned_count = length(job.assigned_workers)
    result_count = map_size(job.results)

    assigned_count > 0 and result_count >= assigned_count
  end

  defp build_job_status(job) do
    %{
      id: job.id,
      type: job.type,
      status: job.status,
      submitted_at: job.submitted_at,
      started_at: Map.get(job, :started_at),
      completed_at: Map.get(job, :completed_at),
      assigned_workers: length(job.assigned_workers),
      results_received: map_size(job.results),
      results: job.results
    }
  end

  defp generate_job_id do
    "job-" <>
      (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  # Worker failure handling
  defp handle_worker_failure(worker_id, failure_info) do
    Logger.warn("Worker #{worker_id} failed, reassigning jobs")
    GenServer.cast(__MODULE__, {:worker_failed, worker_id, failure_info})
  end

  def handle_cast({:worker_failed, worker_id, failure_info}, state) do
    # Find all jobs assigned to this worker
    jobs_to_reassign =
      state.active_jobs
      |> Enum.filter(fn {_job_id, job} ->
        job.status == :running and
          Enum.any?(job.assigned_workers, &(&1.worker_id == worker_id))
      end)
      |> Enum.map(fn {job_id, job} -> {job_id, job} end)

    Logger.info("Reassigning #{length(jobs_to_reassign)} jobs from failed worker #{worker_id}")

    # Mark worker as failed and remove from active workers
    updated_workers = Map.delete(state.workers, worker_id)

    # Remove circuit breaker for failed worker
    updated_circuit_breakers = Map.delete(state.circuit_breakers, worker_id)

    # Unregister from failure detector
    FailureDetector.unregister_worker(worker_id)

    # Process each job for reassignment
    {updated_jobs, updated_queue} =
      reassign_jobs(jobs_to_reassign, state.active_jobs, state.job_queue, worker_id)

    new_state = %{
      state
      | workers: updated_workers,
        circuit_breakers: updated_circuit_breakers,
        active_jobs: updated_jobs,
        job_queue: updated_queue
    }

    # Try to assign pending jobs to remaining workers
    final_state = assign_pending_jobs(new_state)

    {:noreply, final_state}
  end

  defp reassign_jobs(jobs_to_reassign, active_jobs, job_queue, failed_worker_id) do
    Enum.reduce(jobs_to_reassign, {active_jobs, job_queue}, fn {job_id, job},
                                                               {acc_jobs, acc_queue} ->
      # Remove failed worker from assigned workers
      remaining_workers = Enum.reject(job.assigned_workers, &(&1.worker_id == failed_worker_id))

      # Remove any results from the failed worker
      updated_results = Map.delete(job.results, failed_worker_id)

      cond do
        # If there are still workers assigned to this job, keep it running
        length(remaining_workers) > 0 ->
          updated_job = %{
            job
            | assigned_workers: remaining_workers,
              results: updated_results,
              reassigned_at: System.system_time(:second)
          }

          {Map.put(acc_jobs, job_id, updated_job), acc_queue}

        # If no workers left, put job back in queue for reassignment
        true ->
          updated_job = %{
            job
            | status: :pending,
              assigned_workers: [],
              results: updated_results,
              reassigned_at: System.system_time(:second),
              failure_count: Map.get(job, :failure_count, 0) + 1
          }

          # Add back to queue unless it has failed too many times
          if updated_job.failure_count < 3 do
            Logger.info(
              "Job #{job_id} returned to queue for reassignment (attempt #{updated_job.failure_count})"
            )

            new_queue = :queue.in(updated_job, acc_queue)
            {Map.put(acc_jobs, job_id, updated_job), new_queue}
          else
            Logger.error("Job #{job_id} failed too many times, marking as failed")
            failed_job = %{updated_job | status: :failed, failed_at: System.system_time(:second)}
            {Map.put(acc_jobs, job_id, failed_job), acc_queue}
          end
      end
    end)
  end
end
