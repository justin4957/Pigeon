# Pigeon Worker Container
FROM elixir:1.15-alpine

# Install dependencies
RUN apk add --no-cache \
    curl \
    git \
    build-base \
    openssl-dev \
    ca-certificates

# Create app directory
WORKDIR /app

# Copy application files
COPY lib ./lib
COPY config ./config
COPY mix.exs mix.lock ./

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies
RUN mix deps.get

# Compile the application
RUN mix compile

# Create non-root user
RUN addgroup -S pigeon && adduser -S pigeon -G pigeon
RUN chown -R pigeon:pigeon /app
USER pigeon

# Expose ports
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start the worker
CMD ["mix", "run", "--no-halt", "-e", "Pigeon.Worker.start()"]