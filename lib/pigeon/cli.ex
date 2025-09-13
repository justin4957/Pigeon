defmodule Pigeon.CLI do
  @moduledoc """
  Command Line Interface for Pigeon distributed AI framework.

  Adapted from Grapple CLI components for infrastructure management.
  """

  alias Pigeon.Cluster.Manager
  alias Pigeon.Infrastructure.EC2Manager
  alias Pigeon.Work.Processor
  alias Pigeon.Config

  def main(args) do
    Config.ensure_aws_config()

    args
    |> parse_args()
    |> handle_command()
  end

  defp parse_args(args) do
    Optimus.new!(
      name: "pigeon",
      description: "Distributed AI Code Generation and Validation Framework",
      version: "0.1.0",
      author: "Pigeon Team",
      about: "Spin up EC2 instances with Ollama/CodeLlama for distributed work processing",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        deploy: [
          name: "deploy",
          about: "Deploy worker nodes to AWS",
          options: [
            nodes: [
              value_name: "COUNT",
              long: "--nodes",
              short: "-n",
              help: "Number of worker nodes to deploy",
              required: false,
              default: 2,
              parser: :integer
            ],
            instance_type: [
              value_name: "TYPE",
              long: "--instance-type",
              short: "-t",
              help: "EC2 instance type (t3.medium, t3.large, etc.)",
              required: false,
              default: "t3.medium",
              parser: :string
            ],
            region: [
              value_name: "REGION",
              long: "--region",
              short: "-r",
              help: "AWS region",
              required: false,
              default: "us-west-2",
              parser: :string
            ],
            key_name: [
              value_name: "KEY",
              long: "--key-name",
              short: "-k",
              help: "AWS EC2 key pair name",
              required: false,
              parser: :string
            ]
          ]
        ],
        status: [
          name: "status",
          about: "Show cluster status",
          options: [
            detailed: [
              long: "--detailed",
              short: "-d",
              help: "Show detailed status",
              required: false,
              default: false,
              parser: :boolean
            ]
          ]
        ],
        process: [
          name: "process",
          about: "Submit work for distributed processing",
          options: [
            work_file: [
              value_name: "FILE",
              long: "--work-file",
              short: "-f",
              help: "File containing work data to process",
              required: true,
              parser: :string
            ],
            validator: [
              value_name: "MODULE",
              long: "--validator",
              short: "-v",
              help: "Validator module to use for processing",
              required: true,
              parser: :string
            ],
            workers: [
              value_name: "COUNT",
              long: "--workers",
              short: "-w",
              help: "Number of workers to use for processing",
              required: false,
              parser: :integer
            ],
            iterations: [
              value_name: "COUNT",
              long: "--iterations",
              short: "-i",
              help: "Number of processing iterations per worker",
              required: false,
              default: 5,
              parser: :integer
            ]
          ]
        ],
        scale: [
          name: "scale",
          about: "Scale cluster up or down",
          options: [
            nodes: [
              value_name: "COUNT",
              long: "--nodes",
              short: "-n",
              help: "Target number of nodes",
              required: true,
              parser: :integer
            ]
          ]
        ],
        destroy: [
          name: "destroy",
          about: "Destroy entire cluster",
          options: [
            force: [
              long: "--force",
              short: "-f",
              help: "Skip confirmation prompt",
              required: false,
              default: false,
              parser: :boolean
            ]
          ]
        ]
      ]
    )
    |> Optimus.parse!(args)
  end

  defp handle_command({:deploy, opts}) do
    IO.puts("🚀 Deploying Pigeon cluster...")
    IO.puts("   Nodes: #{opts.nodes}")
    IO.puts("   Instance Type: #{opts.instance_type}")
    IO.puts("   Region: #{opts.region}")

    case Manager.deploy_cluster(opts) do
      {:ok, cluster_info} ->
        IO.puts("✅ Cluster deployed successfully!")
        display_cluster_info(cluster_info)

      {:error, reason} ->
        IO.puts("❌ Deployment failed: #{reason}")
        System.halt(1)
    end
  end

  defp handle_command({:status, opts}) do
    case Manager.get_status() do
      {:ok, status} ->
        display_status(status, opts.detailed)

      {:error, :no_cluster} ->
        IO.puts("🕊️  No active cluster found")

      {:error, reason} ->
        IO.puts("❌ Failed to get status: #{reason}")
        System.halt(1)
    end
  end

  defp handle_command({:process, opts}) do
    IO.puts("🧪 Starting distributed work processing...")

    case File.read(opts.work_file) do
      {:ok, work_data} ->
        run_processing(work_data, opts)

      {:error, file_error} ->
        IO.puts("❌ Cannot read file: #{file_error}")
        System.halt(1)
    end
  end

  defp handle_command({:scale, opts}) do
    IO.puts("📈 Scaling cluster to #{opts.nodes} nodes...")

    case Manager.scale_to(opts.nodes) do
      {:ok, result} ->
        IO.puts("✅ Scaling completed!")
        display_scaling_result(result)

      {:error, reason} ->
        IO.puts("❌ Scaling failed: #{reason}")
        System.halt(1)
    end
  end

  defp handle_command({:destroy, opts}) do
    if opts.force or confirm_destruction() do
      IO.puts("💥 Destroying cluster...")

      case Manager.destroy_cluster() do
        {:ok, _result} ->
          IO.puts("✅ Cluster destroyed successfully!")

        {:error, reason} ->
          IO.puts("❌ Destruction failed: #{reason}")
          System.halt(1)
      end
    else
      IO.puts("❌ Destruction cancelled")
    end
  end

  defp run_processing(work_data, opts) do
    case Pigeon.Work.Validator.load_validator(opts.validator) do
      {:ok, validator_module} ->
        processing_opts = %{
          workers: opts[:workers],
          iterations: opts.iterations
        }

        case Processor.process_distributed(work_data, validator_module, processing_opts) do
          {:ok, results} ->
            display_processing_results(results)

          {:error, reason} ->
            IO.puts("❌ Processing failed: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("❌ Invalid validator module: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp display_cluster_info(cluster_info) do
    IO.puts("")
    IO.puts("📊 Cluster Information:")
    IO.puts("   Control Node: #{cluster_info.control_node}")
    IO.puts("   Worker Nodes: #{length(cluster_info.workers)}")

    cluster_info.workers
    |> Enum.with_index(1)
    |> Enum.each(fn {worker, index} ->
      IO.puts("     #{index}. #{worker.instance_id} (#{worker.public_ip}) - #{worker.status}")
    end)
  end

  defp display_status(status, detailed) do
    IO.puts("🕊️  Pigeon Cluster Status")
    IO.puts("   Status: #{status.cluster_status}")
    IO.puts("   Workers: #{status.active_workers}/#{status.total_workers}")
    IO.puts("   Jobs: #{status.active_jobs} active, #{status.completed_jobs} completed")

    if detailed do
      IO.puts("\n📋 Detailed Worker Status:")

      status.workers
      |> Enum.with_index(1)
      |> Enum.each(fn {worker, index} ->
        IO.puts("   #{index}. #{worker.instance_id}")
        IO.puts("      IP: #{worker.public_ip}")
        IO.puts("      Status: #{worker.status}")
        IO.puts("      Load: #{worker.current_jobs}/#{worker.max_jobs}")
        IO.puts("      Uptime: #{format_uptime(worker.uptime)}")
      end)
    end
  end

  defp display_scaling_result(result) do
    IO.puts("   Added: #{result.added} nodes")
    IO.puts("   Removed: #{result.removed} nodes")
    IO.puts("   Total: #{result.total} nodes")
  end

  defp display_processing_results(results) do
    IO.puts("✅ Processing completed!")
    IO.puts("   Total runs: #{results.total_runs}")
    IO.puts("   Success rate: #{Float.round(results.success_rate * 100, 2)}%")
    IO.puts("   Average time: #{results.average_time_ms}ms")

    if results.errors > 0 do
      IO.puts("\n❌ Errors encountered:")
      results.error_details
      |> Enum.each(fn error ->
        IO.puts("   • #{error.worker}: #{error.message}")
      end)
    end

    IO.puts("\n📊 Results by worker:")
    results.worker_results
    |> Enum.each(fn {worker, worker_result} ->
      success_rate = Float.round(worker_result.success_rate * 100, 2)
      IO.puts("   #{worker}: #{worker_result.successes}/#{worker_result.total} (#{success_rate}%)")
    end)
  end

  defp confirm_destruction do
    IO.gets("Are you sure you want to destroy the entire cluster? [y/N]: ")
    |> String.trim()
    |> String.downcase()
    |> case do
      "y" -> true
      "yes" -> true
      _ -> false
    end
  end

  defp format_uptime(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end
end