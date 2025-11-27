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

import std/[options, strutils, tables, logging]
import metrics
import ss2_wrapper, config

type
  FlowSelector* = object
    config*: config.ExporterConfig

  SocketCollector* = ref object
    config*: config.ExporterConfig
    selector*: FlowSelector
    # Metrics
    tcpRttGauge*: Option[Gauge]
    tcpCwndGauge*: Option[Gauge]
    tcpDeliveryRateGauge*: Option[Gauge]
    tcpDataSegsInCounter*: Option[Counter]
    tcpDataSegsOutCounter*: Option[Counter]
    tcpRttHistogram*: Option[Histogram]

proc createFlowLabel*(flow: ss2_wrapper.FlowInfo, folding: string): string =
  ## Create flow label based on folding configuration
  case folding:
  of "raw_endpoint":
    result = "(SRC#{$1}|{$2})(DST#{$3}|{$4})" % [
      flow.src, $flow.srcPort, flow.dst, $flow.dstPort
    ]
  of "pid_condensed":
    # Extract first PID from user context
    var pids: seq[string] = @[]
    for user, pidTable in flow.usrCtxt.pairs():
      for pid in pidTable.keys():
        pids.add(pid)
    
    if pids.len > 0:
      result = "({$1})(DST#{$2}|{$3})" % [
        pids.join(","), flow.dst, $flow.dstPort
      ]
    else:
      # Fallback to raw endpoint if no process info
      result = "(SRC#{$1}|{$2})(DST#{$3}|{$4})" % [
        flow.src, $flow.srcPort, flow.dst, $flow.dstPort
      ]
  else:
    result = "(SRC#{$1}|{$2})(DST#{$3}|{$4})" % [
      flow.src, $flow.srcPort, flow.dst, $flow.dstPort
    ]

proc shouldIncludeFlow*(selector: FlowSelector, flow: ss2_wrapper.FlowInfo): bool =
  ## Apply selection filters to determine if flow should be included
  result = true  # Default to include all
  
  let selectionConfig = selector.config.logic.selection
  if selectionConfig.isNone:
    return true  # No filters configured
  
  let selection = selectionConfig.get()
  
  # Process filtering
  if selection.process.isSome:
    let processFilter = selection.process.get()
    let processMatch = 
      # Check PID match
      if processFilter.pids.len > 0:
        var found = false
        for user, pidTable in flow.usrCtxt.pairs():
          for pidStr in pidTable.keys():
            try:
              let pid = parseInt(pidStr)
              if pid in processFilter.pids:
                found = true
                break
            except ValueError:
              discard
        found
      else:
        true
    
    let cmdMatch =
      # Check command match  
      if processFilter.cmds.len > 0:
        var found = false
        for user, pidTable in flow.usrCtxt.pairs():
          for cmd in pidTable.values():
            for filterCmd in processFilter.cmds:
              if filterCmd in cmd:
                found = true
                break
            if found: break
        found
      else:
        true
    
    result = result and processMatch and cmdMatch

  # Port range filtering would go here
  # Peering filtering would go here

proc newSocketCollector*(config: config.ExporterConfig): SocketCollector =
  ## Create a new socket collector with metrics registration
  result = SocketCollector()
  result.config = config
  result.selector = FlowSelector(config: config)
  
  let metricsConfig = config.logic.metrics
  
  # Register gauge metrics
  if metricsConfig.gauges.active and metricsConfig.gauges.rtt.active:
    result.tcpRttGauge = some(gauge("tcp_rtt"))
  
  if metricsConfig.gauges.active and metricsConfig.gauges.cwnd.active:
    result.tcpCwndGauge = some(gauge("tcp_cwnd"))
  
  if metricsConfig.gauges.active and metricsConfig.gauges.deliveryRate.active:
    result.tcpDeliveryRateGauge = some(gauge("tcp_delivery_rate"))
  
  # Register counter metrics
  if metricsConfig.counters.active and metricsConfig.counters.dataSegsIn.active:
    result.tcpDataSegsInCounter = some(counter("tcp_data_segs_in"))
  
  if metricsConfig.counters.active and metricsConfig.counters.dataSegsOut.active:
    result.tcpDataSegsOutCounter = some(counter("tcp_data_segs_out"))
  
  # Register RTT histogram metric
  if metricsConfig.histograms.active and metricsConfig.histograms.rtt.active:
    let bucketBounds = metricsConfig.histograms.rtt.bucketBounds
    result.tcpRttHistogram = some(histogram("tcp_rtt_hist_ms"))

proc collect*(collector: SocketCollector) =
  ## Collect socket statistics and update metrics
  try:
    info "Starting socket statistics collection..."
    
    let socketStats = callSs2Utility()
    if socketStats.isNone:
      error "Failed to collect socket statistics"
      return
    
    let stats = socketStats.get()
    info "Collected ", stats.flows.len, " TCP flows"
    
    var flowsProcessed = 0
    
    for flow in stats.flows:
      # Apply selection filters
      if not collector.selector.shouldIncludeFlow(flow):
        continue
      
      flowsProcessed.inc()
      
      let flowLabel = createFlowLabel(flow, collector.config.logic.compression.labelFolding)
      
      # Update gauge metrics
      if collector.tcpRttGauge.isSome:
        collector.tcpRttGauge.get().set(flow.tcpInfo.rtt)
      
      if collector.tcpCwndGauge.isSome:
        collector.tcpCwndGauge.get().set(flow.tcpInfo.sndCwnd.float)
      
      if collector.tcpDeliveryRateGauge.isSome:
        collector.tcpDeliveryRateGauge.get().set(flow.tcpInfo.deliveryRate.float)
      
      # Update counter metrics
      if collector.tcpDataSegsInCounter.isSome:
        collector.tcpDataSegsInCounter.get().inc(flow.tcpInfo.dataSegsIn)
      
      if collector.tcpDataSegsOutCounter.isSome:
        collector.tcpDataSegsOutCounter.get().inc(flow.tcpInfo.dataSegsOut)
      
      # Update histogram metrics
      if collector.tcpRttHistogram.isSome:
        collector.tcpRttHistogram.get().observe(flow.tcpInfo.rtt)
    
    info "Processed ", flowsProcessed, " flows after filtering"
    
  except CatchableError as e:
    error "Error during metrics collection: ", e.msg