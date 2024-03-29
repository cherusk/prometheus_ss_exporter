
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

    def provide_tcp_stats(self):

        ss2.RUN_AS_MODULE = True

        sk_stats_all = ss2.run(self.args)

        sk_stats = sk_stats_all[0] # we only query for TCP

        return sk_stats


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
