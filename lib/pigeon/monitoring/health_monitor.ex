defmodule Pigeon.Monitoring.HealthMonitor do
  @moduledoc """
  Health monitoring system for Pigeon cluster components.

  Monitors the health of worker nodes, communication hub, and overall
  cluster status. Provides health checks and alerts for system issues.
  """

  use GenServer
  require Logger

  defstruct [
    :cluster_health,
    :worker_health_checks,
    :last_check_time,
    :check_interval
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  def check_worker_health(worker_id) do
    GenServer.call(__MODULE__, {:check_worker_health, worker_id})
  end

  def report_worker_issue(worker_id, issue) do
    GenServer.cast(__MODULE__, {:report_worker_issue, worker_id, issue})
  end

  # GenServer Implementation

  def init(opts) do
    check_interval = opts[:check_interval] || 30_000  # 30 seconds

    state = %__MODULE__{
      cluster_health: :healthy,
      worker_health_checks: %{},
      last_check_time: System.system_time(:second),
      check_interval: check_interval
    }

    # Schedule periodic health checks
    schedule_health_check(check_interval)

    Logger.info("Health Monitor started with #{check_interval}ms check interval")
    {:ok, state}
  end

  def handle_call(:get_health_status, _from, state) do
    health_status = %{
      cluster_health: state.cluster_health,
      last_check: state.last_check_time,
      worker_statuses: state.worker_health_checks,
      healthy_workers: count_healthy_workers(state.worker_health_checks),
      total_workers: map_size(state.worker_health_checks)
    }

    {:reply, {:ok, health_status}, state}
  end

  def handle_call({:check_worker_health, worker_id}, _from, state) do
    case perform_worker_health_check(worker_id) do
      {:ok, health_data} ->
        new_checks = Map.put(state.worker_health_checks, worker_id, %{
          status: :healthy,
          last_check: System.system_time(:second),
          data: health_data
        })

        new_state = %{state | worker_health_checks: new_checks}
        {:reply, {:ok, :healthy}, new_state}

      {:error, reason} ->
        new_checks = Map.put(state.worker_health_checks, worker_id, %{
          status: :unhealthy,
          last_check: System.system_time(:second),
          error: reason
        })

        new_state = %{state | worker_health_checks: new_checks}
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_cast({:report_worker_issue, worker_id, issue}, state) do
    Logger.warning("Worker health issue reported for #{worker_id}: #{inspect(issue)}")

    new_checks = Map.put(state.worker_health_checks, worker_id, %{
      status: :unhealthy,
      last_check: System.system_time(:second),
      issue: issue
    })

    new_state = %{state | worker_health_checks: new_checks}
    {:noreply, new_state}
  end

  def handle_info(:perform_health_check, state) do
    Logger.debug("Performing scheduled health check")

    new_state = perform_cluster_health_check(state)

    # Schedule next check
    schedule_health_check(state.check_interval)

    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_health_check(interval) do
    Process.send_after(self(), :perform_health_check, interval)
  end

  defp perform_cluster_health_check(state) do
    # Check overall cluster health
    cluster_status = case Pigeon.Cluster.Manager.get_status() do
      {:ok, status} ->
        if status.active_workers > 0 do
          :healthy
        else
          :degraded
        end

      {:error, _reason} ->
        :unhealthy
    end

    %{state |
      cluster_health: cluster_status,
      last_check_time: System.system_time(:second)
    }
  end

  defp perform_worker_health_check(worker_id) do
    # In a real implementation, this would ping the worker
    # For now, return a simple health check result
    try do
      # Simulate a health check
      health_data = %{
        cpu_usage: :rand.uniform(100),
        memory_usage: :rand.uniform(100),
        active_jobs: :rand.uniform(5),
        last_heartbeat: System.system_time(:second)
      }

      {:ok, health_data}
    rescue
      error ->
        {:error, "Health check failed: #{inspect(error)}"}
    end
  end

  defp count_healthy_workers(worker_checks) do
    worker_checks
    |> Map.values()
    |> Enum.count(fn check -> check.status == :healthy end)
  end
end