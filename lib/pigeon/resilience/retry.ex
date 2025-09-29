defmodule Pigeon.Resilience.Retry do
  @moduledoc """
  Retry mechanisms with exponential backoff and configurable policies.

  Provides intelligent retry logic for transient failures with:
  - Exponential backoff with jitter
  - Maximum retry limits
  - Configurable retry conditions
  - Detailed failure tracking
  """

  require Logger

  @default_max_retries 3
  @default_base_delay 1000
  @default_max_delay 30_000
  @default_jitter_factor 0.1

  defstruct [
    :max_retries,
    :base_delay,
    :max_delay,
    :jitter_factor,
    :retry_condition,
    :backoff_strategy
  ]

  @type retry_opts :: [
          max_retries: non_neg_integer(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          jitter_factor: float(),
          retry_condition: (any() -> boolean()),
          backoff_strategy: :exponential | :linear | :constant
        ]

  @type retry_result :: {:ok, any()} | {:error, any()}

  ## Public API

  @spec with_retry((-> retry_result()), retry_opts()) :: retry_result()
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)
    execute_with_retry(fun, config, 0, [])
  end

  @spec with_async_retry((-> retry_result()), retry_opts()) :: Task.t()
  def with_async_retry(fun, opts \\ []) when is_function(fun, 0) do
    Task.async(fn -> with_retry(fun, opts) end)
  end

  @spec calculate_delay(non_neg_integer(), retry_opts()) :: non_neg_integer()
  def calculate_delay(attempt, opts \\ []) do
    config = build_config(opts)
    base_delay = calculate_base_delay(attempt, config)
    jittered_delay = apply_jitter(base_delay, config.jitter_factor)
    min(jittered_delay, config.max_delay)
  end

  ## Private Functions

  defp build_config(opts) do
    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay: Keyword.get(opts, :base_delay, @default_base_delay),
      max_delay: Keyword.get(opts, :max_delay, @default_max_delay),
      jitter_factor: Keyword.get(opts, :jitter_factor, @default_jitter_factor),
      retry_condition: Keyword.get(opts, :retry_condition, &default_retry_condition/1),
      backoff_strategy: Keyword.get(opts, :backoff_strategy, :exponential)
    }
  end

  defp execute_with_retry(fun, config, attempt, previous_errors) do
    start_time = System.monotonic_time(:millisecond)

    case fun.() do
      {:ok, result} = success ->
        if attempt > 0 do
          execution_time = System.monotonic_time(:millisecond) - start_time
          Logger.info("Retry succeeded on attempt #{attempt + 1} after #{execution_time}ms")
        end

        success

      {:error, reason} = error ->
        execution_time = System.monotonic_time(:millisecond) - start_time

        updated_errors = [
          %{attempt: attempt, reason: reason, execution_time: execution_time} | previous_errors
        ]

        if should_retry?(reason, attempt, config) do
          delay = calculate_delay(attempt, config)

          Logger.warn(
            "Retry attempt #{attempt + 1} failed (#{execution_time}ms): #{inspect(reason)}, retrying in #{delay}ms"
          )

          :timer.sleep(delay)
          execute_with_retry(fun, config, attempt + 1, updated_errors)
        else
          final_error = build_final_error(reason, updated_errors, config)
          Logger.error("Retry exhausted after #{attempt + 1} attempts: #{inspect(final_error)}")
          {:error, final_error}
        end

      other ->
        Logger.warn("Retry function returned unexpected result: #{inspect(other)}")
        {:error, {:unexpected_result, other}}
    end
  end

  defp should_retry?(reason, attempt, config) do
    attempt < config.max_retries and config.retry_condition.(reason)
  end

  defp calculate_base_delay(attempt, config) do
    case config.backoff_strategy do
      :exponential ->
        round(config.base_delay * :math.pow(2, attempt))

      :linear ->
        config.base_delay * (attempt + 1)

      :constant ->
        config.base_delay
    end
  end

  defp apply_jitter(delay, jitter_factor) do
    jitter = delay * jitter_factor * (:rand.uniform() - 0.5) * 2
    round(delay + jitter)
  end

  defp default_retry_condition(reason) do
    case reason do
      # Network-related errors - should retry
      :timeout -> true
      :econnrefused -> true
      :nxdomain -> true
      :enetunreach -> true
      {:http_error, status} when status >= 500 -> true
      # Client errors - should not retry
      {:http_error, status} when status >= 400 and status < 500 -> false
      # AWS-related errors - retry on throttling and server errors
      {:aws_error, %{code: "Throttling"}} -> true
      {:aws_error, %{code: "RequestLimitExceeded"}} -> true
      {:aws_error, %{code: "ServiceUnavailable"}} -> true
      {:aws_error, %{code: "InternalError"}} -> true
      # Circuit breaker errors - do not retry (circuit breaker handles this)
      {:circuit_breaker, _} -> false
      # Default: retry on most errors except explicit non-retryable ones
      {:non_retryable, _} -> false
      _ -> true
    end
  end

  defp build_final_error(last_reason, error_history, config) do
    %{
      type: :retry_exhausted,
      last_error: last_reason,
      attempts: length(error_history),
      max_retries: config.max_retries,
      total_duration_ms: calculate_total_duration(error_history),
      error_history: Enum.reverse(error_history)
    }
  end

  defp calculate_total_duration(error_history) do
    if length(error_history) > 0 do
      Enum.sum(Enum.map(error_history, & &1.execution_time))
    else
      0
    end
  end

  ## Convenience Functions

  @doc """
  Retry with specific configuration for HTTP requests.
  """
  def with_http_retry(fun, opts \\ []) do
    http_opts = [
      max_retries: Keyword.get(opts, :max_retries, 3),
      base_delay: Keyword.get(opts, :base_delay, 1000),
      max_delay: Keyword.get(opts, :max_delay, 10_000),
      retry_condition: &http_retry_condition/1
    ]

    with_retry(fun, http_opts)
  end

  @doc """
  Retry with specific configuration for AWS operations.
  """
  def with_aws_retry(fun, opts \\ []) do
    aws_opts = [
      max_retries: Keyword.get(opts, :max_retries, 5),
      base_delay: Keyword.get(opts, :base_delay, 2000),
      max_delay: Keyword.get(opts, :max_delay, 60_000),
      retry_condition: &aws_retry_condition/1
    ]

    with_retry(fun, aws_opts)
  end

  defp http_retry_condition(reason) do
    case reason do
      :timeout -> true
      :econnrefused -> true
      {:http_error, status} when status >= 500 -> true
      # Rate limiting
      {:http_error, 429} -> true
      _ -> false
    end
  end

  defp aws_retry_condition(reason) do
    case reason do
      {:aws_error, %{code: "Throttling"}} -> true
      {:aws_error, %{code: "RequestLimitExceeded"}} -> true
      {:aws_error, %{code: "ServiceUnavailable"}} -> true
      {:aws_error, %{code: "InternalError"}} -> true
      {:aws_error, %{code: "RequestTimeout"}} -> true
      _ -> default_retry_condition(reason)
    end
  end
end
