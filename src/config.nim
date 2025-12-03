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
Configuration Module
Handles YAML configuration parsing for the exporter
]##

import std/[options, strutils, logging, os]
import yaml

type
  IndividualMetricConfig* = object
    active*: bool

  HistogramConfig* = object
    active*: bool
    rtt*: Option[RttHistogramConfig]

  RttHistogramConfig* = object
    active*: bool
    bucketBounds*: seq[float]

  GaugeConfig* = object
    active*: bool
    rtt*: IndividualMetricConfig
    cwnd*: IndividualMetricConfig
    deliveryRate*: IndividualMetricConfig

  CounterConfig* = object
    active*: bool
    dataSegsIn*: IndividualMetricConfig
    dataSegsOut*: IndividualMetricConfig

  MetricsConfig* = object
    histograms*: HistogramConfig
    gauges*: GaugeConfig
    counters*: CounterConfig

  ProcessFilter* = object
    pids*: seq[int]
    cmds*: seq[string]

  PeeringFilter* = object
    addresses*: seq[string]
    networks*: seq[string]
    hosts*: seq[string]

  PortRange* = object
    lower*: int
    upper*: int

  SelectionConfig* = object
    process*: Option[ProcessFilter]
    peering*: Option[PeeringFilter]
    portRanges*: seq[PortRange]

  CompressionConfig* = object
    labelFolding*: string # "raw_endpoint" or "pid_condensed"

  LogicConfig* = object
    metrics*: MetricsConfig
    compression*: CompressionConfig
    selection*: Option[SelectionConfig]

  ExporterConfig* = object
    logic*: LogicConfig

  # Helper types for simplified configuration loading
  SimpleHistogramConfig* = object
    active*: bool

  SimpleMetricsConfig* = object
    gauges*: GaugeConfig
    counters*: CounterConfig
    histograms*: SimpleHistogramConfig

  SimpleLogicConfig* = object
    metrics*: SimpleMetricsConfig
    compression*: CompressionConfig
    selection*: Option[SelectionConfig]

  SimpleConfig* = object
    logic*: SimpleLogicConfig

proc getDefaultRttHistogramConfig(): RttHistogramConfig =
  RttHistogramConfig(
    active: false,
    bucketBounds: @[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5,
        5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0]
  )

proc getDefaultHistogramConfig(): HistogramConfig =
  HistogramConfig(
    active: false,
    rtt: none(RttHistogramConfig)  # Disabled histograms don't need rtt config
  )

proc getDefaultGaugeConfig(): GaugeConfig =
  GaugeConfig(
    active: true,
    rtt: IndividualMetricConfig(active: true),
    cwnd: IndividualMetricConfig(active: true),
    deliveryRate: IndividualMetricConfig(active: true)
  )

proc getDefaultCounterConfig(): CounterConfig =
  CounterConfig(
    active: true,
    dataSegsIn: IndividualMetricConfig(active: true),
    dataSegsOut: IndividualMetricConfig(active: true)
  )

proc getDefaultMetricsConfig(): MetricsConfig =
  MetricsConfig(
    histograms: getDefaultHistogramConfig(),
    gauges: getDefaultGaugeConfig(),
    counters: getDefaultCounterConfig()
  )

proc getDefaultCompressionConfig(): CompressionConfig =
  CompressionConfig(
    labelFolding: "raw_endpoint"
  )

proc getDefaultLogicConfig(): LogicConfig =
  LogicConfig(
    metrics: getDefaultMetricsConfig(),
    compression: getDefaultCompressionConfig(),
    selection: none(SelectionConfig)
  )

proc getDefaultExporterConfig(): ExporterConfig =
  ExporterConfig(
    logic: getDefaultLogicConfig()
  )

proc loadConfig*(configPath: string): Option[ExporterConfig] =
  ## Load configuration from YAML file with graceful error handling
  try:
    info "Loading configuration from: ", configPath

    if not fileExists(configPath):
      error "Configuration file not found: ", configPath
      return none(ExporterConfig)

    let content = readFile(configPath)

    # Start with default configuration
    var config = getDefaultExporterConfig()

    # Try to load YAML configuration
    try:
      load(content, config)
    except CatchableError as yamlError:
      # If YAML loading fails due to missing rtt field when histograms are disabled, handle gracefully
      if "Missing field" in yamlError.msg and "rtt" in yamlError.msg:
        info "RTT field missing but histograms may be disabled - trying simplified loading"
        
        # Check if user explicitly disabled histograms with string check (fallback approach)
        if "histograms:" in content and "active: false" in content:
          info "User appears to have disabled histograms, using simplified configuration"
          
          # Load using predefined simple config types
          var simpleConfig: SimpleConfig
          load(content, simpleConfig)
          
          # Transfer to full config
          config.logic.metrics.gauges = simpleConfig.logic.metrics.gauges
          config.logic.metrics.counters = simpleConfig.logic.metrics.counters
          config.logic.metrics.histograms.active = simpleConfig.logic.metrics.histograms.active
          config.logic.compression = simpleConfig.logic.compression
          config.logic.selection = simpleConfig.logic.selection
          
          info "Configuration loaded successfully with disabled histograms"
          return some(config)
        else:
          # Re-raise the original error if we can't handle it gracefully
          raise yamlError
      else:
        # Re-throw non-rtt related YAML errors
        raise yamlError

    info "Configuration loaded successfully"
    return some(config)

  except CatchableError as e:
    error "Failed to load configuration: ", e.msg
    return none(ExporterConfig)

proc createSampleConfig*(configPath: string) =
  ## Create a sample configuration file
  let sampleConfig = """
---
# Prometheus Socket Statistics Exporter Configuration
# All values shown below are the defaults - uncomment and modify as needed

logic:
  metrics:
    histograms:
      active: false  # Disabled by default - no rtt section needed when disabled
      # To enable RTT histograms, uncomment the following:
      # active: true
      # rtt:
      #   active: true
      #   bucketBounds: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0]
    
    gauges:
      active: true  # Enabled by default
      rtt: { active: true }
      cwnd: { active: true }
      deliveryRate: { active: true }
    
    counters:
      active: true  # Enabled by default
      dataSegsIn: { active: true }
      dataSegsOut: { active: true }
  
  compression:
    labelFolding: "raw_endpoint"  # Default folding method
  
  selection:
    # Optional filtering rules
    
    # Process filtering
    process:
      pids: [1000, 2000]  # Specific process IDs
      cmds: ["nginx", "apache2"]  # Process names
    
    # Network/peer filtering  
    peering:
      addresses: ["8.8.8.8", "1.1.1.1"]  # Specific IPs
      networks: ["10.0.0.0/8", "192.168.0.0/16"]  # CIDR networks
      hosts: ["example.com"]  # Hostnames
    
    # Port range filtering
    portRanges:
      - lower: 80
        upper: 443
      - lower: 8000
        upper: 9000
"""

  try:
    writeFile(configPath, sampleConfig)
    info "Sample configuration created at: ", configPath
  except CatchableError as e:
    error "Failed to create sample configuration: ", e.msg
