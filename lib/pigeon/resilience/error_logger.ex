defmodule Pigeon.Resilience.ErrorLogger do
  @moduledoc """
  Comprehensive error logging and diagnostics for the Pigeon system.

  Provides structured error logging with:
  - Detailed error context and stack traces
  - Error categorization and correlation
  - Performance impact tracking
  - Error rate monitoring
  - Diagnostic data collection
  """

  use GenServer
  require Logger

  @error_retention_days 7
  @max_errors_per_category 1000

  defstruct [
    :errors,
    :error_stats,
    :correlation_map,
    :performance_impact
  ]

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def log_error(category, error_data, context \\ %{}) do
    GenServer.cast(__MODULE__, {:log_error, category, error_data, context})
  end

  def log_infrastructure_error(operation, error, context \\ %{}) do
    enhanced_context =
      Map.merge(context, %{
        operation: operation,
        node: node(),
        timestamp: System.system_time(:millisecond)
      })

    log_error(:infrastructure, error, enhanced_context)
  end

  def log_worker_error(worker_id, error, context \\ %{}) do
    enhanced_context =
      Map.merge(context, %{
        worker_id: worker_id,
        timestamp: System.system_time(:millisecond)
      })

    log_error(:worker, error, enhanced_context)
  end

  def log_job_error(job_id, error, context \\ %{}) do
    enhanced_context =
      Map.merge(context, %{
        job_id: job_id,
        timestamp: System.system_time(:millisecond)
      })

    log_error(:job, error, enhanced_context)
  end

  def log_network_error(endpoint, error, context \\ %{}) do
    enhanced_context =
      Map.merge(context, %{
        endpoint: endpoint,
        timestamp: System.system_time(:millisecond)
      })

    log_error(:network, error, enhanced_context)
  end

  def get_error_summary(time_window_minutes \\ 60) do
    GenServer.call(__MODULE__, {:get_error_summary, time_window_minutes})
  end

  def get_errors_by_category(category, limit \\ 50) do
    GenServer.call(__MODULE__, {:get_errors_by_category, category, limit})
  end

  def get_correlated_errors(correlation_id) do
    GenServer.call(__MODULE__, {:get_correlated_errors, correlation_id})
  end

  def get_error_trends(hours_back \\ 24) do
    GenServer.call(__MODULE__, {:get_error_trends, hours_back})
  end

  ## GenServer Implementation

  def init(_opts) do
    state = %__MODULE__{
      errors: %{},
      error_stats: %{},
      correlation_map: %{},
      performance_impact: %{}
    }

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("Error logger started")
    {:ok, state}
  end

  def handle_cast({:log_error, category, error_data, context}, state) do
    timestamp = System.system_time(:millisecond)
    error_id = generate_error_id()

    # Enhance error data with system information
    enhanced_error = %{
      id: error_id,
      category: category,
      error: error_data,
      context: context,
      timestamp: timestamp,
      severity: determine_severity(category, error_data),
      correlation_id: Map.get(context, :correlation_id),
      stack_trace: get_stack_trace(),
      system_info: get_system_info()
    }

    # Store error
    category_errors = Map.get(state.errors, category, [])

    updated_category_errors =
      [enhanced_error | category_errors] |> Enum.take(@max_errors_per_category)

    new_errors = Map.put(state.errors, category, updated_category_errors)

    # Update statistics
    new_stats = update_error_stats(state.error_stats, category, enhanced_error)

    # Update correlation map if correlation_id exists
    new_correlation_map =
      if enhanced_error.correlation_id do
        existing_errors = Map.get(state.correlation_map, enhanced_error.correlation_id, [])
        Map.put(state.correlation_map, enhanced_error.correlation_id, [error_id | existing_errors])
      else
        state.correlation_map
      end

    # Update performance impact tracking
    new_performance_impact = update_performance_impact(state.performance_impact, enhanced_error)

    # Log to system logger with appropriate level
    log_to_system(enhanced_error)

    # Send alerts for critical errors
    if enhanced_error.severity >= :critical do
      send_alert(enhanced_error)
    end

    new_state = %{
      state
      | errors: new_errors,
        error_stats: new_stats,
        correlation_map: new_correlation_map,
        performance_impact: new_performance_impact
    }

    {:noreply, new_state}
  end

  def handle_call({:get_error_summary, time_window_minutes}, _from, state) do
    cutoff_time = System.system_time(:millisecond) - time_window_minutes * 60 * 1000

    summary =
      state.errors
      |> Enum.reduce(%{}, fn {category, errors}, acc ->
        recent_errors = Enum.filter(errors, &(&1.timestamp >= cutoff_time))

        category_summary = %{
          total_count: length(recent_errors),
          error_rate: calculate_error_rate(recent_errors, time_window_minutes),
          severity_breakdown: group_by_severity(recent_errors),
          top_errors: get_top_errors(recent_errors, 5)
        }

        Map.put(acc, category, category_summary)
      end)

    {:reply, {:ok, summary}, state}
  end

  def handle_call({:get_errors_by_category, category, limit}, _from, state) do
    errors =
      Map.get(state.errors, category, [])
      |> Enum.take(limit)

    {:reply, {:ok, errors}, state}
  end

  def handle_call({:get_correlated_errors, correlation_id}, _from, state) do
    error_ids = Map.get(state.correlation_map, correlation_id, [])

    correlated_errors =
      state.errors
      |> Enum.flat_map(fn {_category, errors} -> errors end)
      |> Enum.filter(&(&1.id in error_ids))
      |> Enum.sort_by(& &1.timestamp)

    {:reply, {:ok, correlated_errors}, state}
  end

  def handle_call({:get_error_trends, hours_back}, _from, state) do
    cutoff_time = System.system_time(:millisecond) - hours_back * 60 * 60 * 1000
    hour_buckets = create_hour_buckets(hours_back)

    trends =
      state.errors
      |> Enum.map(fn {category, errors} ->
        recent_errors = Enum.filter(errors, &(&1.timestamp >= cutoff_time))
        hourly_counts = bucket_errors_by_hour(recent_errors, hour_buckets)

        {category,
         %{
           hourly_counts: hourly_counts,
           total_count: length(recent_errors),
           trend_direction: calculate_trend_direction(hourly_counts)
         }}
      end)
      |> Map.new()

    {:reply, {:ok, trends}, state}
  end

  def handle_info(:cleanup, state) do
    new_state = cleanup_old_errors(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  ## Private Functions

  defp generate_error_id do
    "err-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp determine_severity(category, error_data) do
    case {category, error_data} do
      {:infrastructure, {:aws_error, %{code: "InternalError"}}} -> :critical
      {:infrastructure, {:aws_error, %{code: "ServiceUnavailable"}}} -> :high
      {:worker, {:worker_crashed, _}} -> :high
      {:worker, {:worker_timeout, _}} -> :medium
      {:network, {:http_error, status}} when status >= 500 -> :high
      {:network, {:http_error, status}} when status >= 400 -> :medium
      {:job, {:job_timeout, _}} -> :medium
      {:job, {:validation_failed, _}} -> :low
      _ -> :medium
    end
  end

  defp get_stack_trace do
    try do
      throw(:get_stacktrace)
    catch
      :get_stacktrace ->
        __STACKTRACE__
        |> Enum.take(10)
        |> Enum.map(&Exception.format_stacktrace_entry/1)
    end
  end

  defp get_system_info do
    %{
      node: node(),
      memory_usage: get_memory_usage(),
      process_count: length(Process.list()),
      load_average: get_load_average()
    }
  end

  defp get_memory_usage do
    :erlang.memory()
    |> Enum.into(%{})
    |> Map.take([:total, :processes, :system, :atom, :binary, :ets])
  end

  defp get_load_average do
    case :cpu_sup.avg1() do
      # Convert to decimal
      {:ok, load} -> load / 256
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp update_error_stats(stats, category, error) do
    category_stats =
      Map.get(stats, category, %{
        total_count: 0,
        by_severity: %{},
        hourly_counts: %{},
        last_error_time: nil
      })

    current_hour = div(error.timestamp, 3_600_000)
    hourly_count = Map.get(category_stats.hourly_counts, current_hour, 0)

    new_category_stats = %{
      category_stats
      | total_count: category_stats.total_count + 1,
        by_severity: Map.update(category_stats.by_severity, error.severity, 1, &(&1 + 1)),
        hourly_counts: Map.put(category_stats.hourly_counts, current_hour, hourly_count + 1),
        last_error_time: error.timestamp
    }

    Map.put(stats, category, new_category_stats)
  end

  defp update_performance_impact(impact_map, error) do
    case error.context do
      %{response_time: response_time} when is_number(response_time) ->
        category_impact =
          Map.get(impact_map, error.category, %{
            total_response_time: 0,
            error_count: 0,
            avg_impact: 0
          })

        new_total = category_impact.total_response_time + response_time
        new_count = category_impact.error_count + 1
        new_avg = new_total / new_count

        new_category_impact = %{
          category_impact
          | total_response_time: new_total,
            error_count: new_count,
            avg_impact: new_avg
        }

        Map.put(impact_map, error.category, new_category_impact)

      _ ->
        impact_map
    end
  end

  defp log_to_system(error) do
    log_level =
      case error.severity do
        :critical -> :error
        :high -> :error
        :medium -> :warn
        :low -> :info
      end

    message = format_error_message(error)
    Logger.log(log_level, message, error: error)
  end

  defp format_error_message(error) do
    "#{error.category} error: #{inspect(error.error)} " <>
      "| Context: #{inspect(error.context)} " <>
      "| Severity: #{error.severity}"
  end

  defp send_alert(error) do
    # In a real implementation, this would send alerts via email, Slack, PagerDuty, etc.
    Logger.error("CRITICAL ERROR ALERT: #{format_error_message(error)}")
  end

  defp calculate_error_rate(errors, time_window_minutes) do
    if length(errors) > 0 and time_window_minutes > 0 do
      length(errors) / time_window_minutes
    else
      0.0
    end
  end

  defp group_by_severity(errors) do
    errors
    |> Enum.group_by(& &1.severity)
    |> Enum.map(fn {severity, severity_errors} -> {severity, length(severity_errors)} end)
    |> Map.new()
  end

  defp get_top_errors(errors, limit) do
    errors
    |> Enum.group_by(&inspect(&1.error))
    |> Enum.map(fn {error_type, occurrences} ->
      %{
        error_type: error_type,
        count: length(occurrences),
        last_occurrence: Enum.max_by(occurrences, & &1.timestamp).timestamp
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  defp create_hour_buckets(hours_back) do
    current_hour = div(System.system_time(:millisecond), 3_600_000)

    for i <- (hours_back - 1)..0, into: %{} do
      hour = current_hour - i
      {hour, 0}
    end
  end

  defp bucket_errors_by_hour(errors, hour_buckets) do
    error_counts =
      errors
      |> Enum.group_by(&div(&1.timestamp, 3_600_000))
      |> Enum.map(fn {hour, hour_errors} -> {hour, length(hour_errors)} end)
      |> Map.new()

    Map.merge(hour_buckets, error_counts)
  end

  defp calculate_trend_direction(hourly_counts) do
    counts = Map.values(hourly_counts)

    if length(counts) < 2 do
      :stable
    else
      recent_half = Enum.take(counts, -div(length(counts), 2))
      older_half = Enum.take(counts, div(length(counts), 2))

      recent_avg = Enum.sum(recent_half) / length(recent_half)
      older_avg = Enum.sum(older_half) / length(older_half)

      cond do
        recent_avg > older_avg * 1.2 -> :increasing
        recent_avg < older_avg * 0.8 -> :decreasing
        true -> :stable
      end
    end
  end

  defp cleanup_old_errors(state) do
    cutoff_time = System.system_time(:millisecond) - @error_retention_days * 24 * 60 * 60 * 1000

    new_errors =
      state.errors
      |> Enum.map(fn {category, errors} ->
        recent_errors = Enum.filter(errors, &(&1.timestamp >= cutoff_time))
        {category, recent_errors}
      end)
      |> Map.new()

    %{state | errors: new_errors}
  end

  defp schedule_cleanup do
    # Clean up every hour
    Process.send_after(self(), :cleanup, 60 * 60 * 1000)
  end
end
