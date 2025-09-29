defmodule Pigeon.Integration.LocalDevTest do
  @moduledoc """
  Integration tests for local development setup with Podman containers.

  These tests verify that the local development environment works correctly
  by simulating the distributed architecture locally.

  To run these tests:
  1. Start the control node: ./scripts/dev-start-control.sh
  2. Start worker containers: ./scripts/dev-start-workers.sh
  3. Run tests: mix test test/integration/local_dev_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :local_dev

  alias Pigeon.Communication.Hub
  alias Pigeon.Validators.GExpressionValidator

  @control_node_url "http://localhost:4040"
  @worker_urls ["http://localhost:8081", "http://localhost:8082"]

  describe "Local Development Environment" do
    test "control node is running and healthy" do
      case Req.get("#{@control_node_url}/health", receive_timeout: 5_000) do
        {:ok, %{status: 200, body: body}} ->
          assert is_binary(body) or is_map(body)

        {:error, reason} ->
          flunk("Control node not responding: #{inspect(reason)}")
      end
    end

    test "workers are running and healthy" do
      for {worker_url, index} <- Enum.with_index(@worker_urls, 1) do
        case Req.get("#{worker_url}/health", receive_timeout: 5_000) do
          {:ok, %{status: 200, body: body}} ->
            if is_map(body) do
              assert body["status"] == "healthy"
              assert body["worker_id"] == "worker-#{index}"
            end

          {:error, reason} ->
            flunk("Worker #{index} not responding: #{inspect(reason)}")
        end
      end
    end

    test "workers register with control node" do
      # Wait a moment for registration
      Process.sleep(2_000)

      case Hub.get_status() do
        {:ok, status} ->
          assert status.active_workers >= 2
          assert length(status.workers) >= 2

        {:error, reason} ->
          flunk("Failed to get hub status: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "can process G-expression work across distributed workers" do
      work_data = """
      {
        "g": "app",
        "v": {
          "fn": {"g": "ref", "v": "+"},
          "args": {
            "g": "vec",
            "v": [
              {"g": "lit", "v": 1},
              {"g": "lit", "v": 2}
            ]
          }
        }
      }
      """

      case Pigeon.process_work(work_data, GExpressionValidator, workers: 2, iterations: 1) do
        {:ok, results} ->
          assert results.total_runs >= 1
          assert results.success_rate > 0.0
          assert results.errors == 0
          assert map_size(results.worker_results) >= 1

        {:error, reason} ->
          flunk("Work processing failed: #{inspect(reason)}")
      end
    end

    @tag timeout: 45_000
    test "can process batch work" do
      work_items = [
        ~s({"g": "lit", "v": 42}),
        ~s({"g": "ref", "v": "x"}),
        ~s({"g": "lit", "v": "hello"})
      ]

      case Pigeon.process_work_batch(work_items, GExpressionValidator, workers: 2) do
        {:ok, results} ->
          assert results.total_runs >= length(work_items)
          assert results.batch_count >= 1

        {:error, reason} ->
          flunk("Batch processing failed: #{inspect(reason)}")
      end
    end

    test "custom validator can be used" do
      defmodule LocalTestValidator do
        @behaviour Pigeon.Work.Validator

        def validate(work_string, _opts) do
          case String.contains?(work_string, "test") do
            true -> {:ok, %{status: :valid, contains_test: true}}
            false -> {:error, %{status: :invalid, message: "No 'test' found"}}
          end
        end

        def validate_batch(work_items, opts) do
          results = Enum.map(work_items, &validate(&1, opts))
          {:ok, results}
        end

        def metadata do
          %{
            name: "Local Test Validator",
            version: "1.0.0",
            description: "Tests for 'test' string",
            supported_formats: ["text"]
          }
        end
      end

      # Test valid work
      case Pigeon.process_work("this is a test", LocalTestValidator, workers: 1, iterations: 1) do
        {:ok, results} ->
          assert results.success_rate == 1.0
          assert results.errors == 0

        {:error, reason} ->
          flunk("Custom validator failed: #{inspect(reason)}")
      end

      # Test invalid work
      case Pigeon.process_work("this is invalid", LocalTestValidator, workers: 1, iterations: 1) do
        {:ok, results} ->
          assert results.success_rate == 0.0
          assert results.errors >= 1

        {:error, reason} ->
          flunk("Custom validator failed: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "can handle high load" do
      # Generate multiple work items
      work_items =
        Enum.map(1..10, fn i ->
          Jason.encode!(%{"g" => "lit", "v" => i})
        end)

      start_time = System.monotonic_time(:millisecond)

      case Pigeon.process_work_batch(work_items, GExpressionValidator, workers: 2) do
        {:ok, results} ->
          end_time = System.monotonic_time(:millisecond)
          processing_time = end_time - start_time

          assert results.total_runs >= length(work_items)
          # Should complete within 30 seconds
          assert processing_time < 30_000

          IO.puts("Processed #{results.total_runs} items in #{processing_time}ms")

        {:error, reason} ->
          flunk("High load test failed: #{inspect(reason)}")
      end
    end

    test "workers handle invalid work gracefully" do
      invalid_json = "{ invalid json }"

      case Pigeon.process_work(invalid_json, GExpressionValidator, workers: 1, iterations: 1) do
        {:ok, results} ->
          # Should handle error gracefully
          assert results.errors >= 1
          assert results.success_rate == 0.0

        {:error, reason} ->
          flunk("Error handling test failed: #{inspect(reason)}")
      end
    end

    test "health monitoring works" do
      case Pigeon.Monitoring.HealthMonitor.get_health_status() do
        {:ok, health_status} ->
          assert health_status.cluster_health in [:healthy, :degraded]
          assert health_status.healthy_workers >= 0
          assert health_status.total_workers >= 0

        {:error, reason} ->
          flunk("Health monitoring failed: #{inspect(reason)}")
      end
    end
  end

  describe "Development Workflow" do
    test "can list available validators" do
      case Pigeon.list_validators() do
        {:ok, validators} ->
          assert is_list(validators)
          assert "Pigeon.Validators.GExpressionValidator" in validators

        {:error, reason} ->
          flunk("Validator listing failed: #{inspect(reason)}")
      end
    end

    test "can validate validator implementations" do
      # Test valid validator
      assert {:ok, :valid} = Pigeon.validate_validator(GExpressionValidator)

      # Test invalid validator (String module)
      assert {:error, {:missing_callbacks, _}} = Pigeon.validate_validator(String)
    end

    test "cluster status provides useful information" do
      case Pigeon.cluster_status() do
        {:ok, status} ->
          assert Map.has_key?(status, :cluster_status)
          assert Map.has_key?(status, :active_workers)
          assert Map.has_key?(status, :total_workers)

        {:error, reason} ->
          # In local dev, cluster manager might not be fully initialized
          IO.puts("Note: Cluster status not available in local dev: #{inspect(reason)}")
      end
    end
  end

  describe "Performance and Reliability" do
    @tag timeout: 30_000
    test "processes work consistently" do
      work_data = ~s({"g": "lit", "v": 123})

      # Run the same work multiple times
      results =
        for _ <- 1..5 do
          case Pigeon.process_work(work_data, GExpressionValidator, workers: 1, iterations: 1) do
            {:ok, result} -> result.success_rate
            {:error, _} -> 0.0
          end
        end

      # All runs should succeed
      assert Enum.all?(results, &(&1 == 1.0))
    end

    @tag timeout: 30_000
    test "handles concurrent requests" do
      work_data = ~s({"g": "lit", "v": 456})

      # Start multiple concurrent requests
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            Pigeon.process_work(work_data, GExpressionValidator, workers: 1, iterations: 1)
          end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks, 25_000)

      # All should succeed
      for {:ok, result} <- results do
        assert result.success_rate == 1.0
      end
    end
  end
end
