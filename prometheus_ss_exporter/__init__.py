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
                                    REGISTRY)
import json
import sys
import imp
import time
import os
import re
import io
import collections
import argparse


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

#class flow_keep():


class ss2_collector(object):

    def __init__(self, args):
        ss2_script = Utils.which('ss2')
        self.ss2 = imp.load_source('ss2', ss2_script)
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

    def _form_metric_key(self, flow):
        key = "%s|%s|%s|%s" % (flow['src'],
                               flow['src_port'],
                               flow['dst'],
                               flow['dst_port'])
        return key

    def collect(self):
        stats = self._gather_tcp_stats()

        gauges = {
                'rtt': GaugeMetricFamily('tcp_rtt',
                                         'tcp socket stats per'
                                         'flow latency[rtt]',
                                         labels=['flow']),
                'snd_cwnd':  GaugeMetricFamily('tcp_cwnd',
                                               'tcp socket per'
                                               'flow congestion window stats',
                                               labels=['flow'])
                }
        for flow in stats['TCP']['flows']:
            key = self._form_metric_key(flow)
            for g_k, gauge in gauges.items():
                gauge.add_metric([key], flow['tcp_info'][g_k])

        for gauge in gauges.values():
            yield gauge


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

    return parser.parse_args()


def main():
    try:
        args = setup_args()
        port = int(args.port)
        REGISTRY.register(ss2_collector(args))
        start_http_server(port)
        print("Serving at port: %s" % port)
        while True:
            time.sleep(100)
    except KeyboardInterrupt:
        print("Ceasing operations")
        exit(0)


if __name__ == '__main__':
    main()
