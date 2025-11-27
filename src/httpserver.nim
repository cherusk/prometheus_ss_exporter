##[
HTTP Server Module
Handles HTTP requests using chronos HTTP server
]##

import std/[strutils, logging, options]
import chronos
import chronos/apps/http/httpserver
import metrics
import collector

proc createMetricsHandler*(collector: SocketCollector): auto =
  ## Create HTTP handler for /metrics endpoint
  proc callback(): Future[HttpResponseRef] {.async.} =
    try:
      debug "Received metrics request from: ", req.uri.path
      
      # Collect latest socket statistics
      collector.collect()
      
      # Generate metrics output
      let metricsOutput = collector.registry.output()
      
      let headers = HttpTable.init([
        ("Content-Type", "text/plain; version=0.0.4; charset=utf-8"),
        ("Connection", "close")
      ])
      
      await req.respond(Http200, metricsOutput, headers)
      debug "Metrics response sent successfully"
      
    except CatchableError as e:
      let errorMsg = "Error collecting metrics: " & e.msg
      error errorMsg
      
      let headers = HttpTable.init([
        ("Content-Type", "text/plain"),
        ("Connection", "close")
      ])
      
      await req.respond(Http500, errorMsg, headers)

  return callback

proc createHealthHandler*(): HttpCallback =
  ## Create HTTP handler for /health endpoint
  proc callback(req: Request) {.async.} =
    debug "Received health check request"
    let headers = HttpTable.init([
      ("Content-Type", "text/plain"),
      ("Connection", "close")
    ])
    await req.respond(Http200, "200 OK", headers)

  return callback

proc createRootHandler*(): HttpCallback =
  ## Create HTTP handler for root endpoint with basic info
  proc callback(req: Request) {.async.} =
    debug "Received root request"
    let response = """
# Prometheus Socket Statistics Exporter (Nim Version)
## Endpoints
- /metrics - Prometheus metrics
- /health - Health check

## Usage
curl http://localhost:8020/metrics
"""
    
    let headers = HttpTable.init([
      ("Content-Type", "text/plain"),
      ("Connection", "close")
    ])
    
    await req.respond(Http200, response, headers)

  return callback

proc setupHttpServer*(collector: SocketCollector, port: int): Future[HttpClientRef] {.async.} =
  ## Setup and configure the HTTP server
  info "Setting up HTTP server on port: ", port
  
  let server = HttpClientRef.new()
  
  # Register routes
  server.route(HttpMethod.Get, "/metrics", createMetricsHandler(collector))
  server.route(HttpMethod.Get, "/health", createHealthHandler())
  server.route(HttpMethod.Get, "/", createRootHandler())
  
  # Start the server
  try:
    await server.start(Port(port), "0.0.0.0")
    info "HTTP server started successfully on port: ", port
    return server
  except CatchableError as e:
    error "Failed to start HTTP server: ", e.msg
    raise e

proc gracefulShutdown*(server: HttpClientRef) {.async.} =
  ## Perform graceful shutdown of the HTTP server
  info "Shutting down HTTP server gracefully..."
  try:
    await server.closeWait()
    info "HTTP server shutdown complete"
  except CatchableError as e:
    error "Error during server shutdown: ", e.msg