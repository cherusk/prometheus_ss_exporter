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


from prometheus_client.core import (GaugeMetricFamily,
                                    HistogramMetricFamily,
                                    CounterMetricFamily)
import logging
import bisect
from . import stats


class BucketKeep(object):
    _INF = "+Inf"

    def __init__(self, bounds):
        self.values = [0 for _ in bounds]
        self.bucket_bounds = bounds

        self.outlier_thresh = self.bucket_bounds[-1]
        self.outlier_count = 0

    def enter(self, sample):
        if sample > self.outlier_thresh:
            self.outlier_count += 1
            return

        idx = bisect.bisect(self.bucket_bounds, sample)
        self.values[idx] += 1

    def reveal(self):
        sum_vals = sum(self.values)
        count = sum([sum_vals, self.outlier_count, 1])

        buckets = [[str(bound), val]
                   for bound, val
                   in zip(self.bucket_bounds, self.values)]
        buckets.append([self._INF, count])

        sum_all = sum_vals + count
        return buckets, sum_all


class MetricsKeep:

    def __init__(self, cnfg):
        self.condenser = stats.Condenser(cnfg)
        self._stage(cnfg)

    def _stage(self, cnfg):
        metrics_cnfg = cnfg['logic']['metrics']
        for aspect in ['histograms',
                       'gauges',
                       'counters']:
            if metrics_cnfg[aspect]['active']:
                stager = getattr(self,
                                 "_stage_{0}".format(aspect))
                stager(metrics_cnfg[aspect])

    def _stage_histograms(self, cnfg):
        self.hists = dict()
        if (cnfg['latency']
                ['active']):
            self.hists['rtt'] = {
                        'family': HistogramMetricFamily('tcp_rtt_hist',
                                                        'tcp flows'
                                                        'latency outline',
                                                        unit='ms'),
                        'buckets': BucketKeep(cnfg['latency']
                                              ['bucket_bounds'])
                            }

    def _stage_gauges(self, cnfg):
        self.gauges = dict()
        if cnfg['rtt']['active']:
            self.gauges['rtt'] = GaugeMetricFamily('tcp_rtt',
                                                   'tcp socket stats per'
                                                   'flow latency[rtt]',
                                                   labels=['flow'])
        if cnfg['cwnd']['active']:
            self.gauges['snd_cwnd'] = GaugeMetricFamily('tcp_cwnd',
                                                        'tcp socket per'
                                                        'flow congestion'
                                                        'window stats',
                                                        labels=['flow'])

        if cnfg['delivery_rate']['active']:
            self.gauges['delivery_rate'] = GaugeMetricFamily('tcp_delivery_rate',
                                                             'tcp socket per'
                                                             'flow delivery rate',
                                                             labels=['flow'],
                                                             unit='bytes')

    def _stage_counters(self, cnfg):
        self.counters = dict()
        if (cnfg['data_segs_in']['active']):
            self.counters['data_segs_in'] = CounterMetricFamily('tcp_data_segs_in',
                                                                'tcp per'
                                                                'flow received'
                                                                'data segments',
                                                                labels=['flow'],
                                                                unit='segments')

        if (cnfg['data_segs_out']['active']):
            self.counters['data_segs_out'] = CounterMetricFamily('tcp_data_segs_out',
                                                                 'tcp per'
                                                                 'flow received'
                                                                 'data segments',
                                                                 labels=['flow'],
                                                                 unit='segments')

    def consume_sample(self, flow):
        flow_key = self.condenser.shape_key(flow)
        try:
            for gauge_key, gauge in self.gauges.items():
                gauge.add_metric([flow_key], flow['tcp_info'][gauge_key])

            for histo_key, histo in self.hists.items():
                    histo['buckets'].enter(flow['tcp_info'][histo_key])
        except KeyError as e:
            logging.error("Flow: %s\n Cause: %s\n", flow, e)
