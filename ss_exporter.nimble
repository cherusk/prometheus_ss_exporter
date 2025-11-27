# Package configuration
version       = "3.0.0"
author        = "Matthias Tafelmeier"
description   = "Prometheus socket statistics exporter - rewritten in Nim"
license       = "MIT"

srcDir        = "src"
bin           = @["prometheus_ss_exporter"]

# Dependencies
requires "nim >= 2.0"
requires "https://github.com/status-im/nim-metrics#head"
requires "https://github.com/status-im/nim-chronos#head"
requires "yaml >= 1.1.0"
requires "cligen >= 1.6"

# Optional dependencies for development
task test, "Run tests":
  exec "nim c -r tests/test_basic.nim"

task docker, "Build Docker image":
  exec "docker build -f Dockerfile.nim -t prometheus_ss_exporter:nim ."
