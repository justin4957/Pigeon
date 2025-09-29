defmodule Pigeon.Jobs.JobManager do
  @moduledoc """
  GenServer for managing and tracking distributed jobs in Pigeon.

  Handles job lifecycle, status tracking, and result aggregation
  for work processing across the cluster.
  """

  use GenServer
  require Logger

  defstruct [
    :jobs,
    :job_counter,
    :job_results
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_job(job_data) do
    GenServer.call(__MODULE__, {:create_job, job_data})
  end

  def get_job(job_id) do
    GenServer.call(__MODULE__, {:get_job, job_id})
  end

  def update_job_status(job_id, status) do
    GenServer.cast(__MODULE__, {:update_job_status, job_id, status})
  end

  def add_job_result(job_id, worker_id, result) do
    GenServer.cast(__MODULE__, {:add_job_result, job_id, worker_id, result})
  end

  def list_jobs do
    GenServer.call(__MODULE__, :list_jobs)
  end

  # GenServer Implementation

  def init(_opts) do
    state = %__MODULE__{
      jobs: %{},
      job_counter: 0,
      job_results: %{}
    }

    {:ok, state}
  end

  def handle_call({:create_job, job_data}, _from, state) do
    job_id = generate_job_id(state.job_counter)

    job = %{
      id: job_id,
      data: job_data,
      status: :pending,
      created_at: System.system_time(:second),
      assigned_workers: [],
      completion_count: 0
    }

    new_jobs = Map.put(state.jobs, job_id, job)
    new_state = %{state | jobs: new_jobs, job_counter: state.job_counter + 1}

    {:reply, {:ok, job_id}, new_state}
  end

  def handle_call({:get_job, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      job ->
        {:reply, {:ok, job}, state}
    end
  end

  def handle_call(:list_jobs, _from, state) do
    jobs = Map.values(state.jobs)
    {:reply, {:ok, jobs}, state}
  end

  def handle_cast({:update_job_status, job_id, status}, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        Logger.warning("Attempt to update status for unknown job: #{job_id}")
        {:noreply, state}

      job ->
        updated_job = %{job | status: status}
        new_jobs = Map.put(state.jobs, job_id, updated_job)
        new_state = %{state | jobs: new_jobs}

        {:noreply, new_state}
    end
  end

  def handle_cast({:add_job_result, job_id, worker_id, result}, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        Logger.warning("Attempt to add result for unknown job: #{job_id}")
        {:noreply, state}

      job ->
        # Add result to job results
        job_results = Map.get(state.job_results, job_id, %{})
        updated_results = Map.put(job_results, worker_id, result)
        new_job_results = Map.put(state.job_results, job_id, updated_results)

        # Update job completion count
        updated_job = %{
          job
          | completion_count: job.completion_count + 1,
            status:
              if(job.completion_count + 1 >= length(job.assigned_workers),
                do: :completed,
                else: :running
              )
        }

        new_jobs = Map.put(state.jobs, job_id, updated_job)
        new_state = %{state | jobs: new_jobs, job_results: new_job_results}

        {:noreply, new_state}
    end
  end

  # Private Functions

  defp generate_job_id(counter) do
    "job_#{counter}_#{:erlang.system_time(:millisecond)}"
  end
end
