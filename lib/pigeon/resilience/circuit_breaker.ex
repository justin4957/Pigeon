defmodule Pigeon.Resilience.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for protecting against cascading failures.

  Tracks failure rates and temporarily stops sending requests to failing services
  to allow them time to recover.
  """

  use GenServer
  require Logger

  @default_failure_threshold 5
  @default_timeout 30_000
  @default_recovery_timeout 60_000

  defstruct [
    :name,
    :failure_threshold,
    :timeout,
    :recovery_timeout,
    :state,
    :failure_count,
    :last_failure_time,
    :half_open_max_requests,
    :half_open_request_count
  ]

  # States: :closed, :open, :half_open
  # :closed - normal operation
  # :open - circuit is open, rejecting requests
  # :half_open - testing if service has recovered

  ## Public API

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  def call(circuit_breaker_name, fun) when is_function(fun, 0) do
    GenServer.call(via_tuple(circuit_breaker_name), {:call, fun})
  end

  def get_state(circuit_breaker_name) do
    GenServer.call(via_tuple(circuit_breaker_name), :get_state)
  end

  def reset(circuit_breaker_name) do
    GenServer.call(via_tuple(circuit_breaker_name), :reset)
  end

  ## GenServer Implementation

  def init(opts) do
    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      recovery_timeout: Keyword.get(opts, :recovery_timeout, @default_recovery_timeout),
      state: :closed,
      failure_count: 0,
      last_failure_time: nil,
      half_open_max_requests: Keyword.get(opts, :half_open_max_requests, 3),
      half_open_request_count: 0
    }

    Logger.info("Circuit breaker #{state.name} initialized in #{state.state} state")
    {:ok, state}
  end

  def handle_call({:call, fun}, _from, state) do
    case can_execute?(state) do
      {:ok, new_state} ->
        case execute_with_monitoring(fun, new_state) do
          {:ok, result, updated_state} ->
            final_state = handle_success(updated_state)
            {:reply, {:ok, result}, final_state}

          {:error, reason, updated_state} ->
            final_state = handle_failure(updated_state, reason)
            {:reply, {:error, {:circuit_breaker, reason}}, final_state}
        end

      {:error, reason} ->
        Logger.debug("Circuit breaker #{state.name} rejecting request: #{reason}")
        {:reply, {:error, {:circuit_breaker, reason}}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    status = %{
      name: state.name,
      state: state.state,
      failure_count: state.failure_count,
      last_failure_time: state.last_failure_time,
      half_open_request_count: state.half_open_request_count
    }

    {:reply, status, state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        last_failure_time: nil,
        half_open_request_count: 0
    }

    Logger.info("Circuit breaker #{state.name} manually reset to closed state")
    {:reply, :ok, new_state}
  end

  ## Private Functions

  defp via_tuple(name) do
    {:via, Registry, {Pigeon.CircuitBreakerRegistry, name}}
  end

  defp can_execute?(state) do
    case state.state do
      :closed ->
        {:ok, state}

      :open ->
        if should_attempt_reset?(state) do
          new_state = %{state | state: :half_open, half_open_request_count: 0}
          Logger.info("Circuit breaker #{state.name} transitioning to half-open state")
          {:ok, new_state}
        else
          {:error, :circuit_open}
        end

      :half_open ->
        if state.half_open_request_count < state.half_open_max_requests do
          new_state = %{state | half_open_request_count: state.half_open_request_count + 1}
          {:ok, new_state}
        else
          {:error, :circuit_half_open_limit_reached}
        end
    end
  end

  defp execute_with_monitoring(fun, state) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case fun.() do
        {:ok, result} ->
          execution_time = System.monotonic_time(:millisecond) - start_time
          Logger.debug("Circuit breaker #{state.name} successful execution in #{execution_time}ms")
          {:ok, result, state}

        {:error, reason} ->
          execution_time = System.monotonic_time(:millisecond) - start_time

          Logger.warn(
            "Circuit breaker #{state.name} execution failed in #{execution_time}ms: #{inspect(reason)}"
          )

          {:error, reason, state}

        other ->
          Logger.warn(
            "Circuit breaker #{state.name} execution returned unexpected result: #{inspect(other)}"
          )

          {:error, {:unexpected_result, other}, state}
      end
    catch
      kind, reason ->
        execution_time = System.monotonic_time(:millisecond) - start_time

        Logger.error(
          "Circuit breaker #{state.name} execution crashed in #{execution_time}ms: #{kind} #{inspect(reason)}"
        )

        {:error, {:exception, kind, reason}, state}
    end
  end

  defp handle_success(state) do
    case state.state do
      :closed ->
        # Reset failure count on success
        %{state | failure_count: 0}

      :half_open ->
        # If half-open and we got a success, close the circuit
        Logger.info(
          "Circuit breaker #{state.name} transitioning to closed state after successful half-open request"
        )

        %{
          state
          | state: :closed,
            failure_count: 0,
            last_failure_time: nil,
            half_open_request_count: 0
        }

      :open ->
        # Should not happen, but handle gracefully
        state
    end
  end

  defp handle_failure(state, reason) do
    current_time = System.system_time(:millisecond)
    new_failure_count = state.failure_count + 1

    Logger.warn(
      "Circuit breaker #{state.name} recorded failure #{new_failure_count}: #{inspect(reason)}"
    )

    new_state = %{state | failure_count: new_failure_count, last_failure_time: current_time}

    case state.state do
      :closed ->
        if new_failure_count >= state.failure_threshold do
          Logger.warn("Circuit breaker #{state.name} opening due to #{new_failure_count} failures")
          %{new_state | state: :open}
        else
          new_state
        end

      :half_open ->
        # If half-open request fails, go back to open
        Logger.warn(
          "Circuit breaker #{state.name} returning to open state after failed half-open request"
        )

        %{new_state | state: :open, half_open_request_count: 0}

      :open ->
        new_state
    end
  end

  defp should_attempt_reset?(state) do
    if state.last_failure_time do
      current_time = System.system_time(:millisecond)
      current_time - state.last_failure_time >= state.recovery_timeout
    else
      false
    end
  end
end
