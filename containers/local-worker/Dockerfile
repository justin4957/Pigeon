# Pigeon Local Worker Container
# Simulates EC2 worker nodes for local development

FROM elixir:1.15-alpine

# Install dependencies
RUN apk add --no-cache \
    curl \
    bash \
    git \
    build-base

# Set working directory
WORKDIR /app

# Create app user
RUN addgroup -g 1000 pigeon && \
    adduser -u 1000 -G pigeon -s /bin/sh -D pigeon

# Copy worker application
COPY containers/local-worker/worker_app/ /app/
COPY lib/pigeon/work/validator.ex /app/lib/pigeon/work/
COPY lib/pigeon/validators/ /app/lib/pigeon/validators/

# Set ownership
RUN chown -R pigeon:pigeon /app

# Switch to app user
USER pigeon

# Install Elixir dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix compile

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Expose port
EXPOSE 8080

# Default environment variables
ENV MIX_ENV=prod
ENV WORKER_ID=worker-local
ENV CONTROL_NODE_HOST=host.containers.internal
ENV CONTROL_NODE_PORT=4040
ENV WORKER_PORT=8080

# Start the worker
CMD ["mix", "run", "--no-halt"]