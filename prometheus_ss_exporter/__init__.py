#!/usr/bin/python3
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

from prometheus_client.twisted import MetricsResource
from prometheus_client.core import (REGISTRY)

from twisted.web.server import Site
from twisted.web.resource import Resource
from twisted.internet import reactor

import time
import argparse
import yaml
from yaml import Loader
import os
from . import selection
from . import keep
from . import stats


class ss2_collector(object):

    def __init__(self, args, cnfg):
        self.gather = stats.Gatherer()
        self.selector = selection.Selector(cnfg)
        self.metrics = keep.MetricsKeep(cnfg)

    def collect(self):
        stats = self.gather.provide_tcp_stats()

        for flow in stats['TCP']['flows']:
            if self.selector.arbitrate(flow):
                self.metrics.consume_sample(flow)

        for gauge in self.metrics.gauges.values():
            yield gauge

        for histo in self.metrics.hists.values():
            buckets, _sum = histo['buckets'].reveal()
            histo['family'].add_metric([], buckets, _sum)
            yield histo['family']


class health_check(Resource):
    isLeaf = True

    def render_GET(self, request):
        return "200 OK"


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
                             "./cnfg.yml")
    )

    return parser.parse_args()


def setup_cnfg(_file):

    with open(_file, "r") as cnfg_f:
        cnfg = yaml.load(cnfg_f, Loader=Loader)

    return cnfg


def main():
    try:
        args = setup_args()
        cnfg = setup_cnfg(args.cnfg)
        port = int(args.port)
        REGISTRY.register(ss2_collector(args, cnfg))

        root = Resource()
        root.putChild(b'metrics', MetricsResource(registry=REGISTRY))
        root.putChild(b'health', health_check)

        factory = Site(root)
        reactor.listenTCP(port, factory)
        reactor.run()

    except KeyboardInterrupt:
        print("Ceasing operations")
        exit(0)


if __name__ == '__main__':
    main()
