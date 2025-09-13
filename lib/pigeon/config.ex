defmodule Pigeon.Config do
  @moduledoc """
  Configuration management for Pigeon.
  """

  def ensure_aws_config do
    unless System.get_env("AWS_ACCESS_KEY_ID") do
      raise """
      AWS credentials not configured. Please set:

      export AWS_ACCESS_KEY_ID=your_access_key
      export AWS_SECRET_ACCESS_KEY=your_secret_key
      export AWS_DEFAULT_REGION=us-west-2

      Or configure AWS CLI with: aws configure
      """
    end
  end

  def get_default_config do
    %{
      aws: %{
        region: System.get_env("AWS_DEFAULT_REGION") || "us-west-2",
        instance_type: "t3.medium",
        ami_id: "ami-0c02fb55956c7d316"  # Amazon Linux 2023
      },
      cluster: %{
        default_node_count: 2,
        max_nodes: 10,
        communication_port: 4040
      },
      validation: %{
        default_iterations: 5,
        timeout_seconds: 300
      }
    }
  end
end