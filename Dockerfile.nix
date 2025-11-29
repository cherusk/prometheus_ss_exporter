# Nix-based Dockerfile for Prometheus Socket Statistics Exporter
# Single comprehensive file that builds everything with Nix
# REQUIRES: VERSION argument must be provided

FROM nixos/nix:2.19.2

# VERSION argument is required - fail if not provided
ARG VERSION
RUN if [ -z "$VERSION" ]; then echo "ERROR: VERSION argument is required" && exit 1; fi

# Set up Nix channels
RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs && \
    nix-channel --update

# Copy source files first
COPY . ./

# Install required packages and build
RUN nix-env -iA nixpkgs.nim nixpkgs.nimble nixpkgs.gcc nixpkgs.python3 nixpkgs.python3Packages.pyroute2 nixpkgs.bash nixpkgs.coreutils nixpkgs.wget nixpkgs.procps nixpkgs.shadow nixpkgs.cacert

# Create proper SSL certificate symlinks like NixOS
RUN mkdir -p /etc/ssl/certs && \
    mkdir -p /etc/static/ssl/certs && \
    CERT_PATH=$(find /nix/store -name "ca-bundle.crt" | head -1) && \
    CERT_PATH_ALT=$(find /nix/store -name "ca-certificates.crt" | head -1) && \
    cp "$CERT_PATH" /etc/static/ssl/certs/ca-bundle.crt && \
    cp "$CERT_PATH_ALT" /etc/static/ssl/certs/ca-certificates.crt 2>/dev/null || cp "$CERT_PATH" /etc/static/ssl/certs/ca-certificates.crt && \
    ln -sf /etc/static/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt && \
    ln -sf /etc/static/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt && \
    echo "Created SSL certificate symlinks matching NixOS"

# Use nimble to install dependencies and build
RUN export HOME=$TMPDIR && \
    export BUILD_VERSION="$VERSION" && \
    echo "Building version: $BUILD_VERSION" && \
    echo "SSL certificates setup:" && \
    ls -la /etc/ssl/certs/ && \
    # Now nimble should work with proper SSL setup
    nimble refresh && \
    nimble search metrics && \
    nimble install -y && \
    nimble build -v -d:release -d:metrics --threads:on -d:version="$BUILD_VERSION" --verbose || \
    nim c -d:release -d:metrics --threads:on -d:version="$BUILD_VERSION" src/prometheus_ss_exporter.nim

# Create app directory and install
RUN mkdir -p /app/bin && \
    cp src/prometheus_ss_exporter /app/bin/ && \
    chmod +x /app/bin/prometheus_ss_exporter && \
    echo "Binary copied successfully:" && \
    ls -la /app/bin/

WORKDIR /app

# Expose port
EXPOSE 8020

# Environment variables
ENV PATH=/app/bin:/bin:/usr/bin

# Run the application
ENTRYPOINT ["./bin/prometheus_ss_exporter"]
CMD ["--port", "8020", "--config", "config.yml"]