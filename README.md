[![Build Status](https://travis-ci.com/cherusk/prometheus_ss_exporter.svg?branch=master)](https://travis-ci.com/cherusk/prometheus_ss_exporter)

# prometheus_ss_exporter

Flows|Socket Statistics offering Exporter

# Grafana Sample

![sample](https://github.com/cherusk/prometheus_ss_exporter/blob/master/grafana_sample.png)

# Example Sample

```
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

# Hints 

Although the label space for individual flows is bounded by the underlying flowing constraints configured on kernel level, for certain, highly dynamic traffic flow patterns this exporter is infringing the recommendation as not to employ an "open" and so potentially gargantuan label spaces. That also holds for short amounts of times. Hence, one should deliberately consider following options depending on the specific granularity requirements and resources at hand. 

Apparent mitigation tactics are:
+ The --storage.tsdb.retention=<yours> option of the prometheus server to give bounds to the metrics label data held available can relieve capacity constraints significantly. Nigh this is not necessarily confined to ad-hoc oriented introspection employments. That's holding equally on vaster scale, e.g. when one is apt at forming a distinct retention (sub)hierarchy of servers, maybe within a set of prometheus federations.
+ To further deplete the flow metrics lable cardinality, use the data selection configration aspects of the exporter:
..+ Practically, skimm the **selection** section and for choosing the set of flows of interest.

# Install

```
    1) clone this repo
    2) do 
    # python setup.py install
```

# Author

Matthias Tafelmeier
