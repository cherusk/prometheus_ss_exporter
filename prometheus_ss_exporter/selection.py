
import ipaddress as ip_a


class Selector:

    def __init__(self, cnfg):
        if cnfg['selection']:
            self.selector = self.arbitrate
        else:
            # noop
            self.selector = lambda flow: True

    def arbitrate(self, flow):

        targeted = self.cnfg['selection']
        for p_range in targeted['portranges']:
            if ((flow['dst_port'] < p_range['lower']) or
               (flow['dst_port'] > p_range['lower'])):
                return False

        dst_ip = ip_a.ip_address(flow['dst'])
        for node in targeted['nodes']['ips']:
            try:
                if ip_a.ipaddress(node) == dst_ip:
                    return True
            except TypeError:
                # alludes version discrepancy
                pass

        # deliberatly 'simplified' comparison
        if flow['dst_host'] not in targeted['nodes']['hosts']:
            return False

        flow_pids = []
        flow_cmds = []
        for usr, pid_ctxt in flow['usr_ctxt'].items():
            flow_pids.extend(pid_ctxt.keys())
            flow_cmds.append(pid_ctxt['full_cmd'])

        for pid in targeted['pids']:
            if pid not in flow_pids:
                return False

        for cmd in targeted['cmds']:
            if cmd not in flow_cmds:
                return False

        return True
