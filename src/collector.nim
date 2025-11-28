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

proc createFlowLabel*(flow: ss2_wrapper.FlowInfo, folding: string): string =
  ## Create flow label based on folding configuration
  case folding
  of "raw_endpoint":
    result = "(SRC#{$1}|{$2})(DST#{$3}|{$4})" % [
      flow.src, $flow.srcPort, flow.dst, $flow.dstPort
    ]
  else:
    result = "flow_" & $flow.srcPort & "_" & $flow.dstPort

proc shouldIncludeFlow*(selector: FlowSelector,
    flow: ss2_wrapper.FlowInfo): bool =
  ## Apply selection filters to determine if flow should be included
  # For now, accept all flows
  result = true

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
  case folding
  of "raw_endpoint":
    result = "(SRC#" & src & "|" & $srcPort & ")(DST#" & dst & "|" & $dstPort & ")"
  of "pid_condensed":
    if processId.len > 0:
      result = "(" & processId & ")(DST#" & dst & "|" & $dstPort & ")"
    else:
      # Fallback to raw_endpoint if no process ID available
      result = "(SRC#" & src & "|" & $srcPort & ")(DST#" & dst & "|" &
          $dstPort & ")"
  else:
    result = "flow_" & $srcPort & "_" & $dstPort

proc shouldIncludeFlow*(selector: FlowSelector, flow: JsonNode): bool =
  ## Apply selection filters to determine if flow should be included
  # For now, accept all flows - TODO: implement filtering logic
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

  # Simple JSON parsing without using the problematic ss2_wrapper
  try:
    let cmd = "python3"
    let args = @["-m", "pyroute2.netlink.diag.ss2", "--tcp", "--process"]
    let (output, exitCode) = osproc.execCmdEx(cmd & " " & args.join(" "))

    if exitCode != 0:
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

    let jsonNode = parseJson(output)

    var flowCount = 0
    var flows: seq[JsonNode] = @[]
    var rttValues: seq[float] = @[] # For histogram generation

    if jsonNode.kind == JObject:
      let tcpNode = jsonNode{"TCP"}
      if not tcpNode.isNil and tcpNode.kind == JObject:
        let flowsNode = tcpNode{"flows"}
        if not flowsNode.isNil and flowsNode.kind == JArray:
          flowCount = flowsNode.len
          # Collect flows for detailed analysis
          for flowNode in flowsNode.items():
            if not flowNode.isNil and flowNode.kind == JObject:
              flows.add(flowNode)

    # Add flow count
    result.add(MetricOutput(
      name: "tcp_flows_total",
      labels: @[],
      labelValues: @[],
      value: flowCount.float,
      timestamp: timestamp
    ))

    # Process all flows respecting configuration
    for flowNode in flows:

      let src = flowNode{"src"}.getStr("unknown")
      let dst = flowNode{"dst"}.getStr("unknown")
      let srcPort = safeGetInt(flowNode, "src_port")
      let dstPort = safeGetInt(flowNode, "dst_port")

      # Extract process ID for pid_condensed label folding
      var processId = ""
      if compressionConfig.labelFolding == "pid_condensed":
        # Try usrCtxt (user context) - this is where process info is stored
        let usrCtxtNode = flowNode{"usr_ctxt"}
        if not usrCtxtNode.isNil and usrCtxtNode.kind == JObject:
          for user, pidData in usrCtxtNode.pairs():
            if pidData.kind == JObject:
              for pid, cmdData in pidData.pairs():
                processId = pid
                break
              if processId.len > 0:
                break
        
        # If no usrCtxt, try proc_info as fallback
        if processId.len == 0:
          let procInfo = flowNode{"proc_info"}
          if not procInfo.isNil and procInfo.kind == JObject:
            processId = procInfo{"pid"}.getStr("")

      # Create flow label based on configuration
      let flowLabel = createFlowLabel(src, srcPort, dst, dstPort,
          compressionConfig.labelFolding, processId)

      # Extract TCP info safely
      let tcpInfo = flowNode{"tcp_info"}
      if not tcpInfo.isNil and tcpInfo.kind == JObject:
        # Round Trip Time - GAUGE
        let rtt = safeGetFloat(tcpInfo, "rtt")

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
        let sndCwnd = safeGetInt(tcpInfo, "snd_cwnd")

        result.add(MetricOutput(
          name: "tcp_cwnd",
          labels: @["flow"],
          labelValues: @[flowLabel],
          value: sndCwnd.float,
          timestamp: timestamp
        ))

        # Delivery Rate - GAUGE
        let deliveryRate = safeGetInt(tcpInfo, "delivery_rate")
        if deliveryRate > 0:
          result.add(MetricOutput(
            name: "tcp_delivery_rate",
            labels: @["flow"],
            labelValues: @[flowLabel],
            value: deliveryRate.float,
            timestamp: timestamp
          ))

        # Data Segments - COUNTERS
        let dataSegsIn = safeGetInt(tcpInfo, "data_segs_in")
        let dataSegsOut = safeGetInt(tcpInfo, "data_segs_out")

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

    # Add RTT histogram if enabled in configuration
    if metricsConfig.histograms.active and
        metricsConfig.histograms.rtt.active and rttValues.len > 0:
      # Sort values for histogram calculation
      rttValues = sorted(rttValues)

      # Use bucket bounds from configuration
      let bucketBounds = metricsConfig.histograms.rtt.bucketBounds

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
      value: flows.len.float,
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
    let timestamp = collector.now()

    # Preprocess all metrics with configuration respect
    let metrics = preprocessMetricsWithConfig(collector.config)

    # Output all metrics
    for metric in metrics:
      output(
        name = metric.name,
        labels = metric.labels,
        labelValues = metric.labelValues,
        value = metric.value,
        timestamp = timestamp
      )

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

