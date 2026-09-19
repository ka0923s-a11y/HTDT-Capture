from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.accuracy_benchmark.analyze import (
    BenchmarkError,
    analyze_files,
    build_report,
    canonical_report_bytes,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
OBSERVATIONS = (
    REPO_ROOT / "samples" / "accuracy-benchmark" / "synthetic-observations.json"
)
RULESET = (
    REPO_ROOT / "samples" / "accuracy-benchmark" / "provisional-ruleset-v1.json"
)


def load_fixture():
    observations = json.loads(OBSERVATIONS.read_text(encoding="utf-8"))
    ruleset = json.loads(RULESET.read_text(encoding="utf-8"))
    return observations, ruleset


class AccuracyBenchmarkTests(unittest.TestCase):
    def test_synthetic_fixture_passes_all_engineering_gates(self):
        report = analyze_files(OBSERVATIONS, RULESET)
        self.assertEqual(report["engineering_gate_status"], "pass")
        self.assertTrue(all(
            gate["status"] == "pass"
            for gate in report["gates"]
        ))
        self.assertEqual(
            report["metrics"]["dimensions"]["max_abs_error_m"],
            0.01,
        )
        self.assertLess(
            report["metrics"]["plane_residuals"]["rmse_m"],
            0.015,
        )
        self.assertLess(
            report["metrics"]["speaker_orientation"]["max_error_deg"],
            3.0,
        )
        self.assertEqual(
            len(report["metrics"]["depth"]["buckets"]),
            4,
        )

    def test_report_is_deterministic_for_identical_inputs(self):
        first = analyze_files(OBSERVATIONS, RULESET)
        second = analyze_files(OBSERVATIONS, RULESET)
        self.assertEqual(
            canonical_report_bytes(first),
            canonical_report_bytes(second),
        )

    def test_failed_threshold_is_preserved_as_fail(self):
        observations, ruleset = load_fixture()
        ruleset = copy.deepcopy(ruleset)
        ruleset["thresholds"]["dimension_max_abs_error_m"] = 0.001

        report = build_report(
            observations,
            ruleset,
            observations_sha256="a" * 64,
            ruleset_sha256="b" * 64,
        )

        self.assertEqual(report["engineering_gate_status"], "fail")
        gate = next(
            gate
            for gate in report["gates"]
            if gate["code"] == "dimension_max_abs_error_m"
        )
        self.assertEqual(gate["status"], "fail")
        self.assertEqual(gate["value"], 0.01)
        self.assertEqual(gate["threshold"], 0.001)

    def test_missing_depth_bucket_is_insufficient_not_pass(self):
        observations, ruleset = load_fixture()
        observations = copy.deepcopy(observations)
        observations["depth_observations"] = [
            sample
            for sample in observations["depth_observations"]
            if sample["reference_distance_m"] < 3.0
        ]

        report = build_report(
            observations,
            ruleset,
            observations_sha256="a" * 64,
            ruleset_sha256="b" * 64,
        )

        self.assertEqual(
            report["engineering_gate_status"],
            "insufficient_data",
        )
        self.assertTrue(any(
            gate["status"] == "insufficient_data"
            and gate["code"] == "depth_rmse_3_5m"
            for gate in report["gates"]
        ))

    def test_repeatability_requires_configured_repeat_count(self):
        observations, ruleset = load_fixture()
        observations = copy.deepcopy(observations)
        observations["dimension_observations"] = [
            sample
            for sample in observations["dimension_observations"]
            if not (
                sample["quantity"] == "room_width"
                and sample["scan_index"] == 3
            )
        ]

        report = build_report(
            observations,
            ruleset,
            observations_sha256="a" * 64,
            ruleset_sha256="b" * 64,
        )
        gate = next(
            gate
            for gate in report["gates"]
            if gate["code"] == "repeatability_population_sd_m"
        )
        self.assertEqual(gate["status"], "insufficient_data")
        self.assertEqual(
            report["engineering_gate_status"],
            "insufficient_data",
        )

    def test_required_device_metadata_fails_closed(self):
        observations, ruleset = load_fixture()
        observations = copy.deepcopy(observations)
        del observations["device_metadata"]["ar_configuration_profile_hash"]

        with self.assertRaises(BenchmarkError):
            build_report(
                observations,
                ruleset,
                observations_sha256="a" * 64,
                ruleset_sha256="b" * 64,
            )

    def test_direct_cli_execution_writes_report(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / "report.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(
                        REPO_ROOT
                        / "tools"
                        / "accuracy_benchmark"
                        / "analyze.py"
                    ),
                    str(OBSERVATIONS),
                    str(RULESET),
                    "--output",
                    str(output),
                ],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["engineering_gate_status"], "pass")


if __name__ == "__main__":
    unittest.main()
