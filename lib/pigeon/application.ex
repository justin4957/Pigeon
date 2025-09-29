defmodule Pigeon.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Registry for circuit breakers
      {Registry, keys: :unique, name: Pigeon.CircuitBreakerRegistry},

      # Resilience components
      {Pigeon.Resilience.ErrorLogger, []},
      {Pigeon.Resilience.FailureDetector, []},

      # Core cluster management
      {Pigeon.Cluster.Manager, []},

      # Communication hub
      {Pigeon.Communication.Hub, [port: 4040]},

      # Job management
      {Pigeon.Jobs.JobManager, []},

      # Health monitoring
      {Pigeon.Monitoring.HealthMonitor, []}
    ]

    opts = [strategy: :one_for_one, name: Pigeon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
