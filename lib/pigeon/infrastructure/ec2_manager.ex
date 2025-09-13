defmodule Pigeon.Infrastructure.EC2Manager do
  @moduledoc """
  EC2 infrastructure management for Pigeon workers.
  """

  require Logger
  alias ExAws.EC2

  @default_ami "ami-0c02fb55956c7d316"  # Amazon Linux 2023
  @security_group_name "pigeon-workers"

  def deploy_instances(config) do
    Logger.info("Deploying #{config.node_count} instances of type #{config.instance_type}")

    with {:ok, security_group_id} <- ensure_security_group(config),
         {:ok, user_data} <- generate_user_data(config),
         {:ok, instances} <- launch_instances(config, security_group_id, user_data),
         {:ok, tagged_instances} <- tag_instances(instances, config) do
      wait_for_instances_ready(tagged_instances)
    else
      {:error, reason} ->
        Logger.error("EC2 deployment failed: #{reason}")
        {:error, reason}
    end
  end

  def terminate_instances(workers) do
    instance_ids = Enum.map(workers, & &1.instance_id)

    Logger.info("Terminating instances: #{inspect(instance_ids)}")

    case EC2.terminate_instances(instance_ids) |> ExAws.request() do
      {:ok, _response} ->
        {:ok, :terminated}

      {:error, reason} ->
        Logger.error("Failed to terminate instances: #{reason}")
        {:error, reason}
    end
  end

  def get_instance_status(instance_ids) do
    case EC2.describe_instances(instance_ids: instance_ids) |> ExAws.request() do
      {:ok, response} ->
        instances = extract_instances_from_response(response)
        {:ok, instances}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp ensure_security_group(config) do
    case find_security_group(@security_group_name) do
      {:ok, group_id} ->
        {:ok, group_id}

      {:error, :not_found} ->
        create_security_group(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_security_group(name) do
    case EC2.describe_security_groups(group_names: [name]) |> ExAws.request() do
      {:ok, %{"securityGroupInfo" => [group | _]}} ->
        {:ok, group["groupId"]}

      {:ok, %{"securityGroupInfo" => []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_security_group(config) do
    Logger.info("Creating security group: #{@security_group_name}")

    description = "Pigeon worker nodes security group"

    case EC2.create_security_group(@security_group_name, description) |> ExAws.request() do
      {:ok, %{"groupId" => group_id}} ->
        case setup_security_group_rules(group_id) do
          :ok -> {:ok, group_id}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp setup_security_group_rules(group_id) do
    # Allow SSH access (port 22)
    ssh_rule = %{
      group_id: group_id,
      ip_permissions: [
        %{
          ip_protocol: "tcp",
          from_port: 22,
          to_port: 22,
          ip_ranges: [%{cidr_ip: "0.0.0.0/0", description: "SSH access"}]
        }
      ]
    }

    # Allow Ollama API access (port 11434)
    ollama_rule = %{
      group_id: group_id,
      ip_permissions: [
        %{
          ip_protocol: "tcp",
          from_port: 11434,
          to_port: 11434,
          ip_ranges: [%{cidr_ip: "0.0.0.0/0", description: "Ollama API"}]
        }
      ]
    }

    # Allow worker communication (port 8080)
    worker_rule = %{
      group_id: group_id,
      ip_permissions: [
        %{
          ip_protocol: "tcp",
          from_port: 8080,
          to_port: 8080,
          ip_ranges: [%{cidr_ip: "0.0.0.0/0", description: "Worker API"}]
        }
      ]
    }

    with {:ok, _} <- EC2.authorize_security_group_ingress(ssh_rule) |> ExAws.request(),
         {:ok, _} <- EC2.authorize_security_group_ingress(ollama_rule) |> ExAws.request(),
         {:ok, _} <- EC2.authorize_security_group_ingress(worker_rule) |> ExAws.request() do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_user_data(config) do
    user_data = """
    #!/bin/bash

    # Update system
    yum update -y

    # Install Docker
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user

    # Install Podman
    yum install -y podman

    # Create pigeon user
    useradd -m -s /bin/bash pigeon
    usermod -a -G docker pigeon

    # Create directories
    mkdir -p /opt/pigeon/{config,logs,data}
    chown -R pigeon:pigeon /opt/pigeon

    # Download and setup Pigeon worker
    cd /opt/pigeon

    # Create worker configuration
    cat > config/worker.json << 'EOF'
    {
      "cluster_id": "#{config.cluster_id}",
      "control_node": "#{node()}",
      "worker_port": 8080,
      "ollama_port": 11434,
      "max_concurrent_jobs": 4
    }
    EOF

    # Create systemd service for Pigeon worker
    cat > /etc/systemd/system/pigeon-worker.service << 'EOF'
    [Unit]
    Description=Pigeon Worker Node
    After=docker.service
    Requires=docker.service

    [Service]
    Type=simple
    User=pigeon
    WorkingDirectory=/opt/pigeon
    ExecStart=/opt/pigeon/start-worker.sh
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    EOF

    # Create worker startup script
    cat > /opt/pigeon/start-worker.sh << 'EOF'
    #!/bin/bash

    # Start Ollama container
    podman run -d --name ollama \\
      -p 11434:11434 \\
      -v /opt/pigeon/data:/root/.ollama \\
      --restart unless-stopped \\
      ollama/ollama:latest

    # Wait for Ollama to start
    sleep 10

    # Pull CodeLlama model
    podman exec ollama ollama pull codellama:7b

    # Start Pigeon worker container
    podman run -d --name pigeon-worker \\
      -p 8080:8080 \\
      -v /opt/pigeon/config:/config \\
      -v /opt/pigeon/logs:/logs \\
      --network host \\
      --restart unless-stopped \\
      pigeon/worker:latest

    # Keep service running
    while true; do
      if ! podman ps -q --filter name=ollama | grep -q .; then
        echo "Restarting Ollama..."
        podman start ollama
      fi

      if ! podman ps -q --filter name=pigeon-worker | grep -q .; then
        echo "Restarting Pigeon worker..."
        podman start pigeon-worker
      fi

      sleep 30
    done
    EOF

    chmod +x /opt/pigeon/start-worker.sh
    chown pigeon:pigeon /opt/pigeon/start-worker.sh

    # Enable and start service
    systemctl daemon-reload
    systemctl enable pigeon-worker
    systemctl start pigeon-worker

    # Signal that instance is ready
    /opt/aws/bin/cfn-signal -e $? --stack #{config.cluster_id} --resource Instance --region #{config.region}
    """

    encoded = Base.encode64(user_data)
    {:ok, encoded}
  end

  defp launch_instances(config, security_group_id, user_data) do
    launch_params = %{
      image_id: @default_ami,
      instance_type: config.instance_type,
      key_name: config.key_name,
      security_group_ids: [security_group_id],
      user_data: user_data,
      min_count: config.node_count,
      max_count: config.node_count,
      monitoring: %{enabled: true}
    }

    case EC2.run_instances(launch_params) |> ExAws.request() do
      {:ok, response} ->
        instances = extract_instances_from_launch_response(response)
        {:ok, instances}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tag_instances(instances, config) do
    Enum.reduce_while(instances, {:ok, instances}, fn instance, {:ok, acc} ->
      tags = [
        %{key: "Name", value: "pigeon-worker-#{config.cluster_id}"},
        %{key: "PigeonCluster", value: config.cluster_id},
        %{key: "PigeonRole", value: "worker"},
        %{key: "CreatedBy", value: "pigeon-cli"}
      ]

      case EC2.create_tags([instance.instance_id], tags) |> ExAws.request() do
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp wait_for_instances_ready(instances, retries \\ 30) do
    if retries <= 0 do
      {:error, "Timeout waiting for instances"}
    else
      instance_ids = Enum.map(instances, & &1.instance_id)

      case get_instance_status(instance_ids) do
        {:ok, updated_instances} ->
          if Enum.all?(updated_instances, &(&1.status == :running)) do
            {:ok, updated_instances}
          else
            Logger.info("Waiting for instances to be ready... (#{retries} retries left)")
            :timer.sleep(10_000)
            wait_for_instances_ready(instances, retries - 1)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_instances_from_launch_response(response) do
    response["instancesSet"]
    |> Enum.map(fn instance ->
      %{
        instance_id: instance["instanceId"],
        public_ip: nil,  # Will be populated later
        private_ip: instance["privateIpAddress"],
        status: :pending
      }
    end)
  end

  defp extract_instances_from_response(response) do
    response["reservationSet"]
    |> Enum.flat_map(& &1["instancesSet"])
    |> Enum.map(fn instance ->
      %{
        instance_id: instance["instanceId"],
        public_ip: instance["ipAddress"],
        private_ip: instance["privateIpAddress"],
        status: convert_instance_state(instance["instanceState"]["name"])
      }
    end)
  end

  defp convert_instance_state("pending"), do: :pending
  defp convert_instance_state("running"), do: :running
  defp convert_instance_state("stopping"), do: :stopping
  defp convert_instance_state("stopped"), do: :stopped
  defp convert_instance_state("terminating"), do: :terminating
  defp convert_instance_state("terminated"), do: :terminated
  defp convert_instance_state(_other), do: :unknown
end