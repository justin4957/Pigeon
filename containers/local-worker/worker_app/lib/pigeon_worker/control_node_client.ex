defmodule PigeonWorker.ControlNodeClient do
  @moduledoc """
  Client for communicating with the Pigeon control node.
  Handles worker registration and heartbeat messages.
  """

  use GenServer
  require Logger

  defstruct [
    :control_host,
    :control_port,
    :worker_id,
    :worker_endpoint,
    :registered,
    :heartbeat_interval
  ]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    # Set start time for uptime calculation
    Application.put_env(:pigeon_worker, :start_time, System.system_time(:second))

    state = %__MODULE__{
      control_host: System.get_env("CONTROL_NODE_HOST", "localhost"),
      control_port: System.get_env("CONTROL_NODE_PORT", "4040"),
      worker_id: System.get_env("WORKER_ID", "worker-#{:rand.uniform(1000)}"),
      worker_endpoint: build_worker_endpoint(),
      registered: false,
      heartbeat_interval: 30_000  # 30 seconds
    }

    # Schedule initial registration
    send(self(), :register)

    {:ok, state}
  end

  def handle_info(:register, state) do
    case register_with_control_node(state) do
      :ok ->
        Logger.info("Worker #{state.worker_id} registered successfully")
        new_state = %{state | registered: true}

        # Start heartbeat timer
        schedule_heartbeat(state.heartbeat_interval)

        {:noreply, new_state}

      :error ->
        Logger.warning("Worker #{state.worker_id} registration failed, retrying in 5s...")
        Process.send_after(self(), :register, 5_000)
        {:noreply, state}
    end
  end

  def handle_info(:heartbeat, state) do
    if state.registered do
      send_heartbeat(state)
    end

    # Schedule next heartbeat
    schedule_heartbeat(state.heartbeat_interval)

    {:noreply, state}
  end

  # Private functions

  defp build_worker_endpoint do
    # In container, the worker listens on all interfaces
    worker_port = System.get_env("WORKER_PORT", "8080")

    # Get the container's hostname/IP that control node can reach
    # In Podman, this would be the host's IP or container network IP
    case System.get_env("WORKER_HOST") do
      nil ->
        # Default to the container's external port mapping
        case System.get_env("WORKER_EXTERNAL_PORT") do
          nil -> "http://host.containers.internal:#{worker_port}"
          external_port -> "http://host.containers.internal:#{external_port}"
        end

      worker_host ->
        "http://#{worker_host}:#{worker_port}"
    end
  end

  defp register_with_control_node(state) do
    url = "http://#{state.control_host}:#{state.control_port}/api/worker/register"

    worker_info = %{
      worker_id: state.worker_id,
      endpoint: state.worker_endpoint,
      capabilities: ["validation", "processing"],
      worker_type: System.get_env("WORKER_TYPE", "general"),
      max_concurrent_jobs: 5,
      registered_at: System.system_time(:second)
    }

    case Req.post(url, json: worker_info, receive_timeout: 10_000) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status}} ->
        Logger.error("Registration failed with HTTP #{status}")
        :error

      {:error, reason} ->
        Logger.error("Registration failed: #{inspect(reason)}")
        :error
    end
  end

  defp send_heartbeat(state) do
    url = "http://#{state.control_host}:#{state.control_port}/api/worker/heartbeat"

    heartbeat_data = %{
      worker_id: state.worker_id,
      timestamp: System.system_time(:second),
      status: :active,
      current_jobs: 0,  # Could track actual job count
      uptime: get_uptime(),
      health: %{
        cpu_usage: :rand.uniform(50) + 10,
        memory_usage: :rand.uniform(60) + 20,
        load_average: :rand.uniform(2) + 0.1
      }
    }

    case Req.post(url, json: heartbeat_data, receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        Logger.debug("Heartbeat sent successfully")

      {:ok, %{status: status}} ->
        Logger.warning("Heartbeat failed with HTTP #{status}")

      {:error, reason} ->
        Logger.warning("Heartbeat failed: #{inspect(reason)}")
    end
  end

  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end

  defp get_uptime do
    start_time = Application.get_env(:pigeon_worker, :start_time, System.system_time(:second))
    System.system_time(:second) - start_time
  end
end