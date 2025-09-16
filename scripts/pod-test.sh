#!/bin/bash

# pod-test: Automated CI/CD Pipeline Emulation Script for Pigeon
# Emulates GitHub Actions workflow using Podman containers
# Usage: ./scripts/pod-test.sh [OPTIONS]

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPT_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
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

info() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')] ℹ️ $1${NC}"
}

header() {
    echo -e "${PURPLE}"
    echo "=================================="
    echo "$1"
    echo "=================================="
    echo -e "${NC}"
}

# Configuration variables
CONTAINER_NAME="pigeon-ci-test"
TEST_IMAGE="pigeon-test:latest"
SKIP_TESTS=false
SKIP_COMPILE=false
DEBUG=false
CLEANUP=true
TIMEOUT=1200  # 20 minutes
VERBOSE=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-compile)
                SKIP_COMPILE=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

show_help() {
    echo "Pigeon CI/CD Pipeline Emulation Script"
    echo "======================================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script emulates the CI/CD pipeline locally using Podman containers,"
    echo "allowing you to test your code changes exactly as they would run in CI."
    echo ""
    echo "Options:"
    echo "      --skip-tests     Skip running tests"
    echo "      --skip-compile   Skip compilation step"
    echo "      --debug          Enable debug mode (keeps containers running on failure)"
    echo "      --no-cleanup     Don't cleanup containers after completion"
    echo "      --timeout SEC    Set timeout in seconds (default: 1200)"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Run complete CI/CD pipeline"
    echo "  $0 --skip-tests             # Quick check without tests"
    echo "  $0 --debug --no-cleanup     # Debug mode for troubleshooting"
    echo "  $0 --verbose               # Detailed output"
    echo ""
    echo "What this script does:"
    echo "1. Build development container using Dockerfile.dev"
    echo "2. Install and compile dependencies"
    echo "3. Check code formatting"
    echo "4. Run static analysis (if available)"
    echo "5. Compile code with warnings as errors"
    echo "6. Run test suite"
    echo "7. Generate documentation (if configured)"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    header "Checking Prerequisites"

    if ! command -v podman >/dev/null 2>&1; then
        error "Podman is not installed. Please install podman."
    fi
    success "Podman found"

    if ! podman machine list --format '{{.Running}}' | grep -q true; then
        error "Podman machine is not running. Please start with: podman machine start"
    fi
    success "Podman machine is running"

    if [[ ! -f "$PROJECT_ROOT/mix.exs" ]]; then
        error "Not in a valid Elixir project directory (mix.exs not found)"
    fi
    success "Elixir project detected"
}

# Cleanup function
cleanup_containers() {
    if [[ "$CLEANUP" == true ]]; then
        log "Cleaning up containers..."
        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
        podman rmi -f "$TEST_IMAGE" 2>/dev/null || true
        success "Cleanup completed"
    else
        warn "Skipping cleanup (--no-cleanup specified)"
        info "Container name: $CONTAINER_NAME"
        info "Image name: $TEST_IMAGE"
    fi
}

# Build test container
build_test_container() {
    header "Building Test Container"

    log "Building development container..."
    cd "$PROJECT_ROOT"

    if [[ "$VERBOSE" == true ]]; then
        BUILD_ARGS="--progress=plain"
    else
        BUILD_ARGS=""
    fi

    if ! podman build $BUILD_ARGS -f containers/Dockerfile.dev -t "$TEST_IMAGE" .; then
        error "Failed to build test container"
    fi

    success "Test container built successfully"
}

# Install dependencies
install_dependencies() {
    header "Installing Dependencies"

    log "Fetching and compiling dependencies..."

    local cmd="cd /app && mix deps.get && mix deps.compile"
    if [[ "$VERBOSE" == true ]]; then
        cmd="$cmd --verbose"
    fi

    if ! podman run --rm --name "$CONTAINER_NAME-deps" \
        -v "$PROJECT_ROOT:/app:Z" \
        "$TEST_IMAGE" \
        sh -c "$cmd"; then
        error "Failed to install dependencies"
    fi

    success "Dependencies installed successfully"
}

# Check code formatting
check_formatting() {
    header "Checking Code Formatting"

    log "Running mix format --check-formatted..."

    if ! podman run --rm --name "$CONTAINER_NAME-format" \
        -v "$PROJECT_ROOT:/app:Z" \
        "$TEST_IMAGE" \
        sh -c "cd /app && mix format --check-formatted"; then
        error "Code formatting check failed. Run 'mix format' to fix."
    fi

    success "Code formatting check passed"
}

# Run static analysis
run_static_analysis() {
    header "Running Static Analysis"

    # Check if credo is available
    if podman run --rm \
        -v "$PROJECT_ROOT:/app:Z" \
        "$TEST_IMAGE" \
        sh -c "cd /app && mix deps | grep -q credo" 2>/dev/null; then

        log "Running Credo static analysis..."
        if ! podman run --rm --name "$CONTAINER_NAME-credo" \
            -v "$PROJECT_ROOT:/app:Z" \
            "$TEST_IMAGE" \
            sh -c "cd /app && mix credo --strict"; then
            warn "Static analysis found issues (non-blocking)"
        else
            success "Static analysis passed"
        fi
    else
        info "Credo not configured, skipping static analysis"
    fi
}

# Compile code
compile_code() {
    if [[ "$SKIP_COMPILE" == true ]]; then
        warn "Skipping compilation (--skip-compile specified)"
        return 0
    fi

    header "Compiling Code"

    log "Compiling with warnings as errors..."

    if ! podman run --rm --name "$CONTAINER_NAME-compile" \
        -v "$PROJECT_ROOT:/app:Z" \
        "$TEST_IMAGE" \
        sh -c "cd /app && mix compile --warnings-as-errors"; then
        error "Compilation failed with warnings or errors"
    fi

    success "Code compiled successfully"
}

# Run tests
run_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        warn "Skipping tests (--skip-tests specified)"
        return 0
    fi

    header "Running Test Suite"

    log "Running Elixir tests..."

    local test_cmd="cd /app && mix test"
    if [[ "$VERBOSE" == true ]]; then
        test_cmd="$test_cmd --trace"
    fi

    # Run tests with timeout
    if ! timeout "$TIMEOUT" podman run --rm --name "$CONTAINER_NAME-test" \
        -v "$PROJECT_ROOT:/app:Z" \
        "$TEST_IMAGE" \
        sh -c "$test_cmd"; then

        local exit_code=$?
        if [[ $exit_code == 124 ]]; then
            error "Tests timed out after $TIMEOUT seconds"
        else
            if [[ "$DEBUG" == true ]]; then
                warn "Tests failed. Debug mode enabled - container preserved."
                info "Debug with: podman run -it --rm -v $PROJECT_ROOT:/app:Z $TEST_IMAGE sh"
                return 1
            else
                error "Test suite failed"
            fi
        fi
    fi

    success "All tests passed"
}

# Generate documentation
generate_docs() {
    header "Generating Documentation"

    # Check if ex_doc is available
    if podman run --rm \
        -v "$PROJECT_ROOT:/app:Z" \
        "$TEST_IMAGE" \
        sh -c "cd /app && mix deps | grep -q ex_doc" 2>/dev/null; then

        log "Generating documentation..."
        if ! podman run --rm --name "$CONTAINER_NAME-docs" \
            -v "$PROJECT_ROOT:/app:Z" \
            "$TEST_IMAGE" \
            sh -c "cd /app && mix docs"; then
            warn "Documentation generation failed (non-blocking)"
        else
            success "Documentation generated"
        fi
    else
        info "ex_doc not configured, skipping documentation generation"
    fi
}

# Main pipeline execution
run_pipeline() {
    local start_time=$(date +%s)

    header "Starting Pigeon CI/CD Pipeline Emulation"
    info "Script version: $SCRIPT_VERSION"
    info "Project: $(basename "$PROJECT_ROOT")"
    info "Timeout: ${TIMEOUT}s"

    # Set trap for cleanup on exit
    trap cleanup_containers EXIT

    check_prerequisites
    build_test_container
    install_dependencies
    check_formatting
    run_static_analysis
    compile_code
    run_tests
    generate_docs

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    header "Pipeline Completed Successfully"
    success "Total execution time: ${duration}s"

    if [[ "$DEBUG" == false && "$CLEANUP" == true ]]; then
        log "All containers and images have been cleaned up"
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_no=$1

    error "Pipeline failed at line $line_no (exit code: $exit_code)"

    if [[ "$DEBUG" == true ]]; then
        warn "Debug mode enabled - preserving containers for inspection"
        info "Inspect with: podman run -it --rm -v $PROJECT_ROOT:/app:Z $TEST_IMAGE sh"
        CLEANUP=false
    fi

    cleanup_containers
    exit $exit_code
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Main execution
main() {
    cd "$PROJECT_ROOT"
    parse_arguments "$@"
    run_pipeline
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi