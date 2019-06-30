
import unittest
import prometheus_ss_exporter.keep as keeps


class KeepsTesting(unittest.TestCase):

    def setUp(self):
        bounds = [1.00,
                  5.00,
                  10.00]
        self.keep = keeps.BucketKeep(bounds)

    def test_bucket_keep_filling(self):

        outliers = [11.00, 15.00]
        for o in outliers:
            self.keep.enter(o)

        buckets, _sum = self.keep.reveal()
        self.assertEqual(_sum, 3)
        count = buckets[-1][1]
        self.assertEqual(count, 3)

        tame_samples = [0.10, 0.50, 4.00, 6.00]
        for sample in tame_samples:
            self.keep.enter(sample)

        buckets, _sum = self.keep.reveal()
        self.assertEqual(_sum, 11)
        count = buckets[-1][1]
        self.assertEqual(count, 7)
