import Config

# Configure test environment
config :pigeon,
  # Test mode to avoid starting full application
  test_mode: true,

  # AWS configuration for testing
  aws: %{
    region: "us-east-1",
    mock_mode: true,
    default_instance_type: "t3.micro",
    key_name: "test-key"
  },

  # Cluster configuration for testing
  cluster: %{
    default_nodes: 1,
    max_nodes: 3,
    communication_port: 4041,
    worker_port: 8081,
    ollama_port: 11435
  },

  # Validation configuration for testing
  validation: %{
    default_iterations: 1,
    timeout_ms: 5_000,
    max_concurrent_jobs: 2
  }

# Reduce log output during tests
config :logger, level: :warning
