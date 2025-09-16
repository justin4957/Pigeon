# Pigeon Development Environment

A streamlined development environment for the Pigeon distributed work processing framework using Podman containers.

## Quick Start

```bash
# Start the complete development environment
./scripts/dev.sh start

# Start with extended workers (CPU/Memory optimized)
./scripts/dev.sh start --extended

# Check status
./scripts/dev.sh status

# Stop environment
./scripts/dev.sh stop
```

## What's New

This development setup has been enhanced with functionality inspired by modern CI/CD practices:

### 🚀 Enhanced Development Scripts

- **`./scripts/dev.sh`** - Complete environment management with automatic control node handling
- **`./scripts/pod-test.sh`** - Local CI/CD pipeline emulation for testing before commits

### 🐳 Improved Container Architecture

- **Network isolation** with dedicated `pigeon_network`
- **Volume caching** for faster rebuilds (`deps_cache`, `build_cache`)
- **Container naming** for easier management
- **Profile support** for different worker configurations

### 📊 Better Monitoring & Debugging

- Real-time status checking across all services
- Comprehensive logging with color-coded output
- Debug mode for troubleshooting failures
- Automatic health checks for all workers

## Development Workflow

### 1. Environment Setup

```bash
# Install prerequisites
brew install podman
podman machine start

# Start development environment
./scripts/dev.sh start
```

### 2. Development Loop

```bash
# Make code changes in your editor
# Test locally with CI/CD emulation
./scripts/pod-test.sh

# Quick checks without full test suite
./scripts/pod-test.sh --skip-tests

# Debug mode for troubleshooting
./scripts/pod-test.sh --debug --no-cleanup
```

### 3. Container Management

```bash
# Check environment status
./scripts/dev.sh status

# View logs from all containers
./scripts/dev.sh logs

# Restart with fresh containers
./scripts/dev.sh restart --rebuild

# Clean up everything
./scripts/dev.sh clean
```

## Available Services

### Control Node
- **Port:** 4040
- **Purpose:** Coordinates work distribution
- **Mode:** Runs on host by default (can be containerized)

### Worker Nodes

| Worker | Port | Type | Resources |
|--------|------|------|-----------|
| worker-1 | 8081 | General purpose | Default |
| worker-2 | 8082 | General purpose | Default |
| worker-cpu | 8083 | CPU-intensive | 2.0 CPUs |
| worker-memory | 8084 | Memory-intensive | 1GB RAM limit |

## Script Options

### Development Script (`./scripts/dev.sh`)

```bash
# Actions
./scripts/dev.sh start      # Start environment
./scripts/dev.sh stop       # Stop environment
./scripts/dev.sh restart    # Restart environment
./scripts/dev.sh status     # Show status
./scripts/dev.sh logs       # Show logs
./scripts/dev.sh clean      # Clean up

# Options
--extended              # Start extended workers (CPU/Memory)
--foreground, -f        # Run in foreground
--rebuild              # Force rebuild containers
--no-control           # Don't auto-start control node
```

### CI/CD Test Script (`./scripts/pod-test.sh`)

```bash
# Full pipeline
./scripts/pod-test.sh

# Quick options
./scripts/pod-test.sh --skip-tests        # Skip test suite
./scripts/pod-test.sh --skip-compile      # Skip compilation

# Debug options
./scripts/pod-test.sh --debug             # Debug mode
./scripts/pod-test.sh --no-cleanup        # Preserve containers
./scripts/pod-test.sh --verbose           # Detailed output
```

## CI/CD Pipeline Stages

The pod-test script emulates your complete CI/CD pipeline:

1. **Prerequisites Check** - Verify Podman and project setup
2. **Container Build** - Build development container
3. **Dependency Installation** - Fetch and compile dependencies
4. **Code Formatting** - Check with `mix format`
5. **Static Analysis** - Run Credo (if configured)
6. **Compilation** - Compile with warnings as errors
7. **Test Suite** - Run complete test suite
8. **Documentation** - Generate docs (if ex_doc configured)

## Architecture Improvements

### From Previous Setup
- Manual control node management
- Basic container orchestration
- Limited debugging capabilities
- No CI/CD emulation

### Enhanced Setup
- ✅ Automatic control node lifecycle management
- ✅ Comprehensive environment status monitoring
- ✅ Color-coded logging and error handling
- ✅ Local CI/CD pipeline emulation
- ✅ Debug modes for troubleshooting
- ✅ Profile-based worker configuration
- ✅ Volume caching for faster development
- ✅ Network isolation and proper container naming

## Troubleshooting

### Common Issues

**Podman machine not running:**
```bash
podman machine start
```

**Port conflicts:**
```bash
# Check what's using ports
lsof -i :4040
lsof -i :8081

# Stop conflicting processes or change ports in compose file
```

**Permission issues:**
```bash
# Ensure proper file ownership
sudo chown -R $USER:$USER .
```

**Container build failures:**
```bash
# Clean and rebuild
./scripts/dev.sh clean
./scripts/dev.sh start --rebuild
```

### Debug Mode

When tests or builds fail, use debug mode:

```bash
./scripts/pod-test.sh --debug --no-cleanup
```

This preserves containers for inspection:

```bash
# Inspect the test container
podman run -it --rm -v $(pwd):/app:Z pigeon-test:latest sh

# Check container logs
podman logs pigeon-ci-test
```

## Integration with IDEs

### VS Code

Add to `.vscode/tasks.json`:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Start Pigeon Dev",
            "type": "shell",
            "command": "./scripts/dev.sh start",
            "group": "build"
        },
        {
            "label": "Run CI Tests",
            "type": "shell",
            "command": "./scripts/pod-test.sh",
            "group": "test"
        }
    ]
}
```

### IntelliJ/Elixir Plugin

Create run configurations for:
- `./scripts/dev.sh start` (Development)
- `./scripts/pod-test.sh` (Testing)

## Contributing

When contributing to Pigeon:

1. **Before committing**: Run `./scripts/pod-test.sh` to ensure CI compatibility
2. **For debugging**: Use `./scripts/pod-test.sh --debug` to troubleshoot failures
3. **For quick checks**: Use `./scripts/pod-test.sh --skip-tests` for fast feedback

This ensures your changes work exactly as they would in the CI environment.