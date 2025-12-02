# Nix-based Dockerfile for Prometheus Socket Statistics Exporter
# Optimized build using Nix package manager with caching

FROM nixos/nix:2.19.2

# VERSION argument is required - provide default for development
ARG VERSION=dev-build
RUN if [ -z "$VERSION" ]; then echo "ERROR: VERSION argument is required" && exit 1; fi

# Set up Nix channels with latest stable package set
RUN nix-channel --add https://nixos.org/channels/nixos-25.05 nixpkgs && \
    nix-channel --update

# Copy source files
COPY . ./

# Install development tools
RUN nix-env -iA nixpkgs.nim nixpkgs.nimble nixpkgs.gcc

# Install Python with packages using your NixOS pattern
RUN echo 'let pkgs = import <nixpkgs> {}; in { python-env = pkgs.python312.withPackages (pythonPackages: with pkgs.python312Packages; [ pyroute2 psutil ]); }' > /tmp/python-env.nix && \
    nix-env -if /tmp/python-env.nix -iA python-env && \
    rm /tmp/python-env.nix

# Setup SSL certificates for Python modules
RUN mkdir -p /etc/ssl/certs && \
    CERT_BUNDLE=$(find /nix/store -name "ca-bundle.crt" | head -1) && \
    if [ -n "$CERT_BUNDLE" ]; then \
        ln -sf "$CERT_BUNDLE" /etc/ssl/certs/ca-bundle.crt && \
        ln -sf "$CERT_BUNDLE" /etc/ssl/certs/ca-certificates.crt && \
        echo "SSL certificates configured"; \
    else \
        echo "Warning: SSL certificates not found"; \
    fi

# Build the application with nimble
RUN export HOME=$TMPDIR && \
    export BUILD_VERSION="$VERSION" && \
    echo "Building Prometheus Socket Statistics Exporter version: $BUILD_VERSION" && \
    # Refresh package index and install dependencies
    nimble refresh -y && \
    # Install project dependencies
    nimble install -y --depsOnly || \
    # Fallback: install required packages manually if nimble fails
    (nimble search metrics && nimble install -y metrics chronos yaml) && \
    # Build the application
    nimble build -v -d:release -d:metrics --threads:on -d:version="$BUILD_VERSION" || \
    # Fallback compilation using nim compiler directly
    nim c -d:release -d:metrics --threads:on -d:version="$BUILD_VERSION" src/prometheus_ss_exporter.nim

# Find and install the compiled binary
RUN echo "Looking for compiled binary..." && \
    find . -name "prometheus_ss_exporter" -type f 2>/dev/null || echo "Binary not found in current directory" && \
    BIN_LOCATION=$(find . -name "prometheus_ss_exporter" -type f 2>/dev/null | head -1) && \
    if [ -n "$BIN_LOCATION" ]; then \
        echo "Found binary at: $BIN_LOCATION" && \
        mkdir -p /app/bin && \
        cp "$BIN_LOCATION" /app/bin/prometheus_ss_exporter && \
        chmod +x /app/bin/prometheus_ss_exporter && \
        echo "✅ Binary built and copied successfully" && \
        ls -la /app/bin/; \
    else \
        echo "❌ Build failed - no binary found. Searching for any .nim files..." && \
        find . -name "*.nim" | head -5 && \
        echo "Checking for bin directory..." && \
        ls -la bin/ 2>/dev/null || echo "No bin directory found"; \
        exit 1; \
    fi

WORKDIR /app

# Expose port
EXPOSE 8020

# Environment variables for proper Nix environment
ENV PATH="/nix/var/nix/profiles/default/bin:$PATH"
ENV SSL_CERT_FILE="/etc/ssl/certs/ca-bundle.crt"

# Run the application
ENTRYPOINT ["./bin/prometheus_ss_exporter"]
CMD ["--port", "8020", "--config", "config.yml"]
