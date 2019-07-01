
import ipaddress as ip_a
import itertools as it


class Selector:
    class Discerner:
        def ports(self, flow, portranges):
            for p_range in portranges:
                if ((flow['dst_port'] < p_range['lower']) or
                   (flow['dst_port'] > p_range['upper'])):
                    return False
            return True

        def peers(self, flow,
                  hosts=[], addresses=[]):
            if addresses:
                dst_ip = ip_a.ip_address(flow['dst'])
                for node in addresses:
                    try:
                        if ip_a.ip_address(node) == dst_ip:
                            return True
                    except TypeError:
                        # alludes version discrepancy
                        pass
            # deliberatly 'simplified' comparison
            if hosts:
                if flow['dst_host'] in hosts:
                    return True

            return False

        def process(self, flow,
                    pids=[], cmds=[]):
            flow_pids = []
            flow_cmds = []
            for usr, pid_ctxt in flow['usr_ctxt'].items():
                for pid, cmd_ctxt in pid_ctxt.items():
                    flow_pids.append(pid)
                    flow_cmds.append(cmd_ctxt['full_cmd'])

            for pid in pids:
                if pid in flow_pids:
                    return True

            for cmd in cmds:
                if cmd in flow_cmds:
                    return True
            return False

    def __init__(self, cnfg):
        key = 'selection'
        if (key in cnfg.keys() and
           cnfg[key]):
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
                      self.discern.peers(flow,
                                         hosts=self.cnfg['stack']['nodes']['hosts'],
                                         addresses=self.cnfg['stack']['nodes']['addresses']),
                      self.discern.process(flow,
                                           pids=self.cnfg['process']['pids'],
                                           cmds=self.cnfg['process']['cmds'])
                      ]
        if it.dropwhile(lambda _: _, conditions):
            return True

        return False
