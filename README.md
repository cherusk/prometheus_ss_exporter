# Prometheus Socket Statistics Exporter

[![Docker Image](https://img.shields.io/badge/docker-ready-blue.svg)](https://ghcr.io/cherusk/prometheus_ss_exporter)

A Prometheus exporter that gathers Operating System Network Socket Statistics as metrics, providing deep insights into network performance and connection behavior.

## Overview

This exporter leverages [pyroute2](https://github.com/svinota/pyroute2) (specifically the ss2 module) to collect detailed TCP socket statistics from the Linux kernel, exposing them as Prometheus metrics for monitoring and alerting.

### Key Features

- **Real-time TCP metrics**: Round-trip time, congestion window, delivery rates
- **Histogram support**: Latency distributions and flow statistics
- **Flexible filtering**: Filter by process, network, or port ranges
- **Label compression**: Reduce metric cardinality with configurable folding

### Use Cases

- Network performance monitoring and troubleshooting
- TCP connection health tracking
- Application network behavior analysis
- Infrastructure capacity planning
- SLA monitoring and alerting

---
## Performance Considerations

Although the label space for individual flows is bounded by the underlying flow constraints configured at the kernel level, very dynamic traffic patterns with numerous flows being created and phased out can lead to an overwhelming label space, even for short periods.

Therefore, depending on your specific granularity requirements and available resources, consider the following mitigation strategies:

### Mitigation Strategies

**1. Prometheus Retention Configuration**
Use the `--storage.tsdb.retention=<duration>` option on your Prometheus server to bound the metric label data retention period. This can significantly relieve capacity constraints and is suitable for both ad-hoc introspection deployments and larger-scale scenarios within Prometheus federations.

**2. Flow Selection Filtering**
Reduce flow metric label cardinality by using the exporter's data selection configuration to limit collection to only flows with specific characteristics (process, network, port ranges, etc.).

**3. Label Compression**
Configure label folding options to compress flow identifiers and reduce metric cardinality while preserving essential information.

---
## Metrics Reference

The exporter exposes the following Prometheus metrics:

### Gauge Metrics

| Metric | Description | Labels |
|--------|-------------|--------|
| `tcp_rtt` | TCP round-trip time in milliseconds | `flow` - Connection identifier with source/destination IP and port |
| `tcp_cwnd` | TCP congestion window size | `flow` - Connection identifier with source/destination IP and port |
| `tcp_delivery_rate` | TCP delivery rate in bytes per second | `flow` - Connection identifier with source/destination IP and port |

### Histogram Metrics

| Metric | Description | Labels | Buckets |
|--------|-------------|--------|---------|
| `tcp_rtt_hist_ms` | TCP round-trip time distribution histogram | `le` - bucket boundary | Configurable (default: 0.001ms to 1000ms) |

### Counter Metrics

| Metric | Description | Labels |
|--------|-------------|--------|
| `tcp_data_segs_in` | Number of TCP data segments received | `flow` - Connection identifier with source/destination IP and port |
| `tcp_data_segs_out` | Number of TCP data segments sent | `flow` - Connection identifier with source/destination IP and port |

### Flow Label Format

The `flow` label contains connection information in the format:
```bash
flow="(SRC#<source_ip>|<source_port>)(DST#<dest_ip>|<dest_port>)"
```

Example:
```bash
flow="(SRC#192.168.10.58|39366)(DST#104.19.199.151|443)"
```

---

## Sample Metrics Output

```prometheus
# TYPE tcp_rtt gauge
tcp_rtt{flow="(SRC#192.168.10.58|39366)(DST#104.19.199.151|443)"} 53.376
tcp_rtt{flow="(SRC#192.168.10.58|50484)(DST#212.227.17.170|993)"} 39.129
tcp_rtt{flow="(SRC#127.0.0.1|58334)(DST#127.0.0.1|22)"} 2.178
tcp_rtt{flow="(SRC#127.0.0.1|43908)(DST#127.0.0.1|8020)"} 0.038
tcp_rtt{flow="(SRC#192.168.10.58|36918)(DST#104.16.233.151|443)"} 51.017
tcp_rtt{flow="(SRC#192.168.10.58|36534)(DST#172.217.22.6|443)"} 44.335
tcp_rtt{flow="(SRC#127.0.0.1|58640)(DST#127.0.0.1|5037)"} 0.011
tcp_rtt{flow="(SRC#192.168.10.58|47192)(DST#194.25.134.114|993)"} 36.689
tcp_rtt{flow="(SRC#192.168.10.58|42410)(DST#216.58.205.226|443)"} 40.242
tcp_rtt{flow="(SRC#192.168.10.58|54412)(DST#104.16.22.133|443)"} 56.069
tcp_rtt{flow="(SRC#192.168.10.58|50626)(DST#172.217.18.2|443)"} 46.931
tcp_rtt{flow="(SRC#127.0.0.1|5037)(DST#127.0.0.1|58640)"} 0.01
tcp_rtt{flow="(SRC#192.168.10.58|45014)(DST#192.30.253.124|443)"} 120.324
tcp_rtt{flow="(SRC#127.0.0.1|8020)(DST#127.0.0.1|43908)"} 0.015
# HELP tcp_cwnd tcp socket perflow congestionwindow stats
# TYPE tcp_cwnd gauge
tcp_cwnd{flow="(SRC#192.168.10.58|39366)(DST#104.19.199.151|443)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|50484)(DST#212.227.17.170|993)"} 10.0
tcp_cwnd{flow="(SRC#127.0.0.1|58334)(DST#127.0.0.1|22)"} 10.0
tcp_cwnd{flow="(SRC#127.0.0.1|43908)(DST#127.0.0.1|8020)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|36918)(DST#104.16.233.151|443)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|36534)(DST#172.217.22.6|443)"} 10.0
tcp_cwnd{flow="(SRC#127.0.0.1|58640)(DST#127.0.0.1|5037)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|47192)(DST#194.25.134.114|993)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|42410)(DST#216.58.205.226|443)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|54412)(DST#104.16.22.133|443)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|50626)(DST#172.217.18.2|443)"} 10.0
tcp_cwnd{flow="(SRC#127.0.0.1|5037)(DST#127.0.0.1|58640)"} 10.0
tcp_cwnd{flow="(SRC#192.168.10.58|45014)(DST#192.30.253.124|443)"} 10.0
tcp_cwnd{flow="(SRC#127.0.0.1|8020)(DST#127.0.0.1|43908)"} 10.0
# HELP tcp_rtt_hist_ms tcp flowslatency outline
# TYPE tcp_rtt_hist_ms histogram
tcp_rtt_hist_ms_bucket{le="0.1"} 4.0
tcp_rtt_hist_ms_bucket{le="0.5"} 0.0
tcp_rtt_hist_ms_bucket{le="1.0"} 0.0
tcp_rtt_hist_ms_bucket{le="5.0"} 1.0
tcp_rtt_hist_ms_bucket{le="10.0"} 0.0
tcp_rtt_hist_ms_bucket{le="50.0"} 5.0
tcp_rtt_hist_ms_bucket{le="100.0"} 3.0
tcp_rtt_hist_ms_bucket{le="200.0"} 1.0
tcp_rtt_hist_ms_bucket{le="500.0"} 0.0
tcp_rtt_hist_ms_bucket{le="+Inf"} 10.0
tcp_rtt_hist_ms_count 10.0
tcp_rtt_hist_ms_sum 24.0
```

---

## Configuration

The exporter is configured via a YAML file that controls metric collection, flow filtering, and label compression. Use the `--config` command line argument to specify the configuration file path.

### Configuration Structure

```yaml
---
# Core metrics collection configuration
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
    # [Optional] filtering rules
    process:
      pids: [1000, 2000]  # Specific process IDs
      cmds: ["nginx", "apache2"]  # Process names
    peering:
      addresses: ["8.8.8.8", "1.1.1.1"]  # Specific IPs
      networks: ["10.0.0.0/8", "192.168.0.0/16"]  # CIDR networks
      hosts: ["example.com"]  # Hostnames
    portRanges:
      - lower: 80
        upper: 443
      - lower: 8000
        upper: 9000
```

### Configuration Options

#### `logic.metrics`

Controls which metrics are collected and exposed.

**Histograms**
- `active`: Enable/disable histogram collection globally
- `rtt.active`: Enable TCP round-trip time histogram
- `rtt.bucketBounds`: Array of latency bucket boundaries in milliseconds

**Gauges**
- `active`: Enable/disable gauge collection globally
- `rtt.active`: Enable TCP round-trip time gauge
- `cwnd.active`: Enable TCP congestion window gauge
- `deliveryRate.active`: Enable TCP delivery rate gauge

**Counters**
- `active`: Enable/disable counter collection globally
- `dataSegsIn.active`: Enable incoming data segments counter
- `dataSegsOut.active`: Enable outgoing data segments counter

#### `logic.compression`

Reduces metric cardinality by compressing flow labels.

**Label Folding**
- `labelFolding`: Folding strategy
  - `"raw_endpoint"`: Full IP and port information
  - `"pid_condensed"`: Replace source IP/port with process ID
  
**Effect on Labels:**
```yaml
# raw_endpoint: flow="(SRC#192.168.10.58|39366)(DST#104.19.199.151|443)"
# pid_condensed: flow="(20005)(DST#104.19.199.151|443)"
```

#### `logic.selection`

Filter which flows to monitor. All sections are optional.

**Process Filtering**
```yaml
process:
  pids: [1000, 2000, 3000]  # Monitor flows from specific process IDs
  cmds: ["nginx", "apache2"] # Monitor flows from specific command names
```

**Network/Address Filtering**
```yaml
peering:
  addresses: ["8.8.8.8", "1.1.1.1"]  # Specific IP addresses
  networks: ["10.0.0.0/8", "192.168.0.0/16"]  # CIDR networks (IPv4 only)
  hosts: ["api.example.com", "db.internal"]  # Hostnames
```

**Port Range Filtering**
```yaml
portRanges:
  - lower: 80    # Port 80
    upper: 443   # Up to port 443
  - lower: 8000  # Port 8000
    upper: 9000  # Up to port 9000
```

### Example Configurations

**Minimal Configuration**
```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
    counters:
      active: true
```

**Web Server Monitoring**
```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
      deliveryRate: { active: true }
    histograms:
      latency:
        active: true
        bucket_bounds: [0.1, 0.5, 1, 5, 10, 50, 100, 200]
  selection:
    process:
      cmds: ["nginx", "apache2", "httpd"]
    portranges:
      - lower: 80
        upper: 443
```

**High-Cardinality Environment**
```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
    histograms:
      latency:
        active: true
        bucket_bounds: [1, 5, 10, 50, 100, 500]
  compression:
    labelFolding: "raw_endpoint"  # or "pid_condensed"
  selection:
    peering:
      networks: ["10.0.0.0/8", "192.168.0.0/16"]
```

---

## Deployment

### Docker Deployment

The exporter is available as a Docker container from the GitHub Container Registry. Due to the need to access kernel socket statistics, the container requires elevated privileges.

#### Basic Docker Run

```bash
# Set configuration
YOUR_CONFIG_FILE=/path/to/your/config.yml
RELEASE_TAG=2.1.1
IMAGE="ghcr.io/cherusk/prometheus_ss_exporter:${RELEASE_TAG}"

# Run the container
docker run --privileged --network host --pid host --rm \
           -p 8020:8020 \
           -v "${YOUR_CONFIG_FILE}:/config.yml:ro" \
           --name=prometheus_ss_exporter \
           "${IMAGE}" --port=8020 --config=/config.yml
```

#### Docker Compose

```yaml
version: '3.8'
services:
  prometheus_ss_exporter:
    image: ghcr.io/cherusk/prometheus_ss_exporter:2.1.1
    container_name: prometheus_ss_exporter
    privileged: true
    network_mode: host
    pid: host
    restart: unless-stopped
    ports:
      - "8020:8020"
    command: ["./prometheus_ss_exporter", "--port=8020", "--config=/config.yml"]
    volumes:
      - ./config.yml:/config.yml:ro
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8020/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

#### Security Considerations

**Why privileged mode is required:**
- The exporter needs access to `/proc/net/tcp` and other kernel network statistics
- Socket information is only accessible with elevated privileges
- The container needs to attach to the host network namespace to see all connections

**Alternative security approaches:**
```bash
# More restricted capabilities (if your kernel supports it)
docker run --cap-add=NET_RAW --cap-add=NET_ADMIN \
           --network host --pid host \
           -p 8020:8020 \
           -v "./config.yml:/config.yml:ro" \
           ghcr.io/cherusk/prometheus_ss_exporter:2.1.1 \
           --port=8020 --config=/config.yml
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: prometheus-ss-exporter
  labels:
    app: prometheus-ss-exporter
spec:
  selector:
    matchLabels:
      app: prometheus-ss-exporter
  template:
    metadata:
      labels:
        app: prometheus-ss-exporter
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: exporter
        image: ghcr.io/cherusk/prometheus_ss_exporter:2.1.1
        securityContext:
          privileged: true
        ports:
        - containerPort: 8020
          hostPort: 8020
          protocol: TCP
        command: ["./prometheus_ss_exporter", "--port=8020", "--config=/config.yml"]
        volumeMounts:
        - name: config
          mountPath: /config.yml
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: config
        configMap:
          name: ss-exporter-config
```

### Prometheus Configuration

Add the following to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'socket-stats'
    static_configs:
      - targets: ['localhost:8020']
    scrape_interval: 15s
    metrics_path: /metrics
    # Optional: Relabel to add instance information
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'socket-exporter'
```

---

## Real-World Examples

### Web Server Monitoring

Monitor HTTP/HTTPS traffic to your web servers:

```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
      cwnd: { active: true }
      deliveryRate: { active: true }
    histograms:
      latency:
        active: true
        bucket_bounds: [0.1, 0.5, 1, 5, 10, 50, 100, 200]
    counters:
      active: true
      dataSegsIn: { active: true }
      dataSegsOut: { active: true }
  selection:
    process:
      cmds: ["nginx", "apache2", "httpd"]
    portranges:
      - lower: 80
        upper: 443
```

**Use case:** Track web server response times and connection health for SLA monitoring.

### Database Performance Monitoring

Monitor database connection patterns:

```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
      deliveryRate: { active: true }
    histograms:
      latency:
        active: true
        bucket_bounds: [0.5, 1, 2, 5, 10, 25, 50, 100]
  compression:
    labelFolding: "raw_endpoint"  # or "pid_condensed"
  selection:
    process:
      cmds: ["postgres", "mysqld", "mongod", "oracle"]
    portranges:
      - lower: 3306   # MySQL
        upper: 3306
      - lower: 5432   # PostgreSQL
        upper: 5432
      - lower: 27017  # MongoDB
        upper: 27017
```

**Use case:** Monitor database connection latency and throughput for performance tuning.

### Microservices Environment

Monitor internal service communication:

```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
    histograms:
      latency:
        active: true
        bucket_bounds: [0.01, 0.05, 0.1, 0.5, 1, 5, 10]
  compression:
    labelFolding: "raw_endpoint"  # or "pid_condensed"
  selection:
    peering:
      networks: ["10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
    portranges:
      - lower: 8000
        upper: 9999
      - lower: 3000
        upper: 3999
```

**Use case:** Track microservice-to-service communication patterns in a Kubernetes cluster.

### High-Traffic Edge Server

Monitor edge servers with high connection volumes:

```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
    histograms:
      latency:
        active: true
        bucket_bounds: [1, 5, 10, 25, 50, 100, 250]
  compression:
    labelFolding: "raw_endpoint"  # or "pid_condensed"
  selection:
    # Monitor only external traffic (skip internal networks)
    peering:
      networks:
        exclude: ["10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12"]
    portranges:
      - lower: 80
        upper: 443
      - lower: 8080
        upper: 8080
```

**Use case:** Monitor CDN or edge server performance while managing metric cardinality.

### Development Environment

Lightweight monitoring for development:

```yaml
---
logic:
  metrics:
    gauges:
      active: true
      rtt: { active: true }
    counters:
      active: false
    histograms:
      active: false
  selection:
    process:
      cmds: ["node", "python", "java", "go"]
    portranges:
      - lower: 3000
        upper: 9000
```

**Use case:** Development debugging with minimal overhead and focused metrics.

### Prometheus Alerting Examples

```yaml
# Alert on high latency
- alert: HighSocketLatency
  expr: histogram_quantile(0.95, tcp_rtt_hist_ms_bucket) > 100
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High socket latency detected"
    description: "95th percentile latency is {{ $value }}ms"

# Alert on connection count
- alert: TooManyConnections
  expr: count(tcp_rtt) > 10000
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "Excessive number of TCP connections"
    description: "{{ $value }} TCP connections detected"

# Alert on delivery rate issues
- alert: LowDeliveryRate
  expr: avg(tcp_delivery_rate) < 1000
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Low TCP delivery rate"
    description: "Average delivery rate is {{ $value }} bytes/sec"
```
