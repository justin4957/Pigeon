defmodule Pigeon.Config do
  @moduledoc """
  Configuration management for Pigeon.
  """

  def ensure_aws_config do
    unless System.get_env("AWS_ACCESS_KEY_ID") do
      raise """
      AWS credentials not configured. Please set:

      export AWS_ACCESS_KEY_ID=your_access_key
      export AWS_SECRET_ACCESS_KEY=your_secret_key
      export AWS_DEFAULT_REGION=us-west-2

      Or configure AWS CLI with: aws configure
      """
    end
  end

  def get_default_config do
    %{
      aws: %{
        region: System.get_env("AWS_DEFAULT_REGION") || "us-west-2",
        instance_type: "t3.medium",
        # Amazon Linux 2023
        ami_id: "ami-0c02fb55956c7d316"
      },
      cluster: %{
        default_node_count: 2,
        max_nodes: 10,
        communication_port: 4040
      },
      validation: %{
        default_iterations: 5,
        timeout_seconds: 300
      },
      resilience: get_resilience_config(),
      logging: get_logging_config(),
      monitoring: get_monitoring_config()
    }
  end

  def get_resilience_config do
    %{
      circuit_breaker: %{
        failure_threshold: get_env_int("PIGEON_CB_FAILURE_THRESHOLD", 5),
        timeout_ms: get_env_int("PIGEON_CB_TIMEOUT_MS", 30_000),
        recovery_timeout_ms: get_env_int("PIGEON_CB_RECOVERY_TIMEOUT_MS", 60_000),
        half_open_max_requests: get_env_int("PIGEON_CB_HALF_OPEN_MAX_REQUESTS", 3)
      },
      retry: %{
        max_retries: get_env_int("PIGEON_RETRY_MAX_RETRIES", 3),
        base_delay_ms: get_env_int("PIGEON_RETRY_BASE_DELAY_MS", 1000),
        max_delay_ms: get_env_int("PIGEON_RETRY_MAX_DELAY_MS", 30_000),
        jitter_factor: get_env_float("PIGEON_RETRY_JITTER_FACTOR", 0.1),
        backoff_strategy: get_env_atom("PIGEON_RETRY_BACKOFF_STRATEGY", :exponential)
      },
      failure_detector: %{
        heartbeat_interval_ms: get_env_int("PIGEON_FD_HEARTBEAT_INTERVAL_MS", 30_000),
        failure_threshold: get_env_int("PIGEON_FD_FAILURE_THRESHOLD", 3),
        response_timeout_ms: get_env_int("PIGEON_FD_RESPONSE_TIMEOUT_MS", 10_000)
      },
      timeouts: %{
        worker_communication_ms: get_env_int("PIGEON_WORKER_COMM_TIMEOUT_MS", 30_000),
        job_execution_timeout_ms: get_env_int("PIGEON_JOB_EXECUTION_TIMEOUT_MS", 300_000),
        aws_operation_timeout_ms: get_env_int("PIGEON_AWS_OPERATION_TIMEOUT_MS", 120_000),
        health_check_timeout_ms: get_env_int("PIGEON_HEALTH_CHECK_TIMEOUT_MS", 5_000)
      }
    }
  end

  def get_logging_config do
    %{
      level: get_env_atom("PIGEON_LOG_LEVEL", :info),
      error_retention_days: get_env_int("PIGEON_ERROR_RETENTION_DAYS", 7),
      max_errors_per_category: get_env_int("PIGEON_MAX_ERRORS_PER_CATEGORY", 1000),
      enable_structured_logging: get_env_bool("PIGEON_ENABLE_STRUCTURED_LOGGING", true),
      enable_correlation_ids: get_env_bool("PIGEON_ENABLE_CORRELATION_IDS", true)
    }
  end

  def get_monitoring_config do
    %{
      enable_metrics: get_env_bool("PIGEON_ENABLE_METRICS", true),
      metrics_port: get_env_int("PIGEON_METRICS_PORT", 9090),
      health_check_port: get_env_int("PIGEON_HEALTH_CHECK_PORT", 8080),
      enable_distributed_tracing: get_env_bool("PIGEON_ENABLE_DISTRIBUTED_TRACING", false)
    }
  end

  def get_config(key_path) when is_list(key_path) do
    get_in(get_default_config(), key_path)
  end

  def get_config(key) when is_atom(key) do
    get_default_config()[key]
  end

  def validate_config(config \\ nil) do
    config = config || get_default_config()

    with :ok <- validate_aws_config(config.aws),
         :ok <- validate_resilience_config(config.resilience),
         :ok <- validate_timeouts(config.resilience.timeouts) do
      {:ok, config}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Environment variable helpers
  defp get_env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> default
  end

  defp get_env_float(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_float(value)
    end
  rescue
    ArgumentError -> default
  end

  defp get_env_bool(key, default) do
    case System.get_env(key) do
      nil -> default
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp get_env_atom(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_atom(value)
    end
  rescue
    ArgumentError -> default
  end

  # Configuration validation
  defp validate_aws_config(aws_config) do
    required_fields = [:region, :instance_type, :ami_id]
    missing_fields = Enum.filter(required_fields, &is_nil(aws_config[&1]))

    if missing_fields == [] do
      :ok
    else
      {:error, "Missing AWS configuration fields: #{inspect(missing_fields)}"}
    end
  end

  defp validate_resilience_config(resilience_config) do
    with :ok <- validate_circuit_breaker_config(resilience_config.circuit_breaker),
         :ok <- validate_retry_config(resilience_config.retry),
         :ok <- validate_failure_detector_config(resilience_config.failure_detector) do
      :ok
    else
      error -> error
    end
  end

  defp validate_circuit_breaker_config(cb_config) do
    cond do
      cb_config.failure_threshold <= 0 ->
        {:error, "Circuit breaker failure_threshold must be positive"}

      cb_config.timeout_ms <= 0 ->
        {:error, "Circuit breaker timeout_ms must be positive"}

      cb_config.recovery_timeout_ms <= 0 ->
        {:error, "Circuit breaker recovery_timeout_ms must be positive"}

      true ->
        :ok
    end
  end

  defp validate_retry_config(retry_config) do
    cond do
      retry_config.max_retries < 0 ->
        {:error, "Retry max_retries must be non-negative"}

      retry_config.base_delay_ms <= 0 ->
        {:error, "Retry base_delay_ms must be positive"}

      retry_config.max_delay_ms <= retry_config.base_delay_ms ->
        {:error, "Retry max_delay_ms must be greater than base_delay_ms"}

      retry_config.jitter_factor < 0 or retry_config.jitter_factor > 1 ->
        {:error, "Retry jitter_factor must be between 0 and 1"}

      retry_config.backoff_strategy not in [:exponential, :linear, :constant] ->
        {:error, "Invalid retry backoff_strategy"}

      true ->
        :ok
    end
  end

  defp validate_failure_detector_config(fd_config) do
    cond do
      fd_config.heartbeat_interval_ms <= 0 ->
        {:error, "Failure detector heartbeat_interval_ms must be positive"}

      fd_config.failure_threshold <= 0 ->
        {:error, "Failure detector failure_threshold must be positive"}

      fd_config.response_timeout_ms <= 0 ->
        {:error, "Failure detector response_timeout_ms must be positive"}

      true ->
        :ok
    end
  end

  defp validate_timeouts(timeouts_config) do
    timeout_fields = Map.keys(timeouts_config)
    invalid_timeouts = Enum.filter(timeout_fields, &(timeouts_config[&1] <= 0))

    if invalid_timeouts == [] do
      :ok
    else
      {:error, "Invalid timeout values for: #{inspect(invalid_timeouts)}"}
    end
  end

  # Profile-specific configurations
  def get_development_config do
    base_config = get_default_config()

    development_overrides = %{
      resilience: %{
        circuit_breaker: %{
          # More sensitive in dev
          failure_threshold: 2,
          # Shorter timeouts in dev
          timeout_ms: 10_000,
          recovery_timeout_ms: 30_000
        },
        retry: %{
          # Fewer retries in dev
          max_retries: 2,
          # Faster retries in dev
          base_delay_ms: 500
        }
      },
      logging: %{
        level: :debug,
        enable_structured_logging: true
      }
    }

    deep_merge(base_config, development_overrides)
  end

  def get_production_config do
    base_config = get_default_config()

    production_overrides = %{
      resilience: %{
        circuit_breaker: %{
          # More tolerant in production
          failure_threshold: 10,
          # Longer timeouts in production
          timeout_ms: 60_000,
          recovery_timeout_ms: 120_000
        },
        retry: %{
          # More retries in production
          max_retries: 5,
          # Longer delays in production
          base_delay_ms: 2000
        }
      },
      logging: %{
        level: :info,
        # Keep errors longer in production
        error_retention_days: 30
      }
    }

    deep_merge(base_config, production_overrides)
  end

  def get_config_for_environment(env \\ Mix.env()) do
    case env do
      :dev -> get_development_config()
      :test -> get_development_config()
      :prod -> get_production_config()
      _ -> get_default_config()
    end
  end

  # Helper function for deep merging configurations
  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end
end
