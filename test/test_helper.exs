ExUnit.start()

# Configure test environment
Application.put_env(:pigeon, :test_mode, true)

# Mock external services for testing
defmodule TestHelper do
  def mock_cluster_status do
    %{
      cluster_status: :running,
      active_workers: 2,
      total_workers: 2,
      active_jobs: 0,
      completed_jobs: 0,
      workers: [
        %{
          instance_id: "i-12345",
          public_ip: "10.0.1.1",
          status: :idle,
          current_jobs: 0,
          max_jobs: 5,
          uptime: 3600
        },
        %{
          instance_id: "i-67890",
          public_ip: "10.0.1.2",
          status: :idle,
          current_jobs: 0,
          max_jobs: 5,
          uptime: 3600
        }
      ]
    }
  end

  def mock_job_results do
    %{
      total_runs: 5,
      successes: 4,
      errors: 1,
      success_rate: 0.8,
      average_time_ms: 250,
      worker_results: %{
        "worker1" => %{
          total: 3,
          successes: 2,
          success_rate: 0.67,
          execution_time_ms: 200
        },
        "worker2" => %{
          total: 2,
          successes: 2,
          success_rate: 1.0,
          execution_time_ms: 300
        }
      },
      error_details: [
        %{
          worker: "worker1",
          message: "Processing timeout",
          timestamp: 1234567890
        }
      ]
    }
  end
end