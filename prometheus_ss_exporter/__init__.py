#!/usr/bin/env python
#
# MIT License
#  prometheus_ss_exporter
# Copyright (c) 2018 Matthias Tafelmeier
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

from prometheus_client import start_http_server
from prometheus_client.core import (GaugeMetricFamily,
                                    HistogramMetricFamily,
                                    REGISTRY)
import json
import sys
import imp
import time
import os
import io
import collections
import argparse
import bisect
import yaml
import ipaddress as ip_a
import logging


class Utils:
    @staticmethod
    def which(executable, fail=False):
        def is_executable(filename):
            return (os.path.isfile(filename) and
                    os.access(filename, os.X_OK))

        pathname, filename = os.path.split(executable)
        if pathname:
            if is_executable(executable):
                return executable
        else:
            for path in [i.strip('""')
                         for i in
                         os.environ["PATH"].split(os.pathsep)]:
                filename = os.path.join(path, executable)
                if is_executable(filename):
                    return filename

        if fail:
            raise RuntimeError("No %s binary found in PATH." % executable)


class bucket_keep(object):
    _INF = "+Inf"

    def __init__(self, bounds):
        self.values = [0 for _ in bounds]
        self.bucket_bounds = bounds

    def _incr(self, idx):
        self.values[idx] = self.values[idx] + 1

    def enter(self, sample):
        idx = bisect.bisect(self.bucket_bounds, sample)
        self._incr(idx)

    def reveal(self):
        count = len(self.values) + 1
        sum_vals = sum(self.values) + count

        buckets = [[str(bound), val]
                   for bound, val
                   in zip(self.bucket_bounds, self.values)]
        buckets.append([self._INF, count])

        return buckets, sum_vals


class ss2_collector(object):

    def __init__(self, args, cnfg):
        ss2_script = Utils.which('ss2')
        self.ss2 = imp.load_source('ss2', ss2_script)

        self._form_flow_key = getattr(self, "_form_%s_metric_key" %
                                            cnfg['logic']
                                            ['flow_label']
                                            ['origin_folding'])
        if cnfg['selection']:
            self.selector = self.is_selected
        else:
            # noop
            self.selector = lambda flow: True
        self.cnfg = cnfg

        self._reset_io()

    def _reset_io(self):
        if sys.version_info[0] == 2:
            import cStringIO
            self.stream_sink = cStringIO.StringIO()
        else:
            self.stream_sink = io.StringIO()

    def _gather_tcp_stats(self):
        args = collections.namedtuple('args', ['tcp',
                                               'listen',
                                               'all',
                                               'resolve',
                                               'unix',
                                               'process'])
        args.tcp = True
        args.process = True
        args.resolve = True
        args.listen = False
        args.all = False
        args.unix = False

        _stdout = sys.stdout
        sys.stdout = self.stream_sink

        self.ss2.run(args)

        # catch stdout
        sys.stdout = _stdout
        sk_stats_raw = self.stream_sink.getvalue()

        self._reset_io()

        return json.loads(sk_stats_raw)

    def _form_raw_endpoint_metric_key(self, flow):
        key = "(SRC#%s|%s)(DST#%s|%s)" % (flow['src'],
                                          flow['src_port'],
                                          flow['dst'],
                                          flow['dst_port'])
        return key

    def _form_pid_condensed_metric_key(self, flow):
        pids = []
        key = ""
        try:
            for usr, pid_ctxt in flow['usr_ctxt'].items():
                    pids.extend(pid_ctxt.keys())
            key = "(%s)(DST#%s|%s)" % (",".join(pids),
                                       flow['dst'],
                                       flow['dst_port'])
        except KeyError:
            logging.error("Error: Lacking usr_ctxt \n Flow: %s", flow)

        return key

    def _stage_metrics(self):
        self.hists = {}
        hgram_cnfg = (self.cnfg['logic']
                               ['histograms'])
        if (hgram_cnfg['active']):
            if (hgram_cnfg['latency']
                          ['active']):
                self.hists['rtt'] = {
                            'family': HistogramMetricFamily('tcp_rtt_hist',
                                                            'tcp flows'
                                                            'latency outline',
                                                            unit='ms'),
                            'buckets': bucket_keep(self.cnfg['logic']
                                                            ['histograms']
                                                            ['latency']
                                                            ['bucket_bounds'])
                            }
        self.gauges = {}
        g_cnfg = (self.cnfg['logic']
                           ['gauges'])
        if (g_cnfg['active']):
            if g_cnfg['rtt']['active']:
                self.gauges['rtt'] = GaugeMetricFamily('tcp_rtt',
                                                       'tcp socket stats per'
                                                       'flow latency[rtt]',
                                                       labels=['flow'])
            if g_cnfg['cwnd']['active']:
                self.gauges['snd_cwnd'] = GaugeMetricFamily('tcp_cwnd',
                                                            'tcp socket per'
                                                            'flow congestion'
                                                            'window stats',
                                                            labels=['flow'])

            if g_cnfg['delivery_rate']['active']:
                self.gauges['delivery_rate'] = GaugeMetricFamily('tcp_delivery_rate',
                                                                 'tcp socket per'
                                                                 'flow delivery rate',
                                                                 labels=['flow'],
                                                                 unit='bytes')
        self.counters = {}
        c_cnfg = (self.cnfg['logic']
                           ['counters'])
        if (c_cnfg['active']):
            if (c_cnfg['data_segs_in']['active']):
                self.counters['data_segs_in'] = CounterMetricFamily('tcp_data_segs_in',
                                                                    'tcp per'
                                                                    'flow received'
                                                                    'data segments',
                                                                    labels=['flow'],
                                                                    unit='segments')

            if (c_cnfg['data_segs_out']['active']):
                self.counters['data_segs_out'] = CounterMetricFamily('tcp_data_segs_out',
                                                                     'tcp per'
                                                                     'flow received'
                                                                     'data segments',
                                                                     labels=['flow'],
                                                                     unit='segments')

    def is_selected(self, flow):

        targeted = self.cnfg['selection']
        for p_range in targeted['portranges']:
            if ((flow['dst_port'] < p_range['lower']) or
               (flow['dst_port'] > p_range['lower'])):
                return False

        dst_ip = ip_a.ip_address(flow['dst'])
        for node in targeted['nodes']['ips']:
            try:
                if ip_a.ipaddress(node) == dst_ip:
                    return True
            except TypeError:
                # alludes version discrepancy
                pass

        # deliberatly 'simplified' comparison
        if flow['dst_host'] not in targeted['nodes']['hosts']:
            return False

        flow_pids = []
        flow_cmds = []
        for usr, pid_ctxt in flow['usr_ctxt'].items():
            flow_pids.extend(pid_ctxt.keys())
            flow_cmds.append(pid_ctxt['full_cmd'])

        for pid in targeted['pids']:
            if pid not in flow_pids:
                return False

        for cmd in targeted['cmds']:
            if cmd not in flow_cmds:
                return False

        return True

    def consume_sample(self, flow):
        key = self._form_flow_key(flow)
        try:
            for g_k, gauge in self.gauges.items():
                gauge.add_metric([key], flow['tcp_info'][g_k])

            for h_k, histo in self.hists.items():
                    histo['buckets'].enter(flow['tcp_info'][h_k])
        except KeyError as e:
            logging.error("Flow: %s\n Cause: %s\n", flow, e)

    def collect(self):
        stats = self._gather_tcp_stats()

        self._stage_metrics()

        for flow in stats['TCP']['flows']:
            if self.selector(flow):
                self.consume_sample(flow)

        for gauge in self.gauges.values():
            yield gauge

        for h_k, histo in self.hists.items():
            buckets, _sum = histo['buckets'].reveal()
            histo['family'].add_metric([], buckets, _sum)
            yield histo['family']


def setup_args():
    parser = argparse.ArgumentParser(
        description='prometheus socket statistics exporter'
    )
    parser.add_argument(
        '-p', '--port',
        metavar='port',
        required=False,
        type=int,
        help='Listen to this port',
        default=8020
    )
    parser.add_argument(
        '-c', '--cnfg',
        metavar='CNFG',
        required=False,
        type=str,
        help='Exporter config file',
        default=os.path.join(os.path.dirname(os.path.realpath(__file__)),
                             "../cnfg.yml")
    )

    return parser.parse_args()


def setup_cnfg(_file):

    with open(_file, "r") as cnfg_f:
        cnfg = yaml.load(cnfg_f)

    return cnfg['cnfg']


def main():
    try:
        args = setup_args()
        cnfg = setup_cnfg(args.cnfg)
        print cnfg
        port = int(args.port)
        REGISTRY.register(ss2_collector(args, cnfg))
        start_http_server(port)
        print("Serving at port: %s" % port)
        while True:
            time.sleep(100)
    except KeyboardInterrupt:
        print("Ceasing operations")
        exit(0)


if __name__ == '__main__':
    main()
