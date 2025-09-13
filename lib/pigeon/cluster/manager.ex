defmodule Pigeon.Cluster.Manager do
  @moduledoc """
  Cluster management for Pigeon worker nodes.
  Adapted from Grapple's distributed coordination.
  """

  use GenServer
  require Logger

  alias Pigeon.Infrastructure.EC2Manager
  alias Pigeon.Communication.Hub
  alias Pigeon.Cluster.WorkerSupervisor

  defstruct [
    :control_node,
    :cluster_id,
    :workers,
    :deployment_config,
    :cluster_status,
    :jobs
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def deploy_cluster(opts) do
    GenServer.call(__MODULE__, {:deploy_cluster, opts}, 300_000)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def scale_to(target_nodes) do
    GenServer.call(__MODULE__, {:scale_to, target_nodes}, 300_000)
  end

  def destroy_cluster do
    GenServer.call(__MODULE__, :destroy_cluster, 300_000)
  end

  def register_worker(worker_info) do
    GenServer.call(__MODULE__, {:register_worker, worker_info})
  end

  def worker_heartbeat(worker_id, status) do
    GenServer.cast(__MODULE__, {:worker_heartbeat, worker_id, status})
  end

  # GenServer Implementation

  def init(opts) do
    cluster_id = generate_cluster_id()
    control_node = node()

    state = %__MODULE__{
      control_node: control_node,
      cluster_id: cluster_id,
      workers: %{},
      deployment_config: nil,
      cluster_status: :idle,
      jobs: %{}
    }

    Logger.info("Pigeon Cluster Manager started on #{control_node}")
    {:ok, state}
  end

  def handle_call({:deploy_cluster, opts}, _from, state) do
    case state.cluster_status do
      :idle ->
        deploy_result = do_deploy_cluster(opts, state)
        handle_deployment_result(deploy_result, opts, state)

      _other ->
        {:reply, {:error, "Cluster already active"}, state}
    end
  end

  def handle_call(:get_status, _from, state) do
    case state.cluster_status do
      :idle ->
        {:reply, {:error, :no_cluster}, state}

      _active ->
        status = build_status_response(state)
        {:reply, {:ok, status}, state}
    end
  end

  def handle_call({:scale_to, target_nodes}, _from, state) do
    current_count = map_size(state.workers)

    cond do
      target_nodes > current_count ->
        # Scale up
        scale_up_result = scale_up(target_nodes - current_count, state)
        handle_scale_result(scale_up_result, state)

      target_nodes < current_count ->
        # Scale down
        scale_down_result = scale_down(current_count - target_nodes, state)
        handle_scale_result(scale_down_result, state)

      true ->
        # No change needed
        result = %{added: 0, removed: 0, total: current_count}
        {:reply, {:ok, result}, state}
    end
  end

  def handle_call(:destroy_cluster, _from, state) do
    case destroy_all_workers(state) do
      {:ok, _result} ->
        new_state = %{state |
          workers: %{},
          cluster_status: :idle,
          deployment_config: nil,
          jobs: %{}
        }
        {:reply, {:ok, :destroyed}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:register_worker, worker_info}, _from, state) do
    worker_id = worker_info.instance_id
    updated_worker = Map.put(worker_info, :registered_at, System.system_time(:second))

    new_workers = Map.put(state.workers, worker_id, updated_worker)
    new_state = %{state | workers: new_workers}

    Logger.info("Worker registered: #{worker_id}")
    {:reply, {:ok, :registered}, new_state}
  end

  def handle_cast({:worker_heartbeat, worker_id, status}, state) do
    case Map.get(state.workers, worker_id) do
      nil ->
        Logger.warn("Heartbeat from unknown worker: #{worker_id}")
        {:noreply, state}

      worker ->
        updated_worker = %{worker |
          status: status,
          last_heartbeat: System.system_time(:second)
        }

        new_workers = Map.put(state.workers, worker_id, updated_worker)
        new_state = %{state | workers: new_workers}

        {:noreply, new_state}
    end
  end

  # Private Functions

  defp do_deploy_cluster(opts, state) do
    Logger.info("Deploying cluster with #{opts.nodes} nodes")

    deployment_config = %{
      node_count: opts.nodes,
      instance_type: opts.instance_type,
      region: opts.region,
      key_name: opts.key_name,
      cluster_id: state.cluster_id
    }

    case EC2Manager.deploy_instances(deployment_config) do
      {:ok, instances} ->
        # Wait for instances to be ready and register
        wait_for_workers(instances, deployment_config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_deployment_result({:ok, workers}, opts, state) do
    new_state = %{state |
      workers: workers,
      deployment_config: opts,
      cluster_status: :active
    }

    cluster_info = %{
      control_node: state.control_node,
      workers: Map.values(workers)
    }

    {:reply, {:ok, cluster_info}, new_state}
  end

  defp handle_deployment_result({:error, reason}, _opts, state) do
    {:reply, {:error, reason}, state}
  end

  defp wait_for_workers(instances, config) do
    Logger.info("Waiting for #{length(instances)} workers to come online...")

    # Start worker registration timeout
    timeout = 600_000  # 10 minutes

    workers = instances
    |> Enum.reduce(%{}, fn instance, acc ->
      worker_info = %{
        instance_id: instance.instance_id,
        public_ip: instance.public_ip,
        private_ip: instance.private_ip,
        status: :starting,
        current_jobs: 0,
        max_jobs: 4,
        uptime: 0
      }
      Map.put(acc, instance.instance_id, worker_info)
    end)

    {:ok, workers}
  end

  defp scale_up(additional_nodes, state) do
    deployment_config = Map.put(state.deployment_config, :node_count, additional_nodes)

    case EC2Manager.deploy_instances(deployment_config) do
      {:ok, instances} ->
        case wait_for_workers(instances, deployment_config) do
          {:ok, new_workers} ->
            {:ok, %{added: additional_nodes, removed: 0, new_workers: new_workers}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scale_down(nodes_to_remove, state) do
    workers_to_remove = state.workers
    |> Map.values()
    |> Enum.take(nodes_to_remove)

    case EC2Manager.terminate_instances(workers_to_remove) do
      {:ok, _result} ->
        remaining_workers = state.workers
        |> Enum.reject(fn {_id, worker} ->
          Enum.any?(workers_to_remove, &(&1.instance_id == worker.instance_id))
        end)
        |> Map.new()

        {:ok, %{added: 0, removed: nodes_to_remove, remaining_workers: remaining_workers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_scale_result({:ok, result}, state) do
    new_workers = cond do
      Map.has_key?(result, :new_workers) ->
        Map.merge(state.workers, result.new_workers)

      Map.has_key?(result, :remaining_workers) ->
        result.remaining_workers

      true ->
        state.workers
    end

    new_state = %{state | workers: new_workers}
    result_summary = Map.take(result, [:added, :removed]) |> Map.put(:total, map_size(new_workers))

    {:reply, {:ok, result_summary}, new_state}
  end

  defp handle_scale_result({:error, reason}, state) do
    {:reply, {:error, reason}, state}
  end

  defp destroy_all_workers(state) do
    worker_list = Map.values(state.workers)

    case EC2Manager.terminate_instances(worker_list) do
      {:ok, result} ->
        Logger.info("All workers destroyed successfully")
        {:ok, result}

      {:error, reason} ->
        Logger.error("Failed to destroy workers: #{reason}")
        {:error, reason}
    end
  end

  defp build_status_response(state) do
    workers = Map.values(state.workers)
    active_workers = Enum.count(workers, &(&1.status == :active))
    total_jobs = Enum.sum(Enum.map(workers, &Map.get(&1, :current_jobs, 0)))

    %{
      cluster_status: state.cluster_status,
      active_workers: active_workers,
      total_workers: length(workers),
      active_jobs: total_jobs,
      completed_jobs: map_size(state.jobs),
      workers: workers
    }
  end

  defp generate_cluster_id do
    "pigeon-" <>
      (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end