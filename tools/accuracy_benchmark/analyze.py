"""Deterministic derived metrics for HTDT-Capture accuracy benchmarks.

Raw observations remain the evidence authority. This module computes a
versioned engineering report without replacing or mutating observations.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any


OBSERVATION_SCHEMA = "htdt.capture.accuracy-benchmark-observations"
RULESET_SCHEMA = "htdt.capture.accuracy-benchmark-ruleset"
REPORT_SCHEMA = "htdt.capture.accuracy-benchmark-report"
SCHEMA_VERSION = "1.0.0"


class BenchmarkError(ValueError):
    pass


def _finite_number(value: Any, field: str) -> float:
    if (
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or not math.isfinite(value)
    ):
        raise BenchmarkError(f"{field} must be a finite number")
    return float(value)


def _nonnegative(value: Any, field: str) -> float:
    result = _finite_number(value, field)
    if result < 0:
        raise BenchmarkError(f"{field} must be non-negative")
    return result


def _vec3(value: Any, field: str) -> tuple[float, float, float]:
    if not isinstance(value, list) or len(value) != 3:
        raise BenchmarkError(f"{field} must contain exactly three numbers")
    return tuple(
        _finite_number(component, f"{field}[{index}]")
        for index, component in enumerate(value)
    )


def _distance(lhs: tuple[float, ...], rhs: tuple[float, ...]) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(lhs, rhs)))


def _mean(values: list[float]) -> float:
    if not values:
        raise BenchmarkError("mean requires at least one value")
    return sum(values) / len(values)


def _rmse(values: list[float]) -> float:
    if not values:
        raise BenchmarkError("RMSE requires at least one value")
    return math.sqrt(sum(value * value for value in values) / len(values))


def _population_sd(values: list[float]) -> float:
    if not values:
        raise BenchmarkError("standard deviation requires values")
    center = _mean(values)
    return math.sqrt(
        sum((value - center) ** 2 for value in values) / len(values)
    )


def _round(value: float) -> float:
    return round(float(value), 12)


def _require_document(
    document: Any,
    *,
    schema: str,
    label: str,
) -> dict:
    if not isinstance(document, dict):
        raise BenchmarkError(f"{label} root must be an object")
    if document.get("schema") != schema:
        raise BenchmarkError(
            f"unexpected {label} schema: {document.get('schema')!r}"
        )
    if document.get("schema_version") != SCHEMA_VERSION:
        raise BenchmarkError(
            f"unsupported {label} schema version: "
            f"{document.get('schema_version')!r}"
        )
    return document


def _array(document: dict, key: str) -> list:
    value = document.get(key)
    if not isinstance(value, list):
        raise BenchmarkError(f"{key} must be an array")
    return value


def _required_text(document: dict, key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise BenchmarkError(f"{label}.{key} must be a non-empty string")
    return value


def _validate_observation_metadata(observations: dict) -> None:
    device = observations.get("device_metadata")
    protocol = observations.get("capture_protocol")
    instrument = observations.get("reference_instrument")
    if not isinstance(device, dict):
        raise BenchmarkError("device_metadata must be an object")
    if not isinstance(protocol, dict):
        raise BenchmarkError("capture_protocol must be an object")
    if not isinstance(instrument, dict):
        raise BenchmarkError("reference_instrument must be an object")

    for key in (
        "device_model_identifier",
        "os_version",
        "app_version",
        "app_build",
        "capability_profile_ref",
        "ar_configuration_profile_hash",
    ):
        _required_text(device, key, "device_metadata")

    configuration_hash = device["ar_configuration_profile_hash"]
    if (
        len(configuration_hash) != 64
        or any(character not in "0123456789abcdef" for character in configuration_hash)
    ):
        raise BenchmarkError(
            "device_metadata.ar_configuration_profile_hash "
            "must be lowercase SHA-256 hex"
        )

    for key in ("trajectory", "operator_id", "room_scale"):
        _required_text(protocol, key, "capture_protocol")
    repeated_scan_count = protocol.get("repeated_scan_count")
    if not isinstance(repeated_scan_count, int) or repeated_scan_count < 1:
        raise BenchmarkError(
            "capture_protocol.repeated_scan_count must be a positive integer"
        )

    for key in (
        "instrument_class",
        "make_model",
        "calibration_status",
        "calibration_date",
    ):
        _required_text(instrument, key, "reference_instrument")
    _nonnegative(
        instrument.get("stated_uncertainty_m"),
        "reference_instrument.stated_uncertainty_m",
    )


def _gate(
    code: str,
    value: float | None,
    threshold: float,
    unit: str,
    *,
    sufficient: bool = True,
) -> dict:
    if value is None or not sufficient:
        status = "insufficient_data"
        encoded_value = None if value is None else _round(value)
    else:
        status = "pass" if value <= threshold else "fail"
        encoded_value = _round(value)
    return {
        "code": code,
        "status": status,
        "value": encoded_value,
        "threshold": _round(threshold),
        "comparison": "<=",
        "unit": unit,
    }


def _overall_status(gates: list[dict]) -> str:
    statuses = {gate["status"] for gate in gates}
    if "fail" in statuses:
        return "fail"
    if "insufficient_data" in statuses:
        return "insufficient_data"
    return "pass"


def _dimensions(observations: dict, ruleset: dict) -> tuple[dict, list[dict]]:
    samples = _array(observations, "dimension_observations")
    errors: list[float] = []
    grouped: dict[str, list[float]] = {}

    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise BenchmarkError(
                f"dimension_observations[{index}] must be an object"
            )
        quantity = sample.get("quantity")
        if not isinstance(quantity, str) or not quantity:
            raise BenchmarkError(
                f"dimension_observations[{index}].quantity is invalid"
            )
        reference = _nonnegative(
            sample.get("reference_m"),
            f"dimension_observations[{index}].reference_m",
        )
        observed = _nonnegative(
            sample.get("observed_m"),
            f"dimension_observations[{index}].observed_m",
        )
        error = observed - reference
        errors.append(error)
        grouped.setdefault(quantity, []).append(observed)

    repeat_groups = []
    minimum_repeats = int(ruleset["minimum_repeat_scans"])
    repeatability_complete = bool(grouped)
    repeat_values: list[float] = []
    for quantity in sorted(grouped):
        values = grouped[quantity]
        sd = _population_sd(values)
        enough = len(values) >= minimum_repeats
        repeatability_complete = repeatability_complete and enough
        if enough:
            repeat_values.append(sd)
        repeat_groups.append(
            {
                "quantity": quantity,
                "sample_count": len(values),
                "population_sd_m": _round(sd),
                "minimum_required_samples": minimum_repeats,
                "sufficient": enough,
            }
        )

    metrics = {
        "sample_count": len(errors),
        "max_abs_error_m": (
            _round(max(abs(error) for error in errors))
            if errors
            else None
        ),
        "signed_bias_m": _round(_mean(errors)) if errors else None,
        "rmse_m": _round(_rmse(errors)) if errors else None,
        "repeatability_groups": repeat_groups,
        "max_repeatability_population_sd_m": (
            _round(max(repeat_values)) if repeat_values else None
        ),
    }
    thresholds = ruleset["thresholds"]
    gates = [
        _gate(
            "dimension_max_abs_error_m",
            metrics["max_abs_error_m"],
            thresholds["dimension_max_abs_error_m"],
            "m",
        ),
        _gate(
            "dimension_rmse_m",
            metrics["rmse_m"],
            thresholds["dimension_rmse_m"],
            "m",
        ),
        _gate(
            "repeatability_population_sd_m",
            metrics["max_repeatability_population_sd_m"],
            thresholds["repeatability_population_sd_m"],
            "m",
            sufficient=repeatability_complete,
        ),
    ]
    return metrics, gates


def _plane_residuals(
    observations: dict,
    ruleset: dict,
) -> tuple[dict, list[dict]]:
    planes = _array(observations, "plane_residual_observations")
    residuals: list[float] = []
    by_plane: list[dict] = []
    for index, plane in enumerate(planes):
        if not isinstance(plane, dict):
            raise BenchmarkError(
                f"plane_residual_observations[{index}] must be an object"
            )
        plane_id = plane.get("plane_id")
        values = plane.get("residuals_m")
        if not isinstance(plane_id, str) or not plane_id:
            raise BenchmarkError("plane_id is required")
        if not isinstance(values, list) or not values:
            raise BenchmarkError(f"residuals_m missing for plane {plane_id}")
        numeric = [
            _finite_number(
                value,
                f"plane_residual_observations[{index}].residuals_m",
            )
            for value in values
        ]
        residuals.extend(numeric)
        by_plane.append(
            {
                "plane_id": plane_id,
                "sample_count": len(numeric),
                "rmse_m": _round(_rmse(numeric)),
                "signed_bias_m": _round(_mean(numeric)),
            }
        )

    rmse = _round(_rmse(residuals)) if residuals else None
    metrics = {
        "sample_count": len(residuals),
        "rmse_m": rmse,
        "signed_bias_m": (
            _round(_mean(residuals)) if residuals else None
        ),
        "planes": by_plane,
    }
    gate = _gate(
        "plane_residual_rmse_m",
        rmse,
        ruleset["thresholds"]["plane_residual_rmse_m"],
        "m",
    )
    return metrics, [gate]


def _alignment(
    observations: dict,
    ruleset: dict,
) -> tuple[dict, list[dict]]:
    samples = _array(observations, "roomplan_mesh_alignment_observations")
    errors: list[float] = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise BenchmarkError(
                "roomplan_mesh_alignment_observations entries must be objects"
            )
        roomplan = _vec3(
            sample.get("roomplan_point_m"),
            f"roomplan_mesh_alignment_observations[{index}].roomplan_point_m",
        )
        mesh = _vec3(
            sample.get("armesh_point_m"),
            f"roomplan_mesh_alignment_observations[{index}].armesh_point_m",
        )
        errors.append(_distance(roomplan, mesh))

    rmse = _round(_rmse(errors)) if errors else None
    metrics = {
        "sample_count": len(errors),
        "rmse_m": rmse,
        "max_error_m": _round(max(errors)) if errors else None,
    }
    gate = _gate(
        "roomplan_mesh_alignment_rmse_m",
        rmse,
        ruleset["thresholds"]["roomplan_mesh_alignment_rmse_m"],
        "m",
    )
    return metrics, [gate]


def _loop_closure(
    observations: dict,
    ruleset: dict,
) -> tuple[dict, list[dict]]:
    samples = _array(observations, "loop_closure_observations")
    errors: list[float] = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise BenchmarkError(
                f"loop_closure_observations[{index}] must be an object"
            )
        start = _vec3(
            sample.get("start_position_m"),
            f"loop_closure_observations[{index}].start_position_m",
        )
        end = _vec3(
            sample.get("end_position_m"),
            f"loop_closure_observations[{index}].end_position_m",
        )
        errors.append(_distance(start, end))

    maximum = _round(max(errors)) if errors else None
    metrics = {
        "sample_count": len(errors),
        "max_error_m": maximum,
        "rmse_m": _round(_rmse(errors)) if errors else None,
    }
    gate = _gate(
        "loop_closure_error_m",
        maximum,
        ruleset["thresholds"]["loop_closure_error_m"],
        "m",
    )
    return metrics, [gate]


def _annotation_repeatability(
    observations: dict,
    ruleset: dict,
) -> tuple[dict, list[dict]]:
    samples = _array(observations, "annotation_position_observations")
    grouped: dict[str, list[tuple[float, float, float]]] = {}
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise BenchmarkError(
                f"annotation_position_observations[{index}] must be an object"
            )
        marker_id = sample.get("marker_id")
        if not isinstance(marker_id, str) or not marker_id:
            raise BenchmarkError("annotation marker_id is required")
        position = _vec3(
            sample.get("position_m"),
            f"annotation_position_observations[{index}].position_m",
        )
        grouped.setdefault(marker_id, []).append(position)

    minimum_repeats = int(ruleset["minimum_repeat_scans"])
    all_distances: list[float] = []
    group_metrics: list[dict] = []
    complete = bool(grouped)

    for marker_id in sorted(grouped):
        positions = grouped[marker_id]
        count = len(positions)
        center = tuple(
            _mean([position[axis] for position in positions])
            for axis in range(3)
        )
        distances = [
            _distance(position, center)
            for position in positions
        ]
        enough = count >= minimum_repeats
        complete = complete and enough
        if enough:
            all_distances.extend(distances)
        group_metrics.append(
            {
                "marker_id": marker_id,
                "sample_count": count,
                "centroid_m": [_round(value) for value in center],
                "repeatability_rmse_m": _round(_rmse(distances)),
                "minimum_required_samples": minimum_repeats,
                "sufficient": enough,
            }
        )

    rmse = _round(_rmse(all_distances)) if all_distances else None
    metrics = {
        "sample_count": len(samples),
        "repeatability_rmse_m": rmse,
        "markers": group_metrics,
    }
    gate = _gate(
        "annotation_position_repeatability_rmse_m",
        rmse,
        ruleset["thresholds"][
            "annotation_position_repeatability_rmse_m"
        ],
        "m",
        sufficient=complete,
    )
    return metrics, [gate]


def _orientation(
    observations: dict,
    ruleset: dict,
) -> tuple[dict, list[dict]]:
    samples = _array(observations, "speaker_orientation_observations")
    errors: list[float] = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise BenchmarkError(
                f"speaker_orientation_observations[{index}] must be an object"
            )
        reference = _vec3(
            sample.get("reference_front"),
            f"speaker_orientation_observations[{index}].reference_front",
        )
        observed = _vec3(
            sample.get("observed_front"),
            f"speaker_orientation_observations[{index}].observed_front",
        )
        reference_norm = math.sqrt(sum(value * value for value in reference))
        observed_norm = math.sqrt(sum(value * value for value in observed))
        if reference_norm == 0 or observed_norm == 0:
            raise BenchmarkError("orientation vectors must be non-zero")
        dot = sum(a * b for a, b in zip(reference, observed))
        cosine = max(
            -1.0,
            min(1.0, dot / (reference_norm * observed_norm)),
        )
        errors.append(math.degrees(math.acos(cosine)))

    maximum = _round(max(errors)) if errors else None
    metrics = {
        "sample_count": len(errors),
        "max_error_deg": maximum,
        "rmse_deg": _round(_rmse(errors)) if errors else None,
    }
    gate = _gate(
        "speaker_orientation_max_error_deg",
        maximum,
        ruleset["thresholds"]["speaker_orientation_max_error_deg"],
        "deg",
    )
    return metrics, [gate]


def _depth(
    observations: dict,
    ruleset: dict,
) -> tuple[dict, list[dict]]:
    samples = _array(observations, "depth_observations")
    normalized = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise BenchmarkError(
                f"depth_observations[{index}] must be an object"
            )
        reference = _nonnegative(
            sample.get("reference_distance_m"),
            f"depth_observations[{index}].reference_distance_m",
        )
        observed = _nonnegative(
            sample.get("observed_depth_m"),
            f"depth_observations[{index}].observed_depth_m",
        )
        confidence = sample.get("confidence")
        if confidence not in (0, 1, 2):
            raise BenchmarkError(
                f"depth_observations[{index}].confidence must be 0, 1, or 2"
            )
        normalized.append(
            {
                "reference": reference,
                "error": observed - reference,
                "confidence": confidence,
            }
        )

    bucket_metrics: list[dict] = []
    gates: list[dict] = []
    for bucket in ruleset["depth_buckets"]:
        lower = _nonnegative(bucket.get("min_m"), "depth_buckets.min_m")
        upper = _nonnegative(bucket.get("max_m"), "depth_buckets.max_m")
        if upper <= lower:
            raise BenchmarkError("depth bucket max_m must exceed min_m")
        max_rmse = _nonnegative(
            bucket.get("max_rmse_m"),
            "depth_buckets.max_rmse_m",
        )
        minimum = bucket.get("minimum_samples")
        if not isinstance(minimum, int) or minimum < 1:
            raise BenchmarkError(
                "depth bucket minimum_samples must be a positive integer"
            )

        selected = [
            item
            for item in normalized
            if lower <= item["reference"] < upper
        ]
        errors = [item["error"] for item in selected]
        rmse = _round(_rmse(errors)) if errors else None
        gate = _gate(
            f"depth_rmse_{lower:g}_{upper:g}m",
            rmse,
            max_rmse,
            "m",
            sufficient=len(errors) >= minimum,
        )
        gates.append(gate)
        bucket_metrics.append(
            {
                "min_m": _round(lower),
                "max_m": _round(upper),
                "sample_count": len(errors),
                "minimum_required_samples": minimum,
                "confidence_counts": {
                    str(level): sum(
                        1
                        for item in selected
                        if item["confidence"] == level
                    )
                    for level in (0, 1, 2)
                },
                "signed_bias_m": (
                    _round(_mean(errors)) if errors else None
                ),
                "mae_m": (
                    _round(_mean([abs(error) for error in errors]))
                    if errors
                    else None
                ),
                "rmse_m": rmse,
                "gate_status": gate["status"],
            }
        )

    return {
        "sample_count": len(normalized),
        "buckets": bucket_metrics,
    }, gates


def build_report(
    observations: dict,
    ruleset: dict,
    *,
    observations_sha256: str,
    ruleset_sha256: str,
) -> dict:
    observations = _require_document(
        observations,
        schema=OBSERVATION_SCHEMA,
        label="observations",
    )
    ruleset = _require_document(
        ruleset,
        schema=RULESET_SCHEMA,
        label="ruleset",
    )

    _validate_observation_metadata(observations)

    if not isinstance(observations.get("benchmark_id"), str):
        raise BenchmarkError("benchmark_id is required")
    if not isinstance(observations.get("protocol_version"), str):
        raise BenchmarkError("protocol_version is required")
    if not isinstance(ruleset.get("ruleset_version"), str):
        raise BenchmarkError("ruleset_version is required")
    if ruleset.get("threshold_notice") != (
        "provisional_engineering_gate_not_product_claim"
    ):
        raise BenchmarkError("ruleset threshold notice is missing")

    minimum_repeats = ruleset.get("minimum_repeat_scans")
    if not isinstance(minimum_repeats, int) or minimum_repeats < 2:
        raise BenchmarkError("minimum_repeat_scans must be >= 2")
    if not isinstance(ruleset.get("thresholds"), dict):
        raise BenchmarkError("ruleset thresholds are required")
    if not isinstance(ruleset.get("depth_buckets"), list):
        raise BenchmarkError("ruleset depth_buckets are required")

    dimensions, dimension_gates = _dimensions(observations, ruleset)
    planes, plane_gates = _plane_residuals(observations, ruleset)
    alignment, alignment_gates = _alignment(observations, ruleset)
    loop, loop_gates = _loop_closure(observations, ruleset)
    annotations, annotation_gates = _annotation_repeatability(
        observations,
        ruleset,
    )
    orientation, orientation_gates = _orientation(
        observations,
        ruleset,
    )
    depth, depth_gates = _depth(observations, ruleset)

    gates = (
        dimension_gates
        + plane_gates
        + alignment_gates
        + loop_gates
        + annotation_gates
        + orientation_gates
        + depth_gates
    )

    return {
        "schema": REPORT_SCHEMA,
        "schema_version": SCHEMA_VERSION,
        "benchmark_id": observations["benchmark_id"],
        "protocol_version": observations["protocol_version"],
        "ruleset_version": ruleset["ruleset_version"],
        "threshold_notice": ruleset["threshold_notice"],
        "source_observations_sha256": observations_sha256,
        "source_ruleset_sha256": ruleset_sha256,
        "engineering_gate_status": _overall_status(gates),
        "metrics": {
            "dimensions": dimensions,
            "plane_residuals": planes,
            "roomplan_mesh_alignment": alignment,
            "loop_closure": loop,
            "annotation_position_repeatability": annotations,
            "speaker_orientation": orientation,
            "depth": depth,
        },
        "gates": gates,
    }


def analyze_files(observations_path: Path, ruleset_path: Path) -> dict:
    observations_bytes = observations_path.read_bytes()
    ruleset_bytes = ruleset_path.read_bytes()
    try:
        observations = json.loads(observations_bytes.decode("utf-8"))
        ruleset = json.loads(ruleset_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BenchmarkError(f"invalid benchmark JSON: {exc}") from exc

    return build_report(
        observations,
        ruleset,
        observations_sha256=hashlib.sha256(
            observations_bytes
        ).hexdigest(),
        ruleset_sha256=hashlib.sha256(ruleset_bytes).hexdigest(),
    )


def canonical_report_bytes(report: dict) -> bytes:
    return json.dumps(
        report,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Analyze HTDT-Capture spatial accuracy benchmark data."
    )
    parser.add_argument("observations", type=Path)
    parser.add_argument("ruleset", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    try:
        report = analyze_files(args.observations, args.ruleset)
    except (BenchmarkError, OSError) as exc:
        print(f"benchmark analysis failed: {exc}", file=sys.stderr)
        return 2

    encoded = json.dumps(
        report,
        ensure_ascii=False,
        sort_keys=True,
        indent=2,
        allow_nan=False,
    ) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
