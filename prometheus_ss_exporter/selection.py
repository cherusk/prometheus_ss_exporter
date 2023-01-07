
import ipaddress as ip_a
import itertools as it


class Selector:
    class Discerner:
        def ports(self, flow, portranges):
            if not portranges:
                return True

            for p_range in portranges:
                if ((flow['dst_port'] >= p_range['lower']) and
                   (flow['dst_port'] <= p_range['upper'])):
                    return True
            return False

        def peers(self, flow,
                  hosts=[], addresses=[], networks=[]):
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

            if networks:
                for network in networks:
                    _network = ip_a.IPv4Network(network)
                    dst_ip = ip_a.ip_address(flow['dst'])
                    if dst_ip in _network:
                        return True

            return False

        def process(self, flow,
                    pids=[], cmds=[]):
            flow_pids = []
            flow_cmds = []
            if flow.get('usr_ctxt'):
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
        cnfg = cnfg.get('logic')
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
        conditions = [ self.discern.ports(flow, self.cnfg.get('peering').get('portranges')) if self.cnfg.get('peering') else True,
                       self.discern.peers(flow, hosts=self.cnfg.get('peering').get('hosts'),
                                                addresses=self.cnfg.get('peering').get('addresses'),
                                                networks=self.cnfg.get('peering').get('networks')) if self.cnfg.get('peering') else True,
                       self.discern.process(flow, pids=self.cnfg.get('process').get('pids'),
                                                  cmds=self.cnfg.get('process').get('cmds')) if self.cnfg.get('process') else True
                      ]
        # if one condition false, we decline sample
        if list(it.filterfalse(lambda _: _, conditions)):
            return False

        return True
