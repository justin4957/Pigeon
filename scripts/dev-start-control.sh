#!/bin/bash
# Start Pigeon control node for local development

set -e

echo "🚀 Starting Pigeon Control Node for Local Development"
echo "=================================================="

# Set environment variables for local development
export MIX_ENV=dev
export PIGEON_MODE=local_dev
export PIGEON_WORKERS=local

# Check if Elixir is available
if ! command -v elixir &> /dev/null; then
    echo "❌ Elixir not found. Please install Elixir 1.15+ first."
    exit 1
fi

# Check if mix deps are installed
if [ ! -d "deps" ]; then
    echo "📦 Installing dependencies..."
    mix deps.get
fi

echo "🔧 Compiling project..."
mix compile

echo "🌐 Starting control node on port 4040..."
echo ""
echo "Control Node will be available at:"
echo "  - Health Check: http://localhost:4040/health"
echo "  - Worker Registration: http://localhost:4040/api/worker/register"
echo ""
echo "To test the control node, run in another terminal:"
echo "  curl http://localhost:4040/health"
echo ""
echo "To start workers, run: ./scripts/dev-start-workers.sh"
echo ""
echo "Press Ctrl+C to stop the control node"
echo "=================================================="

# Start the control node with IEx for interactive development
iex -S mix run --no-halt