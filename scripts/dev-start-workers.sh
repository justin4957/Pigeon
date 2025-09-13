#!/bin/bash
# Start Pigeon worker containers for local development

set -e

echo "🔨 Starting Pigeon Workers for Local Development"
echo "=============================================="

# Check if Podman is available
if ! command -v podman &> /dev/null; then
    echo "❌ Podman not found. Please install Podman first."
    echo "   macOS: brew install podman"
    echo "   Linux: See https://podman.io/getting-started/installation"
    exit 1
fi

# Check if control node is running
echo "🔍 Checking if control node is running..."
if ! curl -s http://localhost:4040/health > /dev/null; then
    echo "⚠️  Control node not responding on port 4040"
    echo "   Please start the control node first: ./scripts/dev-start-control.sh"
    echo "   Or check if it's running: curl http://localhost:4040/health"
    exit 1
fi

echo "✅ Control node is running"

# Build worker image if it doesn't exist
echo "🏗️  Building worker image..."
podman build -f containers/local-worker/Dockerfile -t pigeon/local-worker:latest .

# Remove existing containers if they exist
echo "🧹 Cleaning up existing worker containers..."
podman rm -f pigeon-worker-1 pigeon-worker-2 2>/dev/null || true

# Start Worker 1
echo "🚀 Starting Worker 1 on port 8081..."
podman run -d --name pigeon-worker-1 \
    -p 8081:8080 \
    -e CONTROL_NODE_HOST=host.containers.internal \
    -e CONTROL_NODE_PORT=4040 \
    -e WORKER_ID=worker-1 \
    -e WORKER_TYPE=general \
    pigeon/local-worker:latest

# Start Worker 2
echo "🚀 Starting Worker 2 on port 8082..."
podman run -d --name pigeon-worker-2 \
    -p 8082:8080 \
    -e CONTROL_NODE_HOST=host.containers.internal \
    -e CONTROL_NODE_PORT=4040 \
    -e WORKER_ID=worker-2 \
    -e WORKER_TYPE=general \
    pigeon/local-worker:latest

# Wait a moment for containers to start
echo "⏳ Waiting for workers to start..."
sleep 5

# Check worker health
echo "🏥 Checking worker health..."
for i in 1 2; do
    port=$((8080 + i))
    if curl -s http://localhost:$port/health > /dev/null; then
        echo "✅ Worker $i is healthy (port $port)"
    else
        echo "❌ Worker $i is not responding (port $port)"
    fi
done

echo ""
echo "🎉 Workers started successfully!"
echo ""
echo "Workers are available at:"
echo "  - Worker 1: http://localhost:8081/health"
echo "  - Worker 2: http://localhost:8082/health"
echo ""
echo "To view worker logs:"
echo "  podman logs -f pigeon-worker-1"
echo "  podman logs -f pigeon-worker-2"
echo ""
echo "To test the setup, run: ./scripts/dev-test.sh"
echo "To stop workers, run: ./scripts/dev-cleanup.sh"
echo "=============================================="