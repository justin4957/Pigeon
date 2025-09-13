#!/bin/bash
# Clean up Pigeon local development environment

set -e

echo "🧹 Cleaning up Pigeon Local Development Environment"
echo "================================================="

echo "🛑 Stopping worker containers..."
podman stop pigeon-worker-1 pigeon-worker-2 2>/dev/null || true

echo "🗑️  Removing worker containers..."
podman rm pigeon-worker-1 pigeon-worker-2 2>/dev/null || true

# Optional: Remove the worker image
read -p "🤔 Remove worker image? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing worker image..."
    podman rmi pigeon/local-worker:latest 2>/dev/null || true
fi

# Check for any remaining Pigeon containers
remaining=$(podman ps -a --filter "name=pigeon" --format "{{.Names}}" 2>/dev/null || true)
if [ -n "$remaining" ]; then
    echo "⚠️  Found remaining Pigeon containers:"
    echo "$remaining"
    read -p "🤔 Remove all remaining Pigeon containers? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$remaining" | xargs podman rm -f 2>/dev/null || true
    fi
fi

echo ""
echo "✅ Cleanup completed!"
echo ""
echo "To start fresh:"
echo "  1. Start control node: ./scripts/dev-start-control.sh"
echo "  2. Start workers: ./scripts/dev-start-workers.sh"
echo "  3. Run tests: ./scripts/dev-test.sh"
echo "================================================="