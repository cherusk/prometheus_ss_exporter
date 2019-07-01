
import unittest
import prometheus_ss_exporter.selection as selection


class SelectorTesting(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.discerner = selection.Selector.Discerner()

    def test_peers_decline(self):
        selector_addr = ["10.0.1.10"]
        flow = {'dst': '91.189.92.41'}

        outcome = SelectorTesting.discerner.peers(flow,
                                                  addresses=selector_addr)
        self.assertFalse(outcome)

        selector_hosts = ["test.leave.org"]
        flow = {'dst_host': 'test.root.org'}
        outcome = SelectorTesting.discerner.peers(flow,
                                                  hosts=selector_hosts)
        self.assertFalse(outcome)

    def test_peers_accept_test(self):
        selector_addr = ["2003:f1:e3cc:1966:feaa:14ff:fe1c:5dea"]
        flow = {'dst': '2003:f1:e3cc:1966:feaa:14ff:fe1c:5dea'}

        outcome = SelectorTesting.discerner.peers(flow,
                                                  addresses=selector_addr)
        self.assertTrue(outcome)

        selector_hosts = ["test.leave.org"]
        flow = {'dst_host': 'test.leave.org'}
        outcome = SelectorTesting.discerner.peers(flow,
                                                  hosts=selector_hosts)
        self.assertTrue(outcome)

    def test_port_decline_test(self):
        selector_range = [{'lower': 1000, 'upper': 2000}]
        flow = {'dst_port': 100}
        outcome = SelectorTesting.discerner.ports(flow,
                                                  portranges=selector_range)
        self.assertFalse(outcome)

    def test_port_accept_test(self):
        selector_range = [{'lower': 1000, 'upper': 2000}]
        flow = {'dst_port': 1500}
        outcome = SelectorTesting.discerner.ports(flow,
                                                  portranges=selector_range)
        self.assertTrue(outcome)

    def test_process_decline_test(self):
        selector_pids = [100]
        flow = {'usr_ctxt': {'other_bin': {101: {'full_cmd': 'other'}}}}
        outcome = SelectorTesting.discerner.process(flow,
                                                    pids=selector_pids)
        self.assertFalse(outcome)

        selector_cmds = ['server']
        flow = {'usr_ctxt': {'other_bin': {101: {'full_cmd': 'other'}}}}
        outcome = SelectorTesting.discerner.process(flow,
                                                    cmds=selector_cmds)
        self.assertFalse(outcome)

    def test_process_accept_test(self):
        selector_pids = [100]
        flow = {'usr_ctxt': {'server': {100: {'full_cmd': 'server'}}}}
        outcome = SelectorTesting.discerner.process(flow,
                                                    pids=selector_pids)
        self.assertTrue(outcome)

        selector_cmds = ['server']
        flow = {'usr_ctxt': {'server': {101: {'full_cmd': 'server'}}}}
        outcome = SelectorTesting.discerner.process(flow,
                                                    cmds=selector_cmds)
        self.assertTrue(outcome)
