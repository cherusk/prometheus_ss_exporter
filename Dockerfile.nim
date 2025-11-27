# Multi-stage build for Nim-based Prometheus Socket Statistics Exporter
FROM nimlang/nim:2.2.0 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    python3-pip \
    gcc \
    libc6-dev \
    linux-libc-dev \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for ss2 functionality
RUN apt-get update && apt-get install -y python3-pyroute2 && apt-get clean

# Create app directory
WORKDIR /app

# Copy nimble package file
COPY ss_exporter.nimble ./

# Install Nim dependencies
RUN nimble install -y -d

# Copy source code
COPY src/ ./src/
COPY prometheus_ss_exporter/ ./prometheus_ss_exporter/

# Build the application
RUN nimble build -d:release -d:metrics --gc:arc

# Final stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    procps \
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Python ss2 dependencies
RUN apt-get update && apt-get install -y python3-pyroute2 && apt-get clean

# Create app user
RUN groupadd -g 1000 ss_exporter && \
    useradd -u 1000 -g ss_exporter -s /bin/bash ss_exporter

# Create app directory
WORKDIR /app

# Copy binary and Python modules
COPY --from=builder /app/prometheus_ss_exporter.out ./prometheus_ss_exporter

# Set ownership
RUN chown -R ss_exporter:ss_exporter /app

# Switch to non-root user
USER ss_exporter

# Expose port
EXPOSE 8020

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8020/health || exit 1

# Run the application
ENTRYPOINT ["./prometheus_ss_exporter"]
CMD ["--port", "8020", "--config", "config.yml"]