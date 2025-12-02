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

import std/[osproc, json, strutils, tables, options, marshal]

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
    usrCtxt*: Table[string, Table[string, string]]         # user -> pid -> cmd

  SocketStats* = object
    flows*: seq[FlowInfo]

proc parseTcpInfo*(node: JsonNode): TcpInfo =
  ## Parse TCP info from JSON node
  let tcpInfo = node{"tcp_info"}

  # Initialize with default values
  result.rtt = 0.0
  result.sndCwnd = 0
  result.deliveryRate = 0
  result.dataSegsIn = 0
  result.dataSegsOut = 0

  # Check if tcp_info field exists and is an object
  if tcpInfo.isNil or tcpInfo.kind != JObject:
    # Return default values if tcp_info is missing or invalid
    return

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
  # Initialize with default values
  result.src = ""
  result.dst = ""
  result.srcPort = 0
  result.dstPort = 0
  result.dstHost = ""
  result.tcpInfo = TcpInfo(rtt: 0.0, sndCwnd: 0, deliveryRate: 0, dataSegsIn: 0,
      dataSegsOut: 0)
  result.usrCtxt = initTable[string, Table[string, string]]()

  # Check if node is valid
  if node.isNil or node.kind != JObject:
    return

  result.src = node{"src"}.getStr("")
  result.dst = node{"dst"}.getStr("")
  result.srcPort = node{"src_port"}.getInt(0)
  result.dstPort = node{"dst_port"}.getInt(0)
  result.dstHost = node{"dst_host"}.getStr("")
  result.tcpInfo = parseTcpInfo(node)
  result.usrCtxt = parseUserContext(node)

proc callSs2Utility*(): Option[SocketStats] =
  ## Call the ss2 utility as a standalone CLI binary
  try:
    # Call the standalone ss2 binary directly - no Python wrapper needed
    let cmd = "ss2"
    let args = @["--tcp", "--process"]

    # Execute the ss2 binary directly
    let (output, exitCode) = osproc.execCmdEx(cmd & " " & args.join(" "))

    if exitCode != 0:
      echo "ss2 command failed with exit code: ", exitCode
      echo "Error output: ", output
      return none(SocketStats)

    # Parse JSON output - should be clean JSON from standalone binary
    let jsonNode = parseJson(output)

    var socketStats = SocketStats()

    # Handle both old and new ss2 output formats
    var tcpNode: JsonNode = nil
    
    if jsonNode.kind == JArray:
      # New format: [{"TCP": {"flows": [...]}}]
      if jsonNode.len > 0:
        tcpNode = jsonNode[0]{"TCP"}
    elif jsonNode.kind == JObject:
      # Old format: {"TCP": {"flows": [...]}}
      tcpNode = jsonNode{"TCP"}
    
    if not tcpNode.isNil and tcpNode.kind == JObject:
      let flowsNode = tcpNode{"flows"}
      if not flowsNode.isNil and flowsNode.kind == JArray:
        # Found flows
        for flowNode in flowsNode.items():
          if not flowNode.isNil and flowNode.kind == JObject:
            let flow = parseFlowInfo(flowNode)
            socketStats.flows.add(flow)

    # Successfully parsed flows
    return some(socketStats)

  except JsonParsingError as e:
    # JSON parsing error
    echo "JSON parsing error: ", e.msg
    return none(SocketStats)
  except CatchableError as e:
    # Unexpected error
    echo "Unexpected error in ss2 utility: ", e.msg
    return none(SocketStats)

proc testSs2Wrapper*() =
  ## Test the ss2 wrapper functionality and output JSON
  echo "Testing ss2 wrapper..."

  let result = callSs2Utility()
  if result.isSome:
    let stats = result.get()
    echo "Successfully retrieved ", stats.flows.len, " flows"

    # Output detailed information about first few flows
    if stats.flows.len > 0:
      echo "\n=== FLOW DETAILS ==="
      for i, flow in stats.flows:
        if i >= 3: break # Only show first 3 flows
        echo "Flow ", i + 1, ":"
        echo "  Source: ", flow.src, ":", flow.srcPort
        echo "  Destination: ", flow.dst, ":", flow.dstPort
        echo "  RTT: ", flow.tcpInfo.rtt, " ms"
        echo "  Congestion Window: ", flow.tcpInfo.sndCwnd, " bytes"
        echo "  Delivery Rate: ", flow.tcpInfo.deliveryRate, " bps"
        echo "  Data Segments In: ", flow.tcpInfo.dataSegsIn
        echo "  Data Segments Out: ", flow.tcpInfo.dataSegsOut
        echo ""

    # Output full stats as JSON using native marshal
    echo "\n=== FULL JSON OUTPUT ==="
    echo $$stats
  else:
    echo "Failed to get socket statistics"

when isMainModule:
  testSs2Wrapper()
