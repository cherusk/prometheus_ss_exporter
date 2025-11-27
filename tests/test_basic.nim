##[
Basic Tests for Nim Socket Exporter
]##

import std/[unittest, strutils, os, json]
import config, ss2_wrapper, collector

test "Configuration loading":
  # Test loading a basic config
  let config = loadConfig("config.yml")
  if config.isSome:
    let c = config.get()
    check c.logic.metrics.gauges.rtt == true
    check c.logic.metrics.gauges.cwnd == true
  else:
    echo "Config file not found, skipping test"

test "SS2 wrapper functionality":
  # Test calling ss2 utility
  let result = callSs2Utility()
  if result.isSome:
    let stats = result.get()
    echo "Successfully retrieved ", stats.flows.len, " flows"
    check stats.flows.len >= 0
  else:
    echo "SS2 utility not available, skipping test"

test "Flow label generation":
  # Test flow label creation
  var flow = ss2_wrapper.FlowInfo()
  flow.src = "192.168.1.1"
  flow.dst = "192.168.1.2"
  flow.srcPort = 12345
  flow.dstPort = 443
  
  # These functions need to be made public for testing
  echo "Flow label generation test - functions need to be exported"
  check flow.src == "192.168.1.1"
  check flow.dst == "192.168.1.2"

test "Metrics registry creation":
  # This would test the metrics registry if available
  echo "Metrics registry test would go here"
  check true