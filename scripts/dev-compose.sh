#!/bin/bash
# Use Podman Compose to manage local development environment

set -e

COMMAND=${1:-"help"}

case $COMMAND in
    "up"|"start")
        echo "🚀 Starting Pigeon development environment with Podman Compose..."
        echo ""
        echo "⚠️  Make sure the control node is running first:"
        echo "   ./scripts/dev-start-control.sh"
        echo ""
        read -p "Is the control node running? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Please start the control node first, then run this script again."
            exit 1
        fi

        cd containers
        if command -v podman-compose &> /dev/null; then
            podman-compose up -d
        else
            echo "⚠️  podman-compose not found, using podman directly..."
            podman build -f local-worker/Dockerfile -t pigeon/local-worker:latest ..

            # Start basic workers
            podman run -d --name pigeon-worker-1 \
                -p 8081:8080 \
                -e CONTROL_NODE_HOST=host.containers.internal \
                -e CONTROL_NODE_PORT=4040 \
                -e WORKER_ID=worker-1 \
                pigeon/local-worker:latest

            podman run -d --name pigeon-worker-2 \
                -p 8082:8080 \
                -e CONTROL_NODE_HOST=host.containers.internal \
                -e CONTROL_NODE_PORT=4040 \
                -e WORKER_ID=worker-2 \
                pigeon/local-worker:latest
        fi
        echo "✅ Workers started!"
        ;;

    "down"|"stop")
        echo "🛑 Stopping Pigeon development environment..."
        cd containers
        if command -v podman-compose &> /dev/null; then
            podman-compose down
        else
            podman stop pigeon-worker-1 pigeon-worker-2 2>/dev/null || true
            podman rm pigeon-worker-1 pigeon-worker-2 2>/dev/null || true
        fi
        echo "✅ Workers stopped!"
        ;;

    "extended")
        echo "🚀 Starting extended environment (4 workers)..."
        cd containers
        if command -v podman-compose &> /dev/null; then
            podman-compose --profile extended up -d
        else
            echo "❌ Extended mode requires podman-compose"
            echo "   Install with: pip3 install podman-compose"
            exit 1
        fi
        ;;

    "logs")
        echo "📋 Showing worker logs..."
        cd containers
        if command -v podman-compose &> /dev/null; then
            podman-compose logs -f
        else
            podman logs -f pigeon-worker-1 &
            podman logs -f pigeon-worker-2 &
            wait
        fi
        ;;

    "status")
        echo "📊 Worker status:"
        for i in 1 2; do
            port=$((8080 + i))
            if curl -s http://localhost:$port/health > /dev/null; then
                echo "✅ Worker $i: Running (port $port)"
            else
                echo "❌ Worker $i: Not responding (port $port)"
            fi
        done
        ;;

    "help"|*)
        echo "Pigeon Local Development Compose Manager"
        echo "======================================="
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  up/start    - Start worker containers"
        echo "  down/stop   - Stop worker containers"
        echo "  extended    - Start extended environment (4 workers)"
        echo "  logs        - Show worker logs"
        echo "  status      - Check worker status"
        echo "  help        - Show this help"
        echo ""
        echo "Prerequisites:"
        echo "  1. Start control node: ./scripts/dev-start-control.sh"
        echo "  2. Then run: $0 up"
        echo ""
        ;;
esac