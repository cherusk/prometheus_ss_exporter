#!/usr/bin/env nim
#[
MIT License
prometheus_ss_exporter - Prometheus socket statistics exporter in Nim
Copyright (c) 2018 Matthias Tafelmeier

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]##

import std/[os, strutils, logging, options, times, osproc, parseopt, sequtils,
    tables, strformat]
import metrics
import metrics/chronos_httpserver
import config, ss2_wrapper, collector

const
  version {.strdefine.} = "2.1.1"  # Can be overridden with -d:version="X.Y.Z"
  appName = "Prometheus Socket Statistics Exporter (Nim)"

proc setupLogging*(level: Level = lvlInfo) =
  ## Setup console logging with proper formatting
  let fmtStr = "$datetime [$levelname] "
  var logger = newConsoleLogger(levelThreshold = level, fmtStr = fmtStr)
  addHandler(logger)

proc printVersion*() =
  ## Print version information
  echo appName, " v", version
  echo "Built with Nim - high performance systems programming language"

proc printUsage*() =
  ## Print usage information
  echo """
Usage: prometheus_ss_exporter [options]

Options:
  -h, --help              Show this help message
  -v, --version           Show version information
  -p, --port:PORT         HTTP server port (default: 8020)
  -c, --config:FILE       Configuration file path (default: config.yml)
  --log-level:LEVEL       Logging level (DEBUG, INFO, WARN, ERROR)
  --create-config:FILE    Create sample configuration file

Examples:
  prometheus_ss_exporter                                    # Run with defaults
  prometheus_ss_exporter -p 8090 -c /path/to/config.yml    # Custom port and config
  prometheus_ss_exporter --log-level:DEBUG                 # Debug logging
  prometheus_ss_exporter --create-config:config.yml         # Create sample config
"""

proc main*(port = 8020, configFile = "config.yml", logLevel = "INFO",
           createConfig = "") =
  ## Main entry point for the Prometheus socket statistics exporter

  # Handle config creation request
  if createConfig.len > 0:
    createSampleConfig(createConfig)
    return

  # Setup logging
  let level = case logLevel.toUpperAscii():
    of "DEBUG": lvlDebug
    of "INFO": lvlInfo
    of "WARN": lvlWarn
    of "ERROR": lvlError
    else: lvlInfo

  setupLogging(level)

  info "Starting ", appName, " v", version
  info "Nim compiler version: ", NimVersion
  info "Process ID: ", getCurrentProcessId()

  # Load configuration
  let configResult = loadConfig(configFile)
  if configResult.isNone:
    error "Failed to load configuration from: ", configFile
    error "Use --create-config:", configFile, " to create a sample configuration"
    quit(QuitFailure)

  let config = configResult.get()
  info "Configuration loaded successfully from: ", configFile

  # Initialize and start the metrics collector
  initSocketCollector(config)

  # Start Prometheus metrics HTTP server using available API
  info "Starting Prometheus metrics HTTP server..."
  try:
    # Use the deprecated but functional startMetricsHttpServer for now
    # TODO: Replace with modern API once available and documented
    chronos_httpserver.startMetricsHttpServer("0.0.0.0", Port(port))
    info "Prometheus metrics HTTP server started successfully on port ", port
    info "Metrics endpoint: http://localhost:", port, "/metrics"

    # Keep the main thread alive
    while true:
      sleep(1000)

  except CatchableError as e:
    error "Failed to start metrics HTTP server: ", e.msg
    error "Exception details: ", e.name, ": ", e.msg
    error "Stack trace: ", e.getStackTrace()
    quit(QuitFailure)

proc parseArgs(): Table[string, string] =
  var args = initTable[string, string]()

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      discard
    of cmdLongOption, cmdShortOption:
      case key:
      of "port", "p":
        args["port"] = val
      of "config", "c":
        args["config"] = val
      of "log-level":
        args["log-level"] = val
      of "create-config":
        args["create-config"] = val
      of "help", "h":
        printVersion()
        echo ""
        printUsage()
        quit(QuitSuccess)
      of "version", "v":
        printVersion()
        quit(QuitSuccess)
    of cmdEnd:
      break

  return args

when isMainModule:
  # Parse command line arguments
  let args = parseArgs()

  # Set defaults and override with parsed arguments
  var port = 8020
  var configFile = "config.yml"
  var logLevel = "INFO"
  var createConfig = ""

  # Apply parsed arguments with validation
  if args.contains("port"):
    let portStr = args["port"]
    if portStr.len == 0:
      echo "Error: --port requires a numeric value"
      quit(QuitFailure)
    try:
      port = parseInt(portStr)
    except ValueError:
      echo "Error: --port requires a valid numeric value, got: ", portStr
      quit(QuitFailure)

  if args.contains("config"):
    let configStr = args["config"]
    if configStr.len == 0:
      echo "Error: --config requires a file path"
      quit(QuitFailure)
    configFile = configStr

  if args.contains("log-level"):
    let logStr = args["log-level"]
    if logStr.len == 0:
      echo "Error: --log-level requires a value (DEBUG, INFO, WARN, ERROR)"
      quit(QuitFailure)
    logLevel = logStr

  if args.contains("create-config"):
    let createStr = args["create-config"]
    if createStr.len == 0:
      echo "Error: --create-config requires a file path"
      quit(QuitFailure)
    createConfig = createStr

  main(port, configFile, logLevel, createConfig)
