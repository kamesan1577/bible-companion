#!/usr/bin/env python3
"""Format-only projections of seven pinned Chronicles runtime disposition reports.

The projection preserves source-report hashes and row SHA expectations. It does
not read or bind current drafts, change any decision, or touch runtime inputs.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "runtime-disposition-primary-qualified-batch07-persons_2.json",
    "runtime-disposition-batch07-persons_3-qualified-primary-only.json",
    "runtime-disposition-primary-qualified-batch08-persons_1.json",
    "qualified-runtime-disposition-batch08-persons_2.json",
    "runtime-disposition-batch08-persons_3-qualified.json",
    "runtime-disposition-batch09-persons_1-qualified-pending.json",
    "runtime-disposition-batch09-persons_3-qualified.json",
]
BOOKS = {"1CH", "2CH"}
SHA_RE = re.compile(r"^[0-9a-fA-F]{64}$")


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def inferred_book_from_draft_path(draft_path: object) -> str | None:
    if not isinstance(draft_path, str):
        return None
    basename = Path(draft_path).name
    for book in ("1CH", "2CH"):
        if basename.startswith(book + "_"):
            return book
    return None


def load_book_delta() -> tuple[dict, str, str]:
    path = ROOT / "reviews/reclosure-batch08-book-metadata-delta.json"
    raw = path.read_bytes()
    obj = json.loads(raw)
    return obj, str(path.relative_to(ROOT)), sha(raw)


def resolve_book(row: dict, source_name: str, delta_rows: list[dict], delta_path: str, delta_sha: str) -> tuple[str | None, dict | None, list[str]]:
    errors: list[str] = []
    raw_book = row.get("book")
    if raw_book in BOOKS:
        return raw_book, {"method": "source-row-book", "sourceValue": raw_book}, errors
    if raw_book in (None, ""):
        inferred = inferred_book_from_draft_path(row.get("draftPath"))
        if inferred:
            return inferred, {"method": "explicit-draft-filename-prefix", "sourceValue": None, "draftPath": row.get("draftPath")}, errors
        errors.append("book-missing-and-draft-filename-has-no-explicit-1CH-or-2CH-prefix")
        return None, None, errors
    if source_name == "runtime-disposition-batch08-persons_3-qualified.json" and raw_book == "person":
        eid = row.get("entityID")
        matches = [d for d in delta_rows
                   if d.get("entityID") == eid
                   and d.get("draftPath") == row.get("draftPath")
                   and d.get("evidencePath") == row.get("evidencePath")
                   and d.get("currentDraftSHA256") == row.get("currentDraftSHA256")
                   and d.get("currentEvidenceSHA256") == row.get("currentEvidenceSHA256")
                   and d.get("correctedBook") in BOOKS]
        if len(matches) == 1:
            match = matches[0]
            return match["correctedBook"], {
                "method": "exact-identity-and-draft-evidence-sha-match-to-authorized-book-metadata-delta",
                "sourceValue": raw_book,
                "deltaPath": delta_path,
                "deltaSHA256": delta_sha,
                "deltaRowEntityID": match.get("entityID"),
                "deltaOriginalReportBook": match.get("originalReportBook"),
                "deltaCorrectedBook": match.get("correctedBook"),
                "matchedDraftPath": match.get("draftPath"),
                "matchedEvidencePath": match.get("evidencePath"),
                "matchedCurrentDraftSHA256": match.get("currentDraftSHA256"),
                "matchedCurrentEvidenceSHA256": match.get("currentEvidenceSHA256"),
            }, errors
        errors.append(f"p3-batch08-book-person-delta-match-count-{len(matches)}-expected-1")
        return None, None, errors
    errors.append(f"unapproved-or-ambiguous-book-value:{raw_book}")
    return None, None, errors


def disposition_value(row: dict, source_name: str) -> tuple[object, str | None, str | None]:
    """Return raw disposition, source field, and format-only normalization note."""
    if source_name == "runtime-disposition-batch07-persons_3-qualified-primary-only.json":
        field = "decision"  # This report's declared schema uses decision as its disposition field.
    elif source_name in {
        "runtime-disposition-primary-qualified-batch07-persons_2.json",
        "runtime-disposition-primary-qualified-batch08-persons_1.json",
    }:
        field = "primaryOnlyDisposition"
    else:
        field = "runtimeDisposition"
    value = row.get(field)
    if field == "primaryOnlyDisposition" and value == "primary-only-supported":
        return "primary-only-display-supported", field, "format-alias:primary-only-supported"
    return value, field, None


def project_one(source_name: str, delta_rows: list[dict], delta_path: str, delta_sha: str) -> dict:
    source_path = ROOT / "reviews" / source_name
    source_raw = source_path.read_bytes()
    source = json.loads(source_raw)
    rows_key = "rows" if isinstance(source.get("rows"), list) else "entries" if isinstance(source.get("entries"), list) else None
    source_rows = source.get(rows_key) if rows_key else None
    if not isinstance(source_rows, list):
        source_rows = []

    output_rows = []
    row_errors = []
    disposition_counts = Counter()
    for index, row in enumerate(source_rows):
        errors: list[str] = []
        if not isinstance(row, dict):
            row = {}
            errors.append("source-row-is-not-object")
        book, book_resolution, book_errors = resolve_book(row, source_name, delta_rows, delta_path, delta_sha)
        errors.extend(book_errors)
        entity_id = row.get("entityID")
        draft_path = row.get("draftPath")
        evidence_path = row.get("evidencePath")
        draft_sha = row.get("currentDraftSHA256")
        evidence_sha = row.get("currentEvidenceSHA256")
        if not isinstance(entity_id, str) or not entity_id:
            errors.append("missing-entityID")
        if not isinstance(draft_path, str) or not draft_path:
            errors.append("missing-draftPath")
        if not isinstance(evidence_path, str) or not evidence_path:
            errors.append("missing-evidencePath")
        for field, val in (("currentDraftSHA256", draft_sha), ("currentEvidenceSHA256", evidence_sha)):
            if not isinstance(val, str) or not SHA_RE.fullmatch(val):
                errors.append(f"missing-or-invalid-expected-{field}")
        disp, disp_field, normalization = disposition_value(row, source_name)
        if not isinstance(disp, str) or not disp:
            errors.append(f"missing-or-ambiguous-disposition-field:{disp_field}")
            projected_disp = "hold"
        else:
            projected_disp = disp
        if errors:
            projected_disp = "hold"
            row_errors.append({"sourceRowIndex": index, "entityID": entity_id, "errors": errors})
        disposition_counts[projected_disp] += 1
        output_rows.append({
            "book": book,
            "entityID": entity_id,
            "draftPath": draft_path,
            "evidencePath": evidence_path,
            "currentDraftSHA256": draft_sha,
            "currentEvidenceSHA256": evidence_sha,
            "runtimeDisposition": projected_disp,
            "projectionStatus": "hold-error" if errors else "format-projection-only",
            "sourceReportRowIndex": index,
            "sourceDispositionField": disp_field,
            "sourceDispositionValue": row.get(disp_field),
            "dispositionFormatAlias": normalization,
            "expectedCurrentDraftSHA256": draft_sha,
            "expectedCurrentEvidenceSHA256": evidence_sha,
            "bookResolution": book_resolution,
            "rowErrors": errors,
        })

    report = {
        "schemaVersion": 1,
        "projectionType": "format-only-runtime-disposition-q-projection",
        "generatedAtUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "sourceReportPath": str(source_path.relative_to(ROOT)),
        "sourceReportSHA256": sha(source_raw),
        "sourceReportRowsKey": rows_key,
        "sourceReportRowCount": len(source_rows),
        "sourceReportDecisionCounts": source.get("decisionCounts") or source.get("counts") or source.get("runtimeDispositionCounts"),
        "bookMetadataDeltaPath": delta_path if source_name == "runtime-disposition-batch08-persons_3-qualified.json" else None,
        "bookMetadataDeltaSHA256": delta_sha if source_name == "runtime-disposition-batch08-persons_3-qualified.json" else None,
        "policy": {
            "formatOnly": True,
            "currentDraftSHA256AndCurrentEvidenceSHA256": "copied unchanged from source row as expected SHAs; not recomputed or rebound to current files",
            "bookInference": "only missing book values may be inferred from literal 1CH_/2CH_ draft filename prefix; p3 batch08 book=person requires exact entityID, draftPath, evidencePath, draft SHA, and evidence SHA match to the authorized book metadata delta",
            "primaryOnlyAlias": "primary-only-supported is normalized only as a format alias to primary-only-display-supported",
            "p3Batch07DispositionSchema": "decision is mapped to runtimeDisposition only for the named p3 batch07 source report; no other generic verdict field is inferred",
            "semanticPromotion": "none; row disposition values are copied, except the explicitly declared format alias",
            "errors": "missing/invalid SHA, missing path/ID, ambiguous book, or missing disposition marks the row runtimeDisposition=hold with projectionStatus=hold-error",
        },
        "summary": {"rowCount": len(output_rows), "runtimeDispositionCounts": dict(disposition_counts), "errorRowCount": len(row_errors)},
        "rowErrors": row_errors,
        "rows": output_rows,
    }
    output_path = ROOT / "reviews" / ("projected-" + source_name)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report["projectedReportPath"] = str(output_path.relative_to(ROOT))
    report["projectedReportSHA256"] = sha(output_path.read_bytes())
    return report


def main() -> None:
    delta, delta_path, delta_sha = load_book_delta()
    delta_rows = delta.get("rows", [])
    results = [project_one(name, delta_rows, delta_path, delta_sha) for name in SOURCES]
    index = {
        "schemaVersion": 1,
        "projectionType": "format-only-runtime-disposition-q-projection-index",
        "generatedAtUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "scriptPath": str(Path(__file__).relative_to(ROOT)),
        "scriptSHA256": sha(Path(__file__).read_bytes()),
        "bookMetadataDeltaPath": delta_path,
        "bookMetadataDeltaSHA256": delta_sha,
        "sourceReportCount": len(results),
        "totalRows": sum(r["summary"]["rowCount"] for r in results),
        "totalErrorRows": sum(r["summary"]["errorRowCount"] for r in results),
        "projectedReports": [{k: r[k] for k in ("sourceReportPath", "sourceReportSHA256", "projectedReportPath", "projectedReportSHA256", "summary")} for r in results],
        "semanticCaveat": "These are format-only projections of prior independent disposition reports, not new review, current-SHA rebind, or semantic approval.",
    }
    out = ROOT / "reviews/projected-runtime-dispositions-q-index.json"
    out.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    index["indexPath"] = str(out.relative_to(ROOT))
    index["indexSHA256"] = sha(out.read_bytes())
    print(json.dumps(index, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
