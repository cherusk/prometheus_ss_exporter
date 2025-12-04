#!/bin/bash
#
# Production-ready Nix container build system
# Usage: ./build-container-nix.sh [OPTIONS]
#
# This script builds optimized container images using isolated Nix builder containers
# to bypass host Nix daemon limitations and achieve minimal image sizes.
#
# OPTIONS:
#   -v, --version VERSION     Build version tag (default: auto-detect from git)
#   -t, --tag TAG             Docker image tag (default: auto-generate)
#   -n, --name IMAGE_NAME      Container image name (default: auto-detect)
#   -b, --builder TAG         Custom builder container tag (default: generate)
#   -f, --file FILE           Nix file to use (default: default-container.nix)
#   -o, --output FILE         Output tarball path (default: auto-generate)
#   -c, --cores NUM           Number of CPU cores for build (default: auto)
#   --no-cache                Force rebuild without cache
#   --no-clean               Skip builder container cleanup
#   --dry-run                Show what would be executed without running
#   -q, --quiet              Minimal output
#   -h, --help               Show this help message
#
# EXAMPLES:
#   ./build-container-nix.sh                    # Auto-detect all settings
#   ./build-container-nix.sh -v 3.2.0          # Specify version
#   ./build-container-nix.sh -t my-tag        # Custom tag
#   ./build-container-nix.sh --test-only      # Test build only
#   VERSION=3.2.0 ./build-container-nix.sh    # Environment variable
#
# ENVIRONMENT VARIABLES:
#   VERSION       Build version (overrides -v)
#   IMAGE_NAME    Container name (overrides -n)
#   BUILDER_TAG   Builder container tag (overrides -b)
#   NIX_FILE      Nix file to use (overrides -f)
#
# CI/CD INTEGRATION:
#   The script is designed to work seamlessly with GitHub Actions and other CI/CD systems.
#   It automatically detects CI environments and adjusts behavior accordingly.
#

set -euo pipefail

# Default values
DEFAULT_NIX_FILE="default.nix"

# Color codes for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' NC=''
fi

# Logging functions
log_info() { [[ "${QUIET:-0}" != "1" ]] && echo -e "${BLUE}ℹ️  $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✅ $1${NC}" >&2; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}" >&2; }
log_error() { echo -e "${RED}❌ $1${NC}" >&2; }
log_header() { echo -e "${PURPLE}🏗️  $1${NC}" >&2; }
log_step() { [[ "${QUIET:-0}" != "1" ]] && echo -e "${CYAN}📦 $1${NC}" >&2; }

# Parse command line arguments
parse_args() {
    VERSION="${VERSION:-}"
    TAG="${TAG:-}"
    IMAGE_NAME="${IMAGE_NAME:-}"
    BUILDER_TAG="${BUILDER_TAG:-}"
    NIX_FILE="${NIX_FILE:-$DEFAULT_NIX_FILE}"
    OUTPUT_FILE="${OUTPUT_FILE:-}"
    CORES="${CORES:-}"
    NO_CACHE="false"
    NO_CLEAN="false"
    DRY_RUN="false"
    QUIET="${QUIET:-0}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            -n|--name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            -b|--builder)
                BUILDER_TAG="$2"
                shift 2
                ;;
            -f|--file)
                NIX_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -c|--cores)
                CORES="$2"
                shift 2
                ;;
            --no-cache)
                NO_CACHE="true"
                shift
                ;;
            --no-clean)
                NO_CLEAN="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -q|--quiet)
                QUIET="1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << 'EOF'
Production-ready Nix container build system

USAGE:
    ./build-container-nix.sh [OPTIONS]

REQUIRED OPTIONS:
    -v, --version VERSION     Build version tag (required)
    -n, --name IMAGE_NAME      Container image name (required)

OPTIONAL OPTIONS:
    -t, --tag TAG             Docker image tag (default: VERSION-nix-minimal)
    -b, --builder TAG         Custom builder container tag (default: IMAGE_NAME-builder:VERSION)
    -f, --file FILE           Nix file to use (default: default.nix)
    -o, --output FILE         Output tarball path (default: IMAGE_NAME-VERSION-nix-minimal.tar.gz)
    -c, --cores NUM           Number of CPU cores for build (default: auto-detect)
    --no-cache                Force rebuild without cache
    --no-clean               Skip builder container cleanup
    --dry-run                Show what would be executed without running
    -q, --quiet              Minimal output
    -h, --help               Show this help message

EXAMPLES:
    VERSION=3.2.0 IMAGE_NAME=my-app ./build-container-nix.sh
    ./build-container-nix.sh -v 3.2.0 -n my-app -t custom-tag
    ./build-container-nix.sh --version 3.2.0 --name my-app --dry-run

ENVIRONMENT VARIABLES:
    VERSION       Build version (required)
    IMAGE_NAME    Container name (required)
    TAG           Docker image tag (overrides -t)
    BUILDER_TAG   Builder container tag (overrides -b)
    NIX_FILE      Nix file to use (overrides -f)
    OUTPUT_FILE   Output tarball path (overrides -o)
    CORES         Number of CPU cores (overrides -c)
    QUIET         Minimal output (set to 1, overrides -q)
EOF
}

# Resolve parameters from environment variables and set required defaults
resolve_parameters() {
    log_step "Resolving build parameters..."
    
    # Check required parameters
    if [[ -z "$VERSION" ]]; then
        log_error "VERSION is required. Set via environment variable or -v/--version option"
        exit 1
    fi
    
    if [[ -z "$IMAGE_NAME" ]]; then
        log_error "IMAGE_NAME is required. Set via environment variable or -n/--name option"
        exit 1
    fi
    
    # Set optional parameters with defaults
    if [[ -z "$TAG" ]]; then
        TAG="$VERSION"
    fi
    
    if [[ -z "$BUILDER_TAG" ]]; then
        BUILDER_TAG="$IMAGE_NAME-builder:$VERSION"
    fi
    
    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$IMAGE_NAME-$VERSION.tar.gz"
    fi
    
    if [[ -z "$CORES" ]]; then
        if command -v nproc >/dev/null 2>&1; then
            CORES=$(nproc)
        else
            CORES="1"
        fi
    fi
    
    # Construct full image name
    FULL_IMAGE_NAME="$IMAGE_NAME:$TAG"
    
    log_info "Version: $VERSION"
    log_info "Image: $FULL_IMAGE_NAME"
    log_info "Cores: $CORES"
}

# Validate inputs and environment
validate_inputs() {
    log_step "Validating inputs..."
    
    # Check required files
    if [[ ! -f "$NIX_FILE" ]]; then
        log_error "Nix file not found: $NIX_FILE"
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required but not found"
        exit 1
    fi
    
    # Validate version format
    if [[ ! "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid version format: $VERSION"
        exit 1
    fi
    
    # Validate tag format
    if [[ ! "$TAG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid tag format: $TAG"
        exit 1
    fi
    
    # Validate image name format
    if [[ ! "$IMAGE_NAME" =~ ^[a-z0-9._/-]+$ ]]; then
        log_error "Invalid image name format: $IMAGE_NAME"
        exit 1
    fi
    
    # Check available disk space (basic check)
    AVAILABLE_SPACE=$(df . | awk 'NR==2 {print $4}')
    if [[ "$AVAILABLE_SPACE" -lt 1048576 ]]; then  # 1GB in KB
        log_warning "Low disk space available (${AVAILABLE_SPACE}KB). Build may fail."
    fi
    
    log_success "Input validation passed"
}

# Validate builder Dockerfile exists
validate_builder_dockerfile() {
    local builder_dockerfile="Dockerfile.nix-builder"
    
    if [[ ! -f "$builder_dockerfile" ]]; then
        log_error "Builder Dockerfile not found: $builder_dockerfile"
        exit 1
    fi
    
    echo "$builder_dockerfile"
}

# Execute the build process
execute_build() {
    log_header "Starting Nix container build process"
    
    local builder_dockerfile
    builder_dockerfile=$(validate_builder_dockerfile)
    
    log_step "Building builder container using external Dockerfile: $builder_dockerfile"
    
    if [[ "$DRY_RUN" = "true" ]]; then
        log_info "[DRY-RUN] Would build builder container with:"
        log_info "  Dockerfile: $builder_dockerfile"
        log_info "  Tag: $BUILDER_TAG"
        log_info "  Nix file: $NIX_FILE"
        log_info "  Source mount: /source"
        log_info "  Version: $VERSION"
        return 0
    fi
    
    # Build the builder container with cache optimization
    local build_args=(
        --build-arg "VERSION=$VERSION"
        --build-arg "BUILD_CORES=$CORES"
        --build-arg "NIX_FILE=$NIX_FILE"
    )
    
    if [[ "$NO_CACHE" = "true" ]]; then
        build_args+=(--no-cache)
    fi
    
    # Create empty context directory for builder build
    local empty_context="/tmp/nix-builder-context-$$"
    mkdir -p "$empty_context"
    
    docker build "${build_args[@]}" \
        -f "$builder_dockerfile" \
        -t "$BUILDER_TAG" \
        "$empty_context" || {
        rm -rf "$empty_context"
        log_error "Builder container build failed"
        exit 1
    }
    
    # Cleanup empty context
    rm -rf "$empty_context"
    
    log_success "Builder container built successfully"
    
    # Run the build with mounted source
    log_step "Running Nix build with mounted source..."
    
    docker run --rm \
        -v "$(pwd):/source" \
        -v "$(pwd):/output" \
        -e "VERSION=$VERSION" \
        -e "IMAGE_NAME=$IMAGE_NAME" \
        -e "BUILD_CORES=$CORES" \
        -e "NIX_FILE=/source/$NIX_FILE" \
        -e "CI_ENV=false" \
        -e "NO_CACHE=$NO_CACHE" \
        "$BUILDER_TAG" \
        sh -c "
            nix-build \$NIX_FILE -A containerImage \
                --option sandbox false \
                --cores \$BUILD_CORES \
                --argstr version \"\$VERSION\" \
                --argstr imageName \"\$IMAGE_NAME\" \
                ${NO_CACHE:+--no-build-output} && \
            cp result /output/$OUTPUT_FILE
        " || {
        log_error "Build failed"
        exit 1
    }
    
    # Load the built Docker image
    log_step "Loading optimized Docker image..."
    docker load < "$OUTPUT_FILE" || {
        log_error "Failed to load Docker image from: $OUTPUT_FILE"
        exit 1
    }
    
    # Tag the image with the full name if different
    local loaded_image="$IMAGE_NAME:$TAG"
    if [[ "$FULL_IMAGE_NAME" != "$loaded_image" ]]; then
        docker tag "$loaded_image" "$FULL_IMAGE_NAME" || {
            log_warning "Failed to tag image as $FULL_IMAGE_NAME"
        }
    fi
    
    log_success "Build process completed successfully"
}

# Show build summary
show_summary() {
    echo ""
    log_header "🎉 BUILD SUMMARY"
    echo "==================="
    echo "✅ Version: $VERSION"
    echo "✅ Image: $FULL_IMAGE_NAME"
    echo "✅ Output: $OUTPUT_FILE"
    echo "✅ Size: $(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "unknown")"
    echo ""
    
    # Show next steps
    echo "🚀 Next Steps:"
    echo "• Test: docker run --rm -p 8020:8020 $FULL_IMAGE_NAME --help"
    echo "• Inspect: docker history $FULL_IMAGE_NAME"
    echo ""
}

# Main execution
main() {
    
    parse_args "$@"
    resolve_parameters
    validate_inputs
    execute_build
    show_summary
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Nix container build completed successfully! 🎯"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    main "$@"
fi
