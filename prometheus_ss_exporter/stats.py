
import collections
import sys
import io
import json
import logging


import importlib.machinery

from . import utils


class Gatherer:
    def __init__(self):
        self._load_logic()
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

    def _load_logic(self):
        ss2_script_path = utils.which('ss2')
        self.ss2 = (importlib.
                    machinery.
                    SourceFileLoader('ss2',
                                     ss2_script_path).load_module())

    def _reset_io(self):
        if sys.version_info[0] == 2:
            import cStringIO
            self.stream_sink = cStringIO.StringIO()
        else:
            self.stream_sink = io.StringIO()

    def provide_tcp_stats(self):
        _stdout = sys.stdout
        sys.stdout = self.stream_sink

        self.ss2.run(self.args)

        # catch stdout
        sys.stdout = _stdout
        sk_stats_raw = self.stream_sink.getvalue()

        self._reset_io()

        return json.loads(sk_stats_raw)


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
            key = "({0})(DST#{dst}|{dst_port})".format(",".join(pids))
            key = key.format(**flow)
        except KeyError:
            logging.error("Error: Lacking usr_ctxt \n Flow: %s", flow)

        return key

    def shape_key(self, flow):
        return self._former(flow)
