
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
        ss2_script = utils.which('ss2')
        self.ss2 = imp.load_source('ss2', ss2_script)

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
        self._form_flow_key = getattr(self, "_form_%s_metric_key" %
                                            cnfg['logic']
                                            ['flow_label']
                                            ['origin_folding'])

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
