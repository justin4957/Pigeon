defmodule Pigeon.Resilience.FailureDetector do
  @moduledoc """
  Failure detection and health monitoring for worker nodes.

  Monitors worker health through:
  - Heartbeat monitoring
  - Response time tracking
  - Error rate analysis
  - Health check validation
  """

  use GenServer
  require Logger

  @default_heartbeat_interval 30_000
  @default_failure_threshold 3
  @default_response_timeout 10_000

  defstruct [
    :workers,
    :heartbeat_interval,
    :failure_threshold,
    :response_timeout,
    :failure_callbacks
  ]

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register_worker(worker_id, worker_info) do
    GenServer.call(__MODULE__, {:register_worker, worker_id, worker_info})
  end

  def unregister_worker(worker_id) do
    GenServer.call(__MODULE__, {:unregister_worker, worker_id})
  end

  def heartbeat(worker_id, health_data \\ %{}) do
    GenServer.cast(__MODULE__, {:heartbeat, worker_id, health_data})
  end

  def record_success(worker_id, operation_type, response_time) do
    GenServer.cast(__MODULE__, {:record_success, worker_id, operation_type, response_time})
  end

  def record_failure(worker_id, operation_type, error_reason, response_time \\ nil) do
    GenServer.cast(
      __MODULE__,
      {:record_failure, worker_id, operation_type, error_reason, response_time}
    )
  end

  def get_worker_health(worker_id) do
    GenServer.call(__MODULE__, {:get_worker_health, worker_id})
  end

  def get_all_workers_health do
    GenServer.call(__MODULE__, :get_all_workers_health)
  end

  def get_healthy_workers do
    GenServer.call(__MODULE__, :get_healthy_workers)
  end

  def add_failure_callback(callback_fun) when is_function(callback_fun, 2) do
    GenServer.call(__MODULE__, {:add_failure_callback, callback_fun})
  end

  ## GenServer Implementation

  def init(opts) do
    state = %__MODULE__{
      workers: %{},
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, @default_heartbeat_interval),
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      response_timeout: Keyword.get(opts, :response_timeout, @default_response_timeout),
      failure_callbacks: []
    }

    # Schedule periodic health checks
    schedule_health_check()

    Logger.info("Failure detector started with heartbeat interval: #{state.heartbeat_interval}ms")
    {:ok, state}
  end

  def handle_call({:register_worker, worker_id, worker_info}, _from, state) do
    worker_health = %{
      worker_id: worker_id,
      info: worker_info,
      status: :healthy,
      last_heartbeat: System.system_time(:millisecond),
      last_seen: System.system_time(:millisecond),
      consecutive_failures: 0,
      total_failures: 0,
      total_successes: 0,
      avg_response_time: 0,
      recent_response_times: :queue.new(),
      error_history: []
    }

    new_workers = Map.put(state.workers, worker_id, worker_health)
    new_state = %{state | workers: new_workers}

    Logger.info("Worker #{worker_id} registered for health monitoring")
    {:reply, :ok, new_state}
  end

  def handle_call({:unregister_worker, worker_id}, _from, state) do
    new_workers = Map.delete(state.workers, worker_id)
    new_state = %{state | workers: new_workers}

    Logger.info("Worker #{worker_id} unregistered from health monitoring")
    {:reply, :ok, new_state}
  end

  def handle_call({:get_worker_health, worker_id}, _from, state) do
    case Map.get(state.workers, worker_id) do
      nil -> {:reply, {:error, :not_found}, state}
      worker_health -> {:reply, {:ok, build_health_summary(worker_health)}, state}
    end
  end

  def handle_call(:get_all_workers_health, _from, state) do
    health_summaries =
      state.workers
      |> Enum.map(fn {worker_id, health} -> {worker_id, build_health_summary(health)} end)
      |> Map.new()

    {:reply, {:ok, health_summaries}, state}
  end

  def handle_call(:get_healthy_workers, _from, state) do
    healthy_workers =
      state.workers
      |> Enum.filter(fn {_worker_id, health} -> health.status == :healthy end)
      |> Enum.map(fn {worker_id, health} -> {worker_id, health.info} end)

    {:reply, {:ok, healthy_workers}, state}
  end

  def handle_call({:add_failure_callback, callback_fun}, _from, state) do
    new_callbacks = [callback_fun | state.failure_callbacks]
    new_state = %{state | failure_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  def handle_cast({:heartbeat, worker_id, health_data}, state) do
    case Map.get(state.workers, worker_id) do
      nil ->
        Logger.warn("Heartbeat received from unregistered worker: #{worker_id}")
        {:noreply, state}

      worker_health ->
        current_time = System.system_time(:millisecond)

        updated_health = %{
          worker_health
          | last_heartbeat: current_time,
            last_seen: current_time,
            status: determine_status_from_heartbeat(health_data, worker_health)
        }

        new_workers = Map.put(state.workers, worker_id, updated_health)
        new_state = %{state | workers: new_workers}

        {:noreply, new_state}
    end
  end

  def handle_cast({:record_success, worker_id, operation_type, response_time}, state) do
    case Map.get(state.workers, worker_id) do
      nil ->
        Logger.warn("Success recorded for unregistered worker: #{worker_id}")
        {:noreply, state}

      worker_health ->
        updated_health = update_success_metrics(worker_health, operation_type, response_time)

        # If worker was unhealthy and we got a success, potentially mark as recovering
        final_health =
          if worker_health.status != :healthy do
            %{updated_health | consecutive_failures: 0, status: :recovering}
          else
            updated_health
          end

        new_workers = Map.put(state.workers, worker_id, final_health)
        new_state = %{state | workers: new_workers}

        {:noreply, new_state}
    end
  end

  def handle_cast({:record_failure, worker_id, operation_type, error_reason, response_time}, state) do
    case Map.get(state.workers, worker_id) do
      nil ->
        Logger.warn("Failure recorded for unregistered worker: #{worker_id}")
        {:noreply, state}

      worker_health ->
        updated_health =
          update_failure_metrics(worker_health, operation_type, error_reason, response_time)

        # Check if worker should be marked as unhealthy
        new_status =
          if updated_health.consecutive_failures >= state.failure_threshold do
            :unhealthy
          else
            worker_health.status
          end

        final_health = %{updated_health | status: new_status}

        # Trigger failure callbacks if worker became unhealthy
        if worker_health.status != :unhealthy and new_status == :unhealthy do
          trigger_failure_callbacks(worker_id, final_health, state.failure_callbacks)
        end

        new_workers = Map.put(state.workers, worker_id, final_health)
        new_state = %{state | workers: new_workers}

        {:noreply, new_state}
    end
  end

  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  ## Private Functions

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @default_heartbeat_interval)
  end

  defp perform_health_check(state) do
    current_time = System.system_time(:millisecond)
    # Allow 2x interval for tolerance
    heartbeat_timeout = state.heartbeat_interval * 2

    updated_workers =
      state.workers
      |> Enum.map(fn {worker_id, health} ->
        time_since_heartbeat = current_time - health.last_heartbeat

        new_status =
          cond do
            time_since_heartbeat > heartbeat_timeout ->
              if health.status != :unhealthy do
                Logger.warn("Worker #{worker_id} missed heartbeat, marking as unhealthy")
                trigger_failure_callbacks(worker_id, health, state.failure_callbacks)
              end

              :unhealthy

            health.status == :recovering and health.consecutive_failures == 0 ->
              Logger.info("Worker #{worker_id} recovered, marking as healthy")
              :healthy

            true ->
              health.status
          end

        {worker_id, %{health | status: new_status}}
      end)
      |> Map.new()

    %{state | workers: updated_workers}
  end

  defp determine_status_from_heartbeat(health_data, worker_health) do
    # Check if heartbeat contains any critical health indicators
    case health_data do
      %{status: :overloaded} ->
        :degraded

      %{status: :error} ->
        :unhealthy

      %{cpu_usage: cpu} when cpu > 90 ->
        :degraded

      %{memory_usage: mem} when mem > 90 ->
        :degraded

      _ ->
        # If recovering and no issues, mark as healthy
        if worker_health.status == :recovering and worker_health.consecutive_failures == 0 do
          :healthy
        else
          worker_health.status
        end
    end
  end

  defp update_success_metrics(health, operation_type, response_time) do
    # Update response time tracking
    response_times = :queue.in(response_time, health.recent_response_times)
    # Keep only last 10 response times
    trimmed_times =
      if :queue.len(response_times) > 10 do
        {_oldest, newer_times} = :queue.out(response_times)
        newer_times
      else
        response_times
      end

    avg_response_time = calculate_average_response_time(trimmed_times)

    %{
      health
      | total_successes: health.total_successes + 1,
        consecutive_failures: 0,
        avg_response_time: avg_response_time,
        recent_response_times: trimmed_times,
        last_seen: System.system_time(:millisecond)
    }
  end

  defp update_failure_metrics(health, operation_type, error_reason, response_time) do
    current_time = System.system_time(:millisecond)

    error_entry = %{
      timestamp: current_time,
      operation_type: operation_type,
      error_reason: error_reason,
      response_time: response_time
    }

    # Keep only last 20 errors
    updated_history = [error_entry | health.error_history] |> Enum.take(20)

    %{
      health
      | total_failures: health.total_failures + 1,
        consecutive_failures: health.consecutive_failures + 1,
        error_history: updated_history,
        last_seen: current_time
    }
  end

  defp calculate_average_response_time(response_times_queue) do
    times = :queue.to_list(response_times_queue)

    if length(times) > 0 do
      Enum.sum(times) / length(times)
    else
      0
    end
  end

  defp build_health_summary(health) do
    %{
      worker_id: health.worker_id,
      status: health.status,
      last_heartbeat: health.last_heartbeat,
      last_seen: health.last_seen,
      consecutive_failures: health.consecutive_failures,
      total_failures: health.total_failures,
      total_successes: health.total_successes,
      success_rate: calculate_success_rate(health),
      avg_response_time: round(health.avg_response_time),
      recent_errors: Enum.take(health.error_history, 5)
    }
  end

  defp calculate_success_rate(health) do
    total_operations = health.total_successes + health.total_failures

    if total_operations > 0 do
      health.total_successes / total_operations
    else
      1.0
    end
  end

  defp trigger_failure_callbacks(worker_id, health, callbacks) do
    failure_info = %{
      worker_id: worker_id,
      health_summary: build_health_summary(health),
      failure_time: System.system_time(:millisecond)
    }

    Enum.each(callbacks, fn callback ->
      try do
        callback.(worker_id, failure_info)
      rescue
        error ->
          Logger.error("Failure callback crashed: #{inspect(error)}")
      end
    end)
  end
end
