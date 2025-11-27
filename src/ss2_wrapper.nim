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
SS2 Wrapper Module
Calls the ss2 utility and parses its JSON output for socket statistics
]##

import std/[osproc, json, strutils, logging, tables, strscans, options]

type
  TcpInfo* = object
    rtt*: float
    sndCwnd*: int
    deliveryRate*: int
    dataSegsIn*: int
    dataSegsOut*: int

  FlowInfo* = object
    src*: string
    dst*: string
    srcPort*: int
    dstPort*: int
    dstHost*: string
    tcpInfo*: TcpInfo
    usrCtxt*: Table[string, Table[string, string]]  # user -> pid -> cmd

  SocketStats* = object
    flows*: seq[FlowInfo]

proc parseTcpInfo*(node: JsonNode): TcpInfo =
  ## Parse TCP info from JSON node
  let tcpInfo = node{"tcp_info"}
  
  result.rtt = tcpInfo{"rtt"}.getFloat(0.0)
  result.sndCwnd = tcpInfo{"snd_cwnd"}.getInt(0)
  result.deliveryRate = tcpInfo{"delivery_rate"}.getInt(0)
  result.dataSegsIn = tcpInfo{"data_segs_in"}.getInt(0)
  result.dataSegsOut = tcpInfo{"data_segs_out"}.getInt(0)

proc parseUserContext*(node: JsonNode): Table[string, Table[string, string]] =
  ## Parse user context (process information) from JSON
  result = initTable[string, Table[string, string]]()
  
  let usrCtxtNode = node{"usr_ctxt"}
  if usrCtxtNode.kind == JObject:
    for user, pidData in usrCtxtNode.pairs():
      result[user] = initTable[string, string]()
      if pidData.kind == JObject:
        for pid, cmdData in pidData.pairs():
          let fullCmd = cmdData{"full_cmd"}.getStr("")
          result[user][pid] = fullCmd

proc parseFlowInfo*(node: JsonNode): FlowInfo =
  ## Parse individual flow information from JSON
  result.src = node{"src"}.getStr("")
  result.dst = node{"dst"}.getStr("")
  result.srcPort = node{"src_port"}.getInt(0)
  result.dstPort = node{"dst_port"}.getInt(0)
  result.dstHost = node{"dst_host"}.getStr("")
  result.tcpInfo = parseTcpInfo(node)
  result.usrCtxt = parseUserContext(node)

proc callSs2Utility*(): Option[SocketStats] =
  ## Call the ss2 utility and parse its JSON output
  try:
    # Call the ss2 utility - assuming it's in PATH or current directory
    let cmd = "python3"
    let args = @["-c", """
import sys
sys.path.insert(0, './prometheus_ss_exporter')
from prometheus_ss_exporter.stats import Gatherer
import json

gatherer = Gatherer()
stats = gatherer.provide_tcp_stats()
print(json.dumps(stats))
"""]
    
    info "Calling ss2 utility..."
    let (output, exitCode) = osproc.execCmdEx(cmd & " " & args.join(" "))
    
    if exitCode != 0:
      error "ss2 utility failed with exit code: ", exitCode
      error "Output: ", output
      return none(SocketStats)
    
    # Parse JSON output
    let jsonNode = parseJson(output)
    
    var socketStats = SocketStats()
    
    # Parse flows
    let flowsNode = jsonNode{"TCP"}{"flows"}
    if flowsNode.kind == JArray:
      for flowNode in flowsNode.items():
        let flow = parseFlowInfo(flowNode)
        socketStats.flows.add(flow)
    
    info "Successfully parsed ", socketStats.flows.len, " TCP flows"
    return some(socketStats)
    
  except JsonParsingError as e:
    error "Failed to parse ss2 JSON output: ", e.msg
    return none(SocketStats)
  except CatchableError as e:
    error "Error calling ss2 utility: ", e.msg
    return none(SocketStats)

proc testSs2Wrapper*() =
  ## Test the ss2 wrapper functionality
  echo "Testing ss2 wrapper..."
  
  let result = callSs2Utility()
  if result.isSome:
    let stats = result.get()
    echo "Successfully retrieved ", stats.flows.len, " flows"
    
    if stats.flows.len > 0:
      let firstFlow = stats.flows[0]
      echo "First flow: ", firstFlow.src, ":", firstFlow.srcPort, " -> ", 
           firstFlow.dst, ":", firstFlow.dstPort
      echo "RTT: ", firstFlow.tcpInfo.rtt, " ms"
      echo "Congestion Window: ", firstFlow.tcpInfo.sndCwnd
  else:
    echo "Failed to get socket statistics"

when isMainModule:
  testSs2Wrapper()