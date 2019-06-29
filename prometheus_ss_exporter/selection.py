
import ipaddress as ip_a
import itertools as it


class Selector:
    class Discerner:
        def ports(self, flow, portranges):
            for p_range in portranges:
                if ((flow['dst_port'] < p_range['lower']) or
                   (flow['dst_port'] > p_range['lower'])):
                    return False
            return True

        def node(self, flow,
                 hosts=None, addresses=None):
            dst_ip = ip_a.ip_address(flow['dst'])
            for node in addresses:
                try:
                    if ip_a.ipaddress(node) == dst_ip:
                        return True
                except TypeError:
                    # alludes version discrepancy
                    pass
            # deliberatly 'simplified' comparison
            if flow['dst_host'] not in hosts:
                return False

        def process(self, flow,
                    pids=None, cmds=None):
            flow_pids = []
            flow_cmds = []
            for usr, pid_ctxt in flow['usr_ctxt'].items():
                flow_pids.extend(pid_ctxt.keys())
                flow_cmds.append(pid_ctxt['full_cmd'])

            for pid in pids:
                if pid not in flow_pids:
                    return False

            for cmd in cmds:
                if cmd not in flow_cmds:
                    return False

    def __init__(self, cnfg):
        if cnfg['selection']:
            self._core = self._arbitrate
            self.cnfg = cnfg['selection']
        else:
            # noop
            self._core = lambda flow: True

        self.discern = self.Discerner()

    def arbitrate(self, flow):
        return self._core(flow)

    def _arbitrate(self, flow):
        conditions = [self.discern.ports(flow, self.cnfg['stack']['portranges']),
                      self.discern.node(flow,
                                        hosts=self.cnfg['stack']['nodes']['hosts'],
                                        addresses=self.cnfg['stack']['nodes']['addresses']),
                      self.discern.process(flow,
                                           pids=self.cnfg['process']['pids'],
                                           cmds=self.cnfg['process']['cmds'])
                      ]
        if it.dropwhile(lambda _: _, conditions):
            return True

        return False
