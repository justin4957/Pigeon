import Config

# Pigeon Configuration

config :pigeon,
  # AWS Configuration
  aws: %{
    region: System.get_env("AWS_DEFAULT_REGION") || "us-west-2",
    default_instance_type: "t3.medium",
    # Amazon Linux 2023
    default_ami: "ami-0c02fb55956c7d316",
    key_name: System.get_env("AWS_KEY_NAME")
  },

  # Cluster Configuration
  cluster: %{
    default_nodes: 2,
    max_nodes: 20,
    communication_port: 4040,
    worker_port: 8080,
    ollama_port: 11434
  },

  # Validation Configuration
  validation: %{
    default_iterations: 5,
    timeout_ms: 300_000,
    max_concurrent_jobs: 10
  },

  # Communication Configuration
  communication: %{
    heartbeat_interval: 30_000,
    worker_timeout: 120_000,
    retry_attempts: 3
  }

# Environment-specific configuration
if config_env() == :dev do
  config :pigeon,
    # Development overrides
    cluster: %{
      default_nodes: 1,
      communication_port: 4040
    }
end

if config_env() == :test do
  config :pigeon,
    # Test configuration - use local mock services
    aws: %{
      region: "us-east-1",
      mock_mode: true
    }
end

if config_env() == :prod do
  config :pigeon,
    # Production optimizations
    validation: %{
      default_iterations: 10,
      timeout_ms: 600_000
    }
end
