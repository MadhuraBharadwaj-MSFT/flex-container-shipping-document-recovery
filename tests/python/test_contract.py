import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))

from demo_api import prepare_submission
from message_tracking import summarize


class ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.samples = json.loads(
            (ROOT / "samples" / "shipments.json").read_text()
        )

    def test_valid_sample_does_not_expect_repair(self):
        run, shipment = prepare_submission(
            {
                "request_id": "a" * 32,
                "shipment": self.samples["valid"],
            }
        )
        self.assertFalse(run["repair_expected"])
        self.assertEqual("a" * 32, shipment["shipment_id"])

    def test_malformed_sample_expects_repair(self):
        run, shipment = prepare_submission(
            {
                "request_id": "b" * 32,
                "shipment": self.samples["malformed"],
            }
        )
        self.assertTrue(run["repair_expected"])
        self.assertEqual("b" * 32, shipment["shipmentId"])

    def test_flow_summary_uses_highest_confirmed_stage(self):
        flow = summarize(
            [
                {"stage": "received", "observed_at": "2026-01-01T00:00:01Z"},
                {"stage": "rejected", "observed_at": "2026-01-01T00:00:02Z"},
                {"stage": "requeued", "observed_at": "2026-01-01T00:00:03Z"},
            ]
        )
        self.assertEqual("requeued", flow["latest"])


if __name__ == "__main__":
    unittest.main()
