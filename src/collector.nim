##[
MIT License
prometheus_ss_exporter - Prometheus socket statistics exporter in Nim
Copyright (c) 2018 Matthias Tafelmeier

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]##

##[
Collector Module
Handles socket statistics collection and Prometheus metrics registration
]##

import std/[options, strutils, tables, logging, times, osproc, json, algorithm]
import metrics
import ss2_wrapper, config

type
  FlowSelector* = object
    config*: config.ExporterConfig

  SocketCollector* = ref object of Collector
    config*: config.ExporterConfig
    selector*: FlowSelector

when defined(metrics):
  var socketCollector: SocketCollector
  var collectorConfig*: config.ExporterConfig

# No cache needed - call directly

type
  MetricOutput* = object
    name*: string
    labels*: seq[string]
    labelValues*: seq[string]
    value*: float
    timestamp*: int64

proc safeGetFloat(node: JsonNode, key: string, default: float = 0.0): float =
  ## Safely get a float value from JSON node
  if node.isNil: return default
  let field = node{key}
  if field.isNil: return default
  try:
    result = field.getFloat(default)
  except:
    result = default

proc safeGetInt(node: JsonNode, key: string, default: int = 0): int =
  ## Safely get an int value from JSON node
  if node.isNil: return default
  let field = node{key}
  if field.isNil: return default
  try:
    result = field.getInt(default)
  except:
    result = default

proc createFlowLabel*(src: string, srcPort: int, dst: string, dstPort: int,
    folding: string, processId: string = ""): string =
  ## Create flow label based on folding configuration
  echo "DEBUG: createFlowLabel called with src=", src, " srcPort=", srcPort, " dst=", dst, " dstPort=", dstPort, " folding=", folding
  case folding
  of "raw_endpoint":
    echo "DEBUG: using raw_endpoint folding"
    result = "(SRC#" & src & "|" & $srcPort & ")(DST#" & dst & "|" & $dstPort & ")"
    echo "DEBUG: raw_endpoint result: ", result
  of "pid_condensed":
    echo "DEBUG: using pid_condensed folding, processId='", processId, "'"
    if processId.len > 0:
      echo "DEBUG: processId found, using pid format"
      result = "(" & processId & ")(DST#" & dst & "|" & $dstPort & ")"
      echo "DEBUG: pid result: ", result
    else:
      echo "DEBUG: no processId, using fallback"
      # Fallback to raw_endpoint if no process ID available
      result = "(SRC#" & src & "|" & $srcPort & ")(DST#" & dst & "|" &
          $dstPort & ")"
      echo "DEBUG: fallback result: ", result
  else:
    echo "DEBUG: using fallback flow format"
    result = "flow_" & $srcPort & "_" & $dstPort
    echo "DEBUG: fallback result: ", result
  echo "DEBUG: createFlowLabel returning"

proc shouldIncludeFlow*(selector: FlowSelector, flow: ss2_wrapper.FlowInfo): bool =
  ## Apply selection filters to determine if flow should be included
  let selectionConfig = selector.config.logic.selection
  if isNone(selectionConfig):
    return true  # No selection config, accept all flows
  let selection = get(selectionConfig)
  
  # Process filtering
  if isSome(selection.process):
    let processConfig = get(selection.process)
    if processConfig.pids.len > 0:
      # Check if flow's process is in the allowed PIDs
      var foundPid = false
      for user, pidData in flow.usrCtxt.pairs():
        for pid, cmd in pidData.pairs():
          try:
            let flowPid = parseInt(pid)
            if flowPid in processConfig.pids:
              foundPid = true
              break
          except:
            discard
        if foundPid: break
      if not foundPid: return false
    
    if processConfig.cmds.len > 0:
      # Check if flow's command is in the allowed commands
      var foundCmd = false
      for user, pidData in flow.usrCtxt.pairs():
        for pid, cmd in pidData.pairs():
          if cmd in processConfig.cmds:
            foundCmd = true
            break
        if foundCmd: break
      if not foundCmd: return false
  
  # Network/peer filtering
  if isSome(selection.peering):
    let peeringConfig = get(selection.peering)
    if peeringConfig.addresses.len > 0:
      if flow.dst notin peeringConfig.addresses:
        return false
    
    if peeringConfig.networks.len > 0:
      # Simple network matching (basic implementation)
      var foundNetwork = false
      for network in peeringConfig.networks:
        if flow.dst.startswith(network.split('/')[0]):
          foundNetwork = true
          break
      if not foundNetwork: return false
  
  # Port range filtering
  if selection.portRanges.len > 0:
    var foundPort = false
    for portRange in selection.portRanges:
      if flow.dstPort >= portRange.lower and flow.dstPort <= portRange.upper:
        foundPort = true
        break
    if not foundPort: return false
  
  result = true

proc preprocessMetricsWithConfig*(exporterConfig: config.ExporterConfig): seq[MetricOutput] =
  ## Preprocess all metrics data into simple output objects
  let timestamp = epochTime().int64
  result = @[]

  # Always add collection status
  result.add(MetricOutput(
    name: "collector_collection_runs_total",
    labels: @[],
    labelValues: @[],
    value: 1.0,
    timestamp: timestamp
  ))

  # Extract configuration for easier access
  let logicConfig = exporterConfig.logic
  let metricsConfig = logicConfig.metrics

  let compressionConfig = logicConfig.compression

  # Initialize flow selector (TODO: implement actual filtering logic)
  let selector = FlowSelector(config: exporterConfig)

  # Use the ss2_wrapper to get socket statistics
  try:
    echo "DEBUG: calling ss2_wrapper.callSs2Utility()"
    let socketStats = ss2_wrapper.callSs2Utility()
    echo "DEBUG: ss2_wrapper.callSs2Utility() returned"
    if socketStats.isNone:
      echo "DEBUG: socketStats.isNone is true, returning error status"
      result.add(MetricOutput(
        name: "collector_data_status",
        labels: @["status"],
        labelValues: @["ss2_command_failed"],
        value: 1.0,
        timestamp: timestamp
      ))
      result.add(MetricOutput(
        name: "tcp_flows_total",
        labels: @[],
        labelValues: @[],
        value: 0.0,
        timestamp: timestamp
      ))
      return result

    echo "DEBUG: extracting stats from socketStats"
    let stats = socketStats.get()
    echo "DEBUG: extracted stats, flows count: ", stats.flows.len
    var flowCount = 0
    var rttValues: seq[float] = @[] # For histogram generation

    # Filter flows using the selector and count them
    echo "DEBUG: filtering flows, total flows: ", stats.flows.len
    for flow in stats.flows:
      if selector.shouldIncludeFlow(flow):
        flowCount += 1
    echo "DEBUG: filtered flow count: ", flowCount

    # Add flow count
    result.add(MetricOutput(
      name: "tcp_flows_total",
      labels: @[],
      labelValues: @[],
      value: flowCount.float,
      timestamp: timestamp
    ))

    # Process all flows respecting configuration  
    echo "DEBUG: processing flows for metrics"
    var processedFlows = 0
    for flow in stats.flows:
      # Only process flows that pass the filter
      if not selector.shouldIncludeFlow(flow):
        continue

      echo "DEBUG: processing flow ", processedFlows
      let src = flow.src
      let dst = flow.dst
      let srcPort = flow.srcPort
      let dstPort = flow.dstPort
      echo "DEBUG: flow src/dst ports: ", srcPort, "/", dstPort

      # Extract process ID for pid_condensed label folding
      var processId = ""
      if compressionConfig.labelFolding == "pid_condensed":
        # Extract process info from the structured usrCtxt
        for user, pidData in flow.usrCtxt.pairs():
          for pid, cmd in pidData.pairs():
            processId = pid
            break
          if processId.len > 0:
            break

      # Create flow label based on configuration
      echo "DEBUG: calling createFlowLabel for flow ", processedFlows
      let flowLabel = createFlowLabel(src, srcPort, dst, dstPort,
          compressionConfig.labelFolding, processId)
      echo "DEBUG: createFlowLabel returned: ", flowLabel

      # Extract TCP info from structured FlowInfo
      echo "DEBUG: extracting tcpInfo"
      let tcpInfo = flow.tcpInfo
      echo "DEBUG: tcpInfo extracted, rtt: ", tcpInfo.rtt
      
      # Round Trip Time - GAUGE
      let rtt = tcpInfo.rtt

      result.add(MetricOutput(
        name: "tcp_rtt",
        labels: @["flow"],
        labelValues: @[flowLabel],
        value: rtt,
        timestamp: timestamp
      ))

      # Add RTT value to histogram collection
      rttValues.add(rtt)

      # Congestion Window - GAUGE
      let sndCwnd = tcpInfo.sndCwnd

      result.add(MetricOutput(
        name: "tcp_cwnd",
        labels: @["flow"],
        labelValues: @[flowLabel],
        value: sndCwnd.float,
        timestamp: timestamp
      ))

      # Delivery Rate - GAUGE
      let deliveryRate = tcpInfo.deliveryRate
      if deliveryRate > 0:
        result.add(MetricOutput(
          name: "tcp_delivery_rate",
          labels: @["flow"],
          labelValues: @[flowLabel],
          value: deliveryRate.float,
          timestamp: timestamp
        ))

      # Data Segments - COUNTERS
      let dataSegsIn = tcpInfo.dataSegsIn
      let dataSegsOut = tcpInfo.dataSegsOut

      result.add(MetricOutput(
        name: "tcp_data_segs_in",
        labels: @["flow"],
        labelValues: @[flowLabel],
        value: dataSegsIn.float,
        timestamp: timestamp
      ))

      result.add(MetricOutput(
        name: "tcp_data_segs_out",
        labels: @["flow"],
        labelValues: @[flowLabel],
        value: dataSegsOut.float,
        timestamp: timestamp
      ))
      echo "DEBUG: completed processing flow ", processedFlows
      processedFlows += 1

    # Add RTT histogram if enabled in configuration
    if metricsConfig.histograms.active and
        metricsConfig.histograms.rtt.isSome and
        metricsConfig.histograms.rtt.get().active and rttValues.len > 0:
      # Sort values for histogram calculation
      rttValues = sorted(rttValues)

      # Use bucket bounds from configuration
      let bucketBounds = metricsConfig.histograms.rtt.get().bucketBounds

      # Create histogram buckets
      for bound in bucketBounds:
        var count = 0.0
        for rtt in rttValues:
          if rtt <= bound:
            count += 1.0
        result.add(MetricOutput(
          name: "tcp_rtt_hist_ms_bucket",
          labels: @["le"],
          labelValues: @[$bound],
          value: count,
          timestamp: timestamp
        ))

      # Add +Inf bucket (count all values)
      result.add(MetricOutput(
        name: "tcp_rtt_hist_ms_bucket",
        labels: @["le"],
        labelValues: @["+Inf"],
        value: rttValues.len.float,
        timestamp: timestamp
      ))

      # Add histogram count and sum
      result.add(MetricOutput(
        name: "tcp_rtt_hist_ms_count",
        labels: @[],
        labelValues: @[],
        value: rttValues.len.float,
        timestamp: timestamp
      ))

      var sum = 0.0
      for rtt in rttValues:
        sum += rtt
      result.add(MetricOutput(
        name: "tcp_rtt_hist_ms_sum",
        labels: @[],
        labelValues: @[],
        value: sum,
        timestamp: timestamp
      ))

    result.add(MetricOutput(
      name: "collector_data_status",
      labels: @["status"],
      labelValues: @["success"],
      value: flowCount.float,
      timestamp: timestamp
    ))

  except Exception as e:
    result.add(MetricOutput(
      name: "collector_data_status",
      labels: @["status"],
      labelValues: @["json_parse_error"],
      value: 1.0,
      timestamp: timestamp
    ))
    result.add(MetricOutput(
      name: "tcp_flows_total",
      labels: @[],
      labelValues: @[],
      value: 0.0,
      timestamp: timestamp
    ))

when defined(metrics):
  method collect(collector: SocketCollector, output: MetricHandler) =
    echo "DEBUG: collect() method called"
    let timestamp = collector.now()
    echo "DEBUG: got timestamp: ", timestamp

    # Preprocess all metrics with configuration respect
    echo "DEBUG: calling preprocessMetricsWithConfig()"
    let metrics = preprocessMetricsWithConfig(collector.config)
    echo "DEBUG: preprocessMetricsWithConfig returned, metrics count: ", metrics.len

    # Output all metrics
    echo "DEBUG: starting to output metrics"
    var metricIndex = 0
    for metric in metrics:
      echo "DEBUG: processing metric ", metricIndex, ": ", metric.name
      output(
        name = metric.name,
        labels = metric.labels,
        labelValues = metric.labelValues,
        value = metric.value,
        timestamp = timestamp
      )
      metricIndex += 1
    echo "DEBUG: finished outputting all metrics"

proc initSocketCollector*(config: config.ExporterConfig) =
  ## Initialize the global socket collector config and register collector
  collectorConfig = config

  # Create and register the socket collector (only once)
  try:
    socketCollector = SocketCollector.newCollector(name = "socket_stats",
        help = "Prometheus socket statistics exporter")
    socketCollector.config = config # Set the configuration
    socketCollector.selector = FlowSelector(config: config) # Set the selector
    register(socketCollector)
  except RegistrationError:
    # Collector already registered, ignore
    discard

