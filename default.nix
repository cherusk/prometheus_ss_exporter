{ pkgs ? import <nixpkgs> {}, version ? builtins.getEnv "VERSION" }:

let
  # Python runtime dependencies only
  pythonRuntime = pkgs.python312.withPackages (pythonPackages: with pkgs.python312Packages; [ pyroute2 psutil ]);

  # Bash for ss2 wrapper execution
  bashRuntime = pkgs.bash;

  # Build the application using the documentation pattern exactly
  prometheusExporter = pkgs.stdenv.mkDerivation {
    pname = "prometheus-ss-exporter";
    version = version;
    
    src = ./.;
    
    nativeBuildInputs = with pkgs; [
      cacert
      nim
      nimble
      gcc
      git
    ];
    
    buildInputs = with pkgs; [
      pythonRuntime
      bashRuntime
    ];
    
    env = {
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    
    configurePhase = ''
      export HOME=$TMPDIR
      export BUILD_VERSION="${builtins.getEnv "VERSION"}"
      echo "Building version: $BUILD_VERSION"
      if [ -z "$BUILD_VERSION" ]; then
        echo "❌ VERSION environment variable is required"
        exit 1
      fi
    '';
    
    buildPhase = ''
      echo "Using documentation-based SSL setup in container..."
      echo "SSL_CERT_FILE: $SSL_CERT_FILE"
      echo "Certificate exists: $([ -f "$SSL_CERT_FILE" ] && echo "YES" || echo "NO")"
      
      # Following the exact documentation pattern - this should work in container
      nimble refresh
      nimble install --depsOnly
      nimble build -v -d:release -d:metrics --threads:on -d:version="$BUILD_VERSION"
      
      # Build ss2 tool if available
      if [ -d "ss2" ]; then
        cd ss2
        make
        cd ..
      fi
    '';
    
    installPhase = ''
      mkdir -p $out/bin
      
      # Install main binary
      if [ -f "bin/prometheus_ss_exporter" ]; then
        cp bin/prometheus_ss_exporter $out/bin/
      elif [ -f "prometheus_ss_exporter" ]; then
        cp prometheus_ss_exporter $out/bin/
      else
        echo "Binary not found!"
        exit 1
      fi
      
      # Install ss2 tool if built
      if [ -f "ss2/ss2" ]; then
        cp ss2/ss2 $out/bin/
      fi
      
      # Make binaries executable
      chmod +x $out/bin/*
      
      echo "✅ Installation completed successfully!"
      ls -la $out/bin/
    '';
  };

  # Create container image using buildLayeredImage for better pseudo filesystem support
  containerImage = pkgs.dockerTools.buildLayeredImage {
    name = "prometheus-ss-exporter";
    tag = "${version}";
    
    # Use busybox for minimal base utilities and pseudo filesystem support
    fromImage = null;
    
    # Include runtime dependencies
    contents = [
      prometheusExporter
      pythonRuntime
      bashRuntime
      pkgs.cacert
      pkgs.busybox  # Provides basic utilities and pseudo filesystem support
    ];
    
    config = {
      Entrypoint = [ "${prometheusExporter}/bin/prometheus_ss_exporter" ];
      Cmd = [ "--port=8020" "--config=config.yml" ];
      ExposedPorts = {
        "8020/tcp" = {};
      };
      Env = [
        "PATH=/bin:${prometheusExporter}/bin:${pythonRuntime}/bin"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      ];
      WorkingDir = "/app";
      User = "1000:1000";
      
      Healthcheck = {
        Test = [ "CMD" "${prometheusExporter}/bin/prometheus_ss_exporter" "--help" ];
        Interval = 30000000000;  # 30s in nanoseconds
        Timeout = 5000000000;    # 5s in nanoseconds
        Retries = 3;
        StartPeriod = 5000000000; # 5s in nanoseconds
      };
    };
  };

in {
  inherit prometheusExporter containerImage;
}