defmodule PigeonWorker.Server do
  @moduledoc """
  HTTP server for Pigeon worker node.
  Receives work requests and processes them using configured validators.
  """

  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  def start_link(_) do
    port = String.to_integer(System.get_env("WORKER_PORT", "8080"))
    Bandit.start_link(plug: __MODULE__, port: port)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  # Health check endpoint
  get "/health" do
    worker_id = System.get_env("WORKER_ID", "unknown")

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      status: "healthy",
      worker_id: worker_id,
      timestamp: System.system_time(:second),
      uptime: get_uptime()
    }))
  end

  # Receive work from control node
  post "/api/work" do
    worker_id = System.get_env("WORKER_ID", "unknown")

    case conn.body_params do
      %{"work_data" => work_data, "validator_module" => validator_module, "job_id" => job_id} ->
        Logger.info("Worker #{worker_id} received work for job #{job_id}")

        result = process_work(work_data, validator_module)

        # Send result back to control node
        send_result_to_control_node(job_id, worker_id, result)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "accepted", job_id: job_id}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid work request"}))
    end
  end

  # Handle message from control node
  post "/api/message" do
    case conn.body_params do
      %{"type" => "welcome", "data" => data} ->
        worker_id = System.get_env("WORKER_ID", "unknown")
        Logger.info("Worker #{worker_id} received welcome message: #{inspect(data)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "acknowledged"}))

      %{"type" => "task_assignment", "data" => task_data} ->
        handle_task_assignment(task_data)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "accepted"}))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid message"}))
    end
  end

  # Fallback route
  match _ do
    send_resp(conn, 404, "Not Found")
  end

  # Private functions

  defp process_work(work_data, validator_module_string) do
    try do
      # Load the validator module
      validator_module = case validator_module_string do
        "Pigeon.Validators.GExpressionValidator" ->
          PigeonWorker.GExpressionValidator
        "Pigeon.Validators.JsonValidator" ->
          PigeonWorker.JsonValidator
        _ ->
          PigeonWorker.DefaultValidator
      end

      # Process the work
      case validator_module.validate(work_data, []) do
        {:ok, result} ->
          %{
            status: :success,
            result: result,
            worker_id: System.get_env("WORKER_ID", "unknown"),
            processed_at: System.system_time(:second),
            execution_time_ms: :rand.uniform(100) + 50  # Simulate processing time
          }

        {:error, reason} ->
          %{
            status: :error,
            error: reason,
            worker_id: System.get_env("WORKER_ID", "unknown"),
            processed_at: System.system_time(:second)
          }
      end
    rescue
      error ->
        %{
          status: :error,
          error: "Processing exception: #{inspect(error)}",
          worker_id: System.get_env("WORKER_ID", "unknown"),
          processed_at: System.system_time(:second)
        }
    end
  end

  defp handle_task_assignment(task_data) do
    worker_id = System.get_env("WORKER_ID", "unknown")
    job_id = task_data["job_id"]

    Logger.info("Worker #{worker_id} processing task for job #{job_id}")

    # Process the task
    result = process_work(task_data["data"], task_data["validator_module"] || "default")

    # Send result back
    send_result_to_control_node(job_id, worker_id, result)
  end

  defp send_result_to_control_node(job_id, worker_id, result) do
    control_host = System.get_env("CONTROL_NODE_HOST", "localhost")
    control_port = System.get_env("CONTROL_NODE_PORT", "4040")

    url = "http://#{control_host}:#{control_port}/api/worker/result"

    payload = %{
      job_id: job_id,
      worker_id: worker_id,
      result: result,
      timestamp: System.system_time(:second)
    }

    case Req.post(url, json: payload, receive_timeout: 10_000) do
      {:ok, %{status: 200}} ->
        Logger.info("Successfully sent result for job #{job_id}")

      {:ok, %{status: status}} ->
        Logger.warning("Failed to send result for job #{job_id}: HTTP #{status}")

      {:error, reason} ->
        Logger.error("Failed to send result for job #{job_id}: #{inspect(reason)}")
    end
  end

  defp get_uptime do
    # Simple uptime calculation (seconds since process start)
    System.system_time(:second) - Application.get_env(:pigeon_worker, :start_time, System.system_time(:second))
  end
end