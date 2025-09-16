#!/bin/bash

# Pigeon Development Environment Script
# Streamlined local development with Podman containers
# Inspired by Delphi project deployment practices

set -e

# Configuration
PROJECT_NAME="pigeon-dev"
COMPOSE_FILE="containers/podman-compose.yml"
CONTROL_NODE_PORT=4040
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ❌ ERROR: $1${NC}"
    exit 1
}

header() {
    echo -e "${PURPLE}"
    echo "=================================="
    echo "$1"
    echo "=================================="
    echo -e "${NC}"
}

# Check for available compose commands (prefer podman-compose)
detect_compose_command() {
    if command -v podman-compose >/dev/null 2>&1; then
        COMPOSE_CMD="podman-compose"
        SUPPORTS_PROFILES=true
        log "Using Podman Compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        SUPPORTS_PROFILES=true
        log "Using Docker Compose (v2)"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        SUPPORTS_PROFILES=false
        log "Using Docker Compose (legacy - profiles not supported)"
    else
        error "No compose command found. Please install podman-compose or Docker Compose."
    fi
}

# Check if control node is running
check_control_node() {
    if ! curl -s http://localhost:$CONTROL_NODE_PORT/health >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Start control node if not running
start_control_node() {
    if check_control_node; then
        log "Control node already running on port $CONTROL_NODE_PORT"
        return 0
    fi

    log "Starting control node..."
    cd "$PROJECT_ROOT"

    # Start control node in background
    nohup mix run --no-halt > control_node.log 2>&1 &
    CONTROL_PID=$!
    echo $CONTROL_PID > control_node.pid

    # Wait for control node to be ready
    log "Waiting for control node to start..."
    for i in {1..30}; do
        if check_control_node; then
            success "Control node started on port $CONTROL_NODE_PORT"
            return 0
        fi
        sleep 1
    done

    error "Control node failed to start within 30 seconds"
}

# Stop control node
stop_control_node() {
    if [[ -f "$PROJECT_ROOT/control_node.pid" ]]; then
        local pid=$(cat "$PROJECT_ROOT/control_node.pid")
        if kill -0 $pid 2>/dev/null; then
            log "Stopping control node (PID: $pid)..."
            kill $pid
            rm -f "$PROJECT_ROOT/control_node.pid"
            success "Control node stopped"
        else
            warn "Control node PID file exists but process not running"
            rm -f "$PROJECT_ROOT/control_node.pid"
        fi
    else
        warn "No control node PID file found"
    fi
}

# Show worker status
show_status() {
    header "Pigeon Development Environment Status"

    # Control node status
    if check_control_node; then
        success "Control Node: Running (port $CONTROL_NODE_PORT)"
    else
        error "Control Node: Not responding (port $CONTROL_NODE_PORT)"
    fi

    # Worker status
    echo ""
    log "Worker Status:"
    local workers_running=0
    for port in 8081 8082 8083 8084; do
        local worker_num=$((port - 8080))
        if curl -s http://localhost:$port/health >/dev/null 2>&1; then
            success "Worker $worker_num: Running (port $port)"
            workers_running=$((workers_running + 1))
        else
            warn "Worker $worker_num: Not responding (port $port)"
        fi
    done

    echo ""
    log "Summary: $workers_running workers running"
}

# Parse command line arguments
parse_arguments() {
    INCLUDE_EXTENDED=false
    DETACHED=true
    REBUILD=false
    START_CONTROL=true
    SHOW_HELP=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --extended)
                INCLUDE_EXTENDED=true
                shift
                ;;
            --foreground|-f)
                DETACHED=false
                shift
                ;;
            --rebuild)
                REBUILD=true
                shift
                ;;
            --no-control)
                START_CONTROL=false
                shift
                ;;
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            start)
                ACTION="start"
                shift
                ;;
            stop)
                ACTION="stop"
                shift
                ;;
            restart)
                ACTION="restart"
                shift
                ;;
            status)
                ACTION="status"
                shift
                ;;
            logs)
                ACTION="logs"
                shift
                ;;
            clean)
                ACTION="clean"
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    if [[ "$SHOW_HELP" == true ]] || [[ -z "${ACTION:-}" ]]; then
        show_help
        exit 0
    fi
}

show_help() {
    echo "Pigeon Development Environment Manager"
    echo "====================================="
    echo ""
    echo "Usage: $0 <action> [OPTIONS]"
    echo ""
    echo "Actions:"
    echo "  start       Start the development environment"
    echo "  stop        Stop the development environment"
    echo "  restart     Restart the development environment"
    echo "  status      Show environment status"
    echo "  logs        Show container logs"
    echo "  clean       Clean up containers and images"
    echo ""
    echo "Options:"
    echo "      --extended      Start extended environment (4 workers)"
    echo "  -f, --foreground    Run in foreground mode (default: detached)"
    echo "      --rebuild       Force rebuild of images"
    echo "      --no-control    Don't start control node automatically"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start basic development environment"
    echo "  $0 start --extended         # Start with all worker types"
    echo "  $0 start --rebuild          # Rebuild containers before starting"
    echo "  $0 stop                     # Stop all services"
    echo "  $0 status                   # Check service status"
    echo "  $0 logs                     # Show container logs"
}

start_environment() {
    header "Starting Pigeon Development Environment"

    detect_compose_command

    # Start control node if requested
    if [[ "$START_CONTROL" == true ]]; then
        start_control_node
    fi

    # Change to containers directory
    cd "$PROJECT_ROOT/containers"

    # Prepare compose arguments
    COMPOSE_ARGS=()

    if [[ "$INCLUDE_EXTENDED" == true ]]; then
        if [[ "$SUPPORTS_PROFILES" == true ]]; then
            COMPOSE_ARGS+=(--profile extended)
            log "Including extended worker profile"
        else
            warn "Profiles not supported with legacy docker-compose. Extended mode unavailable."
        fi
    fi

    if [[ "$REBUILD" == true ]]; then
        COMPOSE_ARGS+=(--build)
        log "Forcing image rebuild"
    fi

    if [[ "$DETACHED" == true ]]; then
        COMPOSE_ARGS+=(-d)
        log "Starting in detached mode"
    else
        log "Starting in foreground mode (Ctrl+C to stop)"
    fi

    # Start services
    log "Starting worker containers..."
    if ! $COMPOSE_CMD -p $PROJECT_NAME up "${COMPOSE_ARGS[@]}"; then
        error "Failed to start development environment. Check the logs above for details."
    fi

    if [[ "$DETACHED" == true ]]; then
        success "Development environment started"
        echo ""
        log "Use these commands to manage the environment:"
        log "  $0 status     - Check service status"
        log "  $0 logs       - View container logs"
        log "  $0 stop       - Stop the environment"
    else
        success "Development environment stopped"
    fi
}

stop_environment() {
    header "Stopping Pigeon Development Environment"

    detect_compose_command

    # Stop containers
    cd "$PROJECT_ROOT/containers"
    log "Stopping worker containers..."
    $COMPOSE_CMD -p $PROJECT_NAME down || warn "Some containers may not have been running"

    # Stop control node
    stop_control_node

    success "Development environment stopped"
}

restart_environment() {
    header "Restarting Pigeon Development Environment"
    stop_environment
    echo ""
    start_environment
}

show_logs() {
    header "Container Logs"
    detect_compose_command
    cd "$PROJECT_ROOT/containers"

    if [[ "$SUPPORTS_PROFILES" == true ]]; then
        $COMPOSE_CMD -p $PROJECT_NAME logs -f
    else
        $COMPOSE_CMD -p $PROJECT_NAME logs -f
    fi
}

clean_environment() {
    header "Cleaning Pigeon Development Environment"

    warn "This will remove all containers, images, and data!"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled"
        exit 0
    fi

    detect_compose_command

    # Stop and remove everything
    cd "$PROJECT_ROOT/containers"
    log "Removing containers and networks..."
    $COMPOSE_CMD -p $PROJECT_NAME down --rmi all --volumes --remove-orphans || true

    # Stop control node
    stop_control_node

    # Clean up local files
    cd "$PROJECT_ROOT"
    rm -f control_node.log control_node.pid

    success "Environment cleaned"
}

# Main execution
main() {
    parse_arguments "$@"

    case "${ACTION}" in
        start)
            start_environment
            ;;
        stop)
            stop_environment
            ;;
        restart)
            restart_environment
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        clean)
            clean_environment
            ;;
        *)
            error "Unknown action: ${ACTION}"
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi