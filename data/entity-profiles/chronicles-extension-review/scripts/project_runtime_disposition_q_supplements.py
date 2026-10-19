#!/usr/bin/env python3
"""Format-only projection of two late batch08 disposition supplements."""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    ("qualified-runtime-disposition-batch08-persons_2-current-rebind.json", "rows", "runtimeDisposition", "qualified-runtime-disposition-batch08-persons_2-current-rebind"),
    ("qualified-runtime-disposition-batch08-persons_2-conaniah-current-delta.json", "items", "currentDisposition", "qualified-runtime-disposition-batch08-persons_2-conaniah-current-delta"),
]
SHA_RE = re.compile(r"^[0-9a-fA-F]{64}$")


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def project(source_name: str, rows_key: str, disposition_field: str, output_stem: str) -> dict:
    source_path = ROOT / "reviews" / source_name
    source_raw = source_path.read_bytes()
    source = json.loads(source_raw)
    rows = source.get(rows_key)
    if not isinstance(rows, list):
        rows = []
    errors_out = []
    counts = Counter()
    projected = []
    for i, row in enumerate(rows):
        errors = []
        if not isinstance(row, dict):
            row = {}
            errors.append("source-row-is-not-object")
        book = row.get("book")
        if book not in {"1CH", "2CH"}:
            errors.append("missing-or-invalid-explicit-book")
        entity_id = row.get("entityID")
        draft_path = row.get("draftPath")
        evidence_path = row.get("evidencePath")
        if not isinstance(entity_id, str) or not entity_id:
            errors.append("missing-entityID")
        if not isinstance(draft_path, str) or not draft_path:
            errors.append("missing-draftPath")
        if not isinstance(evidence_path, str) or not evidence_path:
            errors.append("missing-evidencePath")

        # Preserve the source report's expected hashes under standard names.
        if source_name.endswith("current-rebind.json"):
            draft_sha = row.get("currentDraftSHA256")
            profile_sha = row.get("currentProfileSHA256")
            evidence_sha = row.get("currentEvidenceSHA256")
            draft_sha_field, profile_sha_field, evidence_sha_field = "currentDraftSHA256", "currentProfileSHA256", "currentEvidenceSHA256"
        else:
            draft_sha = row.get("draftSHA256")
            profile_sha = row.get("profileSHA256")
            evidence_sha = row.get("evidenceSHA256")
            draft_sha_field, profile_sha_field, evidence_sha_field = "draftSHA256", "profileSHA256", "evidenceSHA256"
        for field, value in (("draft", draft_sha), ("evidence", evidence_sha)):
            if not isinstance(value, str) or not SHA_RE.fullmatch(value):
                errors.append(f"missing-or-invalid-expected-{field}-SHA256")
        if profile_sha is not None and (not isinstance(profile_sha, str) or not SHA_RE.fullmatch(profile_sha)):
            errors.append("invalid-expected-profile-SHA256")
        disposition = row.get(disposition_field)
        if not isinstance(disposition, str) or not disposition:
            errors.append(f"missing-or-ambiguous-disposition-field:{disposition_field}")
            projected_disposition = "hold"
        else:
            projected_disposition = disposition
        if errors:
            projected_disposition = "hold"
            errors_out.append({"sourceRowIndex": i, "entityID": entity_id, "errors": errors})
        counts[projected_disposition] += 1
        projected.append({
            "book": book,
            "entityID": entity_id,
            "draftPath": draft_path,
            "evidencePath": evidence_path,
            "currentDraftSHA256": draft_sha,
            "currentEvidenceSHA256": evidence_sha,
            "runtimeDisposition": projected_disposition,
            "projectionStatus": "hold-error" if errors else "format-projection-only",
            "sourceRowIndex": i,
            "sourceDispositionField": disposition_field,
            "sourceDispositionValue": row.get(disposition_field),
            "dispositionFormatAlias": f"{disposition_field}->runtimeDisposition" if disposition_field != "runtimeDisposition" else None,
            "expectedSourceDraftSHA256": draft_sha,
            "expectedSourceProfileSHA256": profile_sha,
            "expectedSourceEvidenceSHA256": evidence_sha,
            "sourceHashFieldNames": {"draft": draft_sha_field, "profile": profile_sha_field, "evidence": evidence_sha_field},
            "rowErrors": errors,
        })
    report = {
        "schemaVersion": 1,
        "projectionType": "format-only-runtime-disposition-q-supplement",
        "generatedAtUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "sourceReportPath": str(source_path.relative_to(ROOT)),
        "sourceReportSHA256": sha(source_raw),
        "sourceRowsKey": rows_key,
        "sourceDispositionField": disposition_field,
        "sourceRowCount": len(rows),
        "sourceCounts": source.get("counts"),
        "sourceReportDecisionCounts": source.get("decisionCounts"),
        "policy": {
            "formatOnly": True,
            "expectedSHAs": "Copied unchanged from the original independent row; not recomputed, refreshed, or rebound to current files.",
            "disposition": f"The explicit source field {disposition_field!r} is copied as the runtimeDisposition value; no semantic promotion or disposition inference is performed.",
            "errors": "Missing/ambiguous identity, paths, SHA, explicit book, or disposition yields runtimeDisposition=hold with projectionStatus=hold-error.",
        },
        "summary": {"rowCount": len(projected), "runtimeDispositionCounts": dict(counts), "errorRowCount": len(errors_out)},
        "rowErrors": errors_out,
        "rows": projected,
    }
    out = ROOT / "reviews" / ("projected-" + output_stem + ".json")
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"sourceReportPath": report["sourceReportPath"], "sourceReportSHA256": report["sourceReportSHA256"], "projectedReportPath": str(out.relative_to(ROOT)), "projectedReportSHA256": sha(out.read_bytes()), "rowCount": len(projected), "counts": dict(counts), "errorRowCount": len(errors_out)}


def main() -> None:
    projections = [project(*spec) for spec in SOURCES]
    index = {
        "schemaVersion": 1,
        "projectionType": "format-only-runtime-disposition-q-supplement-index",
        "generatedAtUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "scriptPath": str(Path(__file__).relative_to(ROOT)),
        "scriptSHA256": sha(Path(__file__).read_bytes()),
        "supplementCount": len(projections),
        "totalRows": sum(x["rowCount"] for x in projections),
        "totalErrorRows": sum(x["errorRowCount"] for x in projections),
        "projectedReports": projections,
        "semanticCaveat": "These supplements preserve existing disposition decisions and expected SHA bindings as format projections only; they are not new review or current-SHA rebind.",
    }
    out = ROOT / "reviews/projected-runtime-dispositions-q-supplement-index.json"
    out.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    index["indexPath"] = str(out.relative_to(ROOT))
    index["indexSHA256"] = sha(out.read_bytes())
    print(json.dumps(index, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
