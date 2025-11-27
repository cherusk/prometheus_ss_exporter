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
    rtt*: RttHistogramConfig

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
    labelFolding*: string  # "raw_endpoint" or "pid_condensed"

  LogicConfig* = object
    metrics*: MetricsConfig
    compression*: CompressionConfig
    selection*: Option[SelectionConfig]

  ExporterConfig* = object
    logic*: LogicConfig

proc loadConfig*(configPath: string): Option[ExporterConfig] =
  ## Load configuration from YAML file
  try:
    info "Loading configuration from: ", configPath
    
    if not fileExists(configPath):
      error "Configuration file not found: ", configPath
      return none(ExporterConfig)
    
    let content = readFile(configPath)
    var config = ExporterConfig()
    load(content, config)
    
    result = some(config)
    
    # Set defaults
    result.get.logic.metrics.histograms.active = false
    result.get.logic.metrics.histograms.rtt = RttHistogramConfig(active: false, bucketBounds: @[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0])
    result.get.logic.metrics.gauges.active = true
    result.get.logic.metrics.gauges.rtt = IndividualMetricConfig(active: true)
    result.get.logic.metrics.gauges.cwnd = IndividualMetricConfig(active: true)
    result.get.logic.metrics.gauges.deliveryRate = IndividualMetricConfig(active: true)
    result.get.logic.metrics.counters.active = true
    result.get.logic.metrics.counters.dataSegsIn = IndividualMetricConfig(active: true)
    result.get.logic.metrics.counters.dataSegsOut = IndividualMetricConfig(active: true)
    result.get.logic.compression.labelFolding = "raw_endpoint"
    
    info "Configuration loaded with default values"
    return result
    
  except CatchableError as e:
    error "Failed to load configuration: ", e.msg
    return none(ExporterConfig)

proc createSampleConfig*(configPath: string) =
  ## Create a sample configuration file
  let sampleConfig = """
---
# Prometheus Socket Statistics Exporter Configuration

logic:
  metrics:
    histograms:
      active: true
      rtt:
        active: true
        bucketBounds: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0]
    
    gauges:
      active: true
      rtt: { active: true }
      cwnd: { active: true }
      deliveryRate: { active: true }
    
    counters:
      active: true
      dataSegsIn: { active: true }
      dataSegsOut: { active: true }
  
  compression:
    labelFolding: "raw_endpoint"  # or "pid_condensed"
  
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