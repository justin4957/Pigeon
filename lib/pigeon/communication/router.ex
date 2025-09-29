defmodule Pigeon.Communication.Router do
  @moduledoc """
  HTTP router for Pigeon communication hub.
  Handles worker registration, heartbeats, and job management.
  """

  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Health check endpoint
  get "/health" do
    response = %{
      status: "healthy",
      service: "pigeon-control-node",
      timestamp: System.system_time(:second),
      version: Application.spec(:pigeon, :vsn) |> to_string()
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Worker registration endpoint
  post "/api/worker/register" do
    case conn.body_params do
      worker_info when is_map(worker_info) ->
        case Pigeon.Communication.Hub.register_worker(worker_info) do
          {:ok, :registered} ->
            response = %{
              status: "registered",
              worker_id: worker_info["worker_id"],
              message: "Worker registered successfully"
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))

          {:error, reason} ->
            response = %{
              status: "error",
              message: "Registration failed: #{inspect(reason)}"
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(response))
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid registration data"}))
    end
  end

  # Worker heartbeat endpoint
  post "/api/worker/heartbeat" do
    case conn.body_params do
      %{"worker_id" => worker_id} = heartbeat_data ->
        Pigeon.Communication.Hub.worker_heartbeat(worker_id, heartbeat_data)

        response = %{
          status: "acknowledged",
          worker_id: worker_id,
          timestamp: System.system_time(:second)
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(response))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid heartbeat data"}))
    end
  end

  # Worker result submission endpoint
  post "/api/worker/result" do
    case conn.body_params do
      %{"job_id" => job_id, "worker_id" => worker_id, "result" => result} ->
        Pigeon.Communication.Hub.worker_result(worker_id, job_id, result)

        response = %{
          status: "received",
          job_id: job_id,
          worker_id: worker_id
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(response))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid result data"}))
    end
  end

  # Job status endpoint
  get "/api/jobs/:job_id" do
    job_id = conn.path_params["job_id"]

    case Pigeon.Communication.Hub.get_job_status(job_id) do
      {:ok, job_status} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(job_status))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Job not found"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: inspect(reason)}))
    end
  end

  # Submit new job endpoint
  post "/api/jobs" do
    case conn.body_params do
      job_data when is_map(job_data) ->
        case Pigeon.Communication.Hub.submit_job(job_data) do
          {:ok, job_id} ->
            response = %{
              status: "submitted",
              job_id: job_id
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(201, Jason.encode!(response))

          {:error, reason} ->
            response = %{
              status: "error",
              message: "Job submission failed: #{inspect(reason)}"
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(response))
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid job data"}))
    end
  end

  # Hub status endpoint
  get "/api/status" do
    try do
      # Try to get status from the hub GenServer
      case GenServer.whereis(Pigeon.Communication.Hub) do
        nil ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(503, Jason.encode!(%{error: "Hub not running"}))

        _pid ->
          # Get basic status information
          status = %{
            hub_status: "running",
            timestamp: System.system_time(:second),
            # Could implement connection tracking
            active_connections: 0,
            uptime: get_uptime()
          }

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(status))
      end
    rescue
      error ->
        Logger.error("Error getting hub status: #{inspect(error)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: "Internal server error"}))
    end
  end

  # Catch-all for undefined routes
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Private helper functions

  defp get_uptime do
    # Simple uptime based on application start time
    case Application.get_env(:pigeon, :start_time) do
      nil ->
        Application.put_env(:pigeon, :start_time, System.system_time(:second))
        0

      start_time ->
        System.system_time(:second) - start_time
    end
  end
end
