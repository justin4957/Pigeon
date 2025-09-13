defmodule Pigeon.Communication.Hub do
  @moduledoc """
  Centralized communication hub for coordinating with worker nodes.
  Implements hub-and-spoke pattern for distributed work processing.
  """

  use GenServer
  require Logger

  alias Pigeon.Communication.Protocol
  alias Pigeon.Jobs.JobManager

  defstruct [
    :control_node,
    :workers,
    :active_jobs,
    :job_queue,
    :message_handlers
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
      message_handlers: %{}
    }

    # Start HTTP server for worker communication
    start_communication_server(opts)

    Logger.info("Pigeon Communication Hub started on #{control_node}")
    {:ok, state}
  end

  def handle_call({:register_worker, worker_info}, _from, state) do
    worker_id = worker_info.worker_id
    updated_worker = Map.merge(worker_info, %{
      registered_at: System.system_time(:second),
      last_heartbeat: System.system_time(:second),
      status: :idle
    })

    new_workers = Map.put(state.workers, worker_id, updated_worker)
    new_state = %{state | workers: new_workers}

    Logger.info("Worker registered: #{worker_id} at #{worker_info.endpoint}")

    # Send welcome message to worker
    send_worker_message(worker_info.endpoint, :welcome, %{
      control_node: state.control_node,
      worker_id: worker_id,
      assigned_at: System.system_time(:second)
    })

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
        final_job = if job_complete?(updated_job) do
          %{updated_job |
            status: :completed,
            completed_at: System.system_time(:second)
          }
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
        updated_worker = %{worker |
          status: status,
          last_heartbeat: System.system_time(:second)
        }

        new_workers = Map.put(state.workers, worker_id, updated_worker)
        new_state = %{state | workers: new_workers}

        {:noreply, new_state}
    end
  end

  # Private Functions

  defp start_communication_server(opts) do
    port = opts[:port] || 4040

    cowboy_opts = %{
      port: port,
      dispatch: [
        {:_, [
          {"/api/worker/register", Pigeon.Communication.Handlers.RegisterHandler, []},
          {"/api/worker/heartbeat", Pigeon.Communication.Handlers.HeartbeatHandler, []},
          {"/api/worker/result", Pigeon.Communication.Handlers.ResultHandler, []},
          {"/api/jobs/:job_id", Pigeon.Communication.Handlers.JobHandler, []},
          {"/health", Pigeon.Communication.Handlers.HealthHandler, []}
        ]}
      ]
    }

    case :cowboy.start_clear(:pigeon_http, cowboy_opts) do
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
              updated_job = %{job |
                status: :running,
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
    assignments = Enum.map(selected_workers, fn worker ->
      task_data = %{
        job_id: job.id,
        task_type: job.type,
        data: job.data,
        worker_id: worker.worker_id
      }

      case send_worker_message(worker.endpoint, :task_assignment, task_data) do
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
      assignments = work_items
      |> Enum.with_index()
      |> Enum.map(fn {work_item, index} ->
        worker = Enum.at(available_workers, rem(index, length(available_workers)))
        {work_item, worker}
      end)

      # Send work to each assigned worker
      results = Enum.map(assignments, fn {work_item, worker} ->
        case send_worker_message(worker.endpoint, :work_item, work_item) do
          :ok ->
            %{work_item_id: work_item.id, worker_id: worker.worker_id, status: :sent}

          {:error, reason} ->
            %{work_item_id: work_item.id, worker_id: worker.worker_id, status: :failed, reason: reason}
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
        {:error, "HTTP #{status}"}

      {:error, reason} ->
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
end