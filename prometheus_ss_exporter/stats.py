
import collections
import sys
import io
import json
import logging


import importlib.machinery
import pyroute2.netlink.diag.ss2 as ss2

from . import utils


class Gatherer:
    def __init__(self):
        self._reset_io()

        self.args = collections.namedtuple('args', ['tcp',
                                                    'listen',
                                                    'all',
                                                    'resolve',
                                                    'unix',
                                                    'process'])
        self.args.tcp = True
        self.args.process = True
        self.args.resolve = True
        self.args.listen = False
        self.args.all = False
        self.args.unix = False

    def _reset_io(self):
        if sys.version_info[0] == 2:
            import cStringIO
            self.stream_sink = cStringIO.StringIO()
        else:
            self.stream_sink = io.StringIO()

    def provide_tcp_stats(self):
        _stdout = sys.stdout
        sys.stdout = self.stream_sink

        ss2.run(self.args)

        # catch stdout
        sys.stdout = _stdout
        sk_stats_raw = self.stream_sink.getvalue()

        self._reset_io()

        sk_stats_parsed = dict()
        try:
            sk_stats_parsed = json.loads(sk_stats_raw)
        except json.decoder.JSONDecodeError as err:
            logging.error("Failed parsing sample")
            logging.error("-----")
            logging.error(sk_stats_parsed)
            logging.error("-----")

        return sk_stats_parsed


class Condenser:

    def __init__(self, cnfg):
        attr = "_form_{0}_metric_key".format(cnfg['logic']
                                                 ['compression']
                                                 ['label_folding']
                                                 ['origin'])
        self._former = getattr(self, attr)

    def _form_raw_endpoint_metric_key(self, flow):
        key = "(SRC#{src}|{src_port})(DST#{dst}|{dst_port})".format(**flow)
        return key

    def _form_pid_condensed_metric_key(self, flow):
        key = None
        try:
            pids = list()
            for usr, pid_ctxt in flow['usr_ctxt'].items():
                pids.extend(pid_ctxt.keys())
            key_suffix = "(DST#{dst}|{dst_port})".format(**flow)
            key = "({0}){1}".format(",".join(pids),
                                    key_suffix)
        except KeyError:
            logging.error("Error: Lacking usr_ctxt \n Flow: %s", flow)

        return key

    def shape_key(self, flow):
        return self._former(flow)
