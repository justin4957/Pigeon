#!/bin/bash
# Test the local Pigeon development setup

set -e

echo "🧪 Testing Pigeon Local Development Setup"
echo "========================================"

# Check if control node is running
echo "🔍 Testing control node..."
if curl -s http://localhost:4040/health > /dev/null; then
    echo "✅ Control node is running"
    curl -s http://localhost:4040/health | jq . 2>/dev/null || curl -s http://localhost:4040/health
else
    echo "❌ Control node is not responding"
    exit 1
fi

echo ""

# Check workers
echo "🔍 Testing workers..."
for i in 1 2; do
    port=$((8080 + i))
    if curl -s http://localhost:$port/health > /dev/null; then
        echo "✅ Worker $i is running (port $port)"
        worker_health=$(curl -s http://localhost:$port/health)
        echo "   Health: $worker_health"
    else
        echo "❌ Worker $i is not responding (port $port)"
    fi
done

echo ""

# Test with Elixir/IEx
echo "🧪 Running Elixir tests..."
echo "Starting IEx session for interactive testing..."
echo ""
echo "In the IEx session, try these commands:"
echo ""
echo "# 1. Check control hub status"
echo "Pigeon.Communication.Hub.get_status()"
echo ""
echo "# 2. Test G-expression validation"
echo 'work_data = "{\"g\": \"lit\", \"v\": 42}"'
echo "Pigeon.process_work(work_data, Pigeon.Validators.GExpressionValidator, workers: 2)"
echo ""
echo "# 3. Test JSON validation"
echo 'json_data = "{\"name\": \"test\", \"value\": 123}"'
echo "# Define custom validator first:"
echo 'defmodule TestValidator do'
echo '  @behaviour Pigeon.Work.Validator'
echo '  def validate(work, _), do: {:ok, Jason.decode!(work)}'
echo '  def validate_batch(items, opts), do: {:ok, Enum.map(items, &validate(&1, opts))}'
echo '  def metadata, do: %{name: "Test", version: "1.0.0", description: "Test", supported_formats: ["json"]}'
echo 'end'
echo "Pigeon.process_work(json_data, TestValidator, workers: 2)"
echo ""
echo "# 4. Exit IEx"
echo "System.halt()"
echo ""
echo "========================================"

# Start IEx for interactive testing
MIX_ENV=dev iex -S mix