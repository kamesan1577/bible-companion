#!/usr/bin/env python3
"""Mechanically compare current Chronicles evidence-sidecar quotations to pinned WEB witnesses.

This checks citation coordinates, URLs, literal quotation payloads, and SHA fields.
It does not assess whether an entity interpretation is semantically correct.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
WITNESS_PATHS = {
    "1CH": ROOT / "inventory/targets/chronicles1-web-verses.json",
    "2CH": ROOT / "inventory/targets/chronicles2-web-verses.json",
}
EVIDENCE_GROUPS = [f"{kind}_{n}" for kind in ("persons", "places") for n in (1, 2, 3)]
ARRAY_FIELDS = ("primaryWitnesses", "primaryTextRead", "primaryTextChecks", "sourceChecks", "primaryChecks")
REF_RE = re.compile(r"\b(1CH|2CH)\s*(\d{1,2})\s*:\s*(\d{1,3})(?:\s*[-–—]\s*(\d{1,3}))?\b", re.I)
URL_RE = re.compile(r"/(1CH|2CH)(\d{2})\.htm(?:l)?(?:#V(\d+))?", re.I)


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def canon_text(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def parse_ref(value):
    if not isinstance(value, str):
        return None
    m = REF_RE.search(value)
    if not m:
        return None
    book, ch, start, end = m.groups()
    return {"book": book.upper(), "chapter": int(ch), "startVerse": int(start), "endVerse": int(end or start), "raw": value}


def parse_url(value):
    if not isinstance(value, str):
        return None
    m = URL_RE.search(value)
    if not m:
        return None
    book, ch, verse = m.groups()
    return {"book": book.upper(), "chapter": int(ch), "verse": int(verse) if verse else None}


def witness_map():
    out = {}
    inputs = {}
    for book, path in WITNESS_PATHS.items():
        data = json.loads(path.read_text(encoding="utf-8"))
        inputs[book] = {"path": str(path.relative_to(ROOT)), "fileSHA256": sha(path.read_text(encoding="utf-8")), "rows": len(data)}
        for row in data:
            c = row.get("canonical") or {}
            key = (str(c.get("book", row.get("sourceBook", book))).upper(), int(c.get("chapter", row.get("sourceChapter", 0))), int(c.get("verse", row.get("sourceVerse", 0))))
            out[key] = {**row, "actualTextSHA256": sha(str(row.get("text", "")))}
    return out, inputs


def is_sidecar(obj):
    if not isinstance(obj, dict):
        return False
    return bool(set(ARRAY_FIELDS).intersection(obj)) and any(k in obj for k in ("entityID", "draftPath", "profilePath", "book", "profileSHA256", "draftSHA256"))


def scan_sidecar(path, obj, witnesses):
    issues, warnings, citations, external, additional = [], [], [], [], []
    freshness = "unknown"
    draft_path = obj.get("draftPath") or obj.get("profilePath")
    expected_draft_sha = obj.get("draftSHA256")
    if isinstance(draft_path, str):
        dp = (ROOT / draft_path).resolve() if not Path(draft_path).is_absolute() else Path(draft_path)
        if dp.exists():
            actual = sha(dp.read_text(encoding="utf-8"))
            freshness = "current" if not expected_draft_sha or actual == expected_draft_sha else "stale-sidecar-draftSHA"
            if freshness != "current":
                issues.append({"kind": "sidecarDraftHashMismatch", "storedDraftSHA256": expected_draft_sha, "actualDraftSHA256": actual, "draftPath": str(dp.relative_to(ROOT)) if dp.is_relative_to(ROOT) else str(dp)})
        else:
            freshness = "draftPath-missing"
            issues.append({"kind": "draftPathMissing", "draftPath": draft_path})

    for field in ARRAY_FIELDS:
        rows = obj.get(field)
        if not isinstance(rows, list):
            continue
        for i, row in enumerate(rows):
            if not isinstance(row, dict):
                continue
            nested = row.get("text") if isinstance(row.get("text"), dict) else None
            ref = parse_ref(row.get("ref"))
            url_value = row.get("citationURL") or row.get("sourceURL") or row.get("url") or (nested or {}).get("citationURL")
            url = parse_url(url_value)
            host = urlparse(url_value).hostname if isinstance(url_value, str) else None
            if host and host.lower() != "ebible.org":
                external.append({"field": field, "index": i, "ref": row.get("ref"), "url": url_value, "classification": "non-pinned-web-source; excluded from fixed Chronicles WEB comparison"})
                continue
            book = (ref or {}).get("book") or (url or {}).get("book") or str(row.get("sourceBook") or obj.get("book") or "").upper()
            # Additional cross-book sources are documented separately, not compared to Chronicles witnesses.
            if book not in witnesses_by_book:
                external.append({"field": field, "index": i, "ref": row.get("ref"), "url": row.get("citationURL") or row.get("sourceURL") or row.get("url"), "classification": "outside-fixed-Chronicles-witness-scope"})
                continue
            ptr = f"{field}[{i}]"
            rec = {"field": field, "index": i, "ref": row.get("ref"), "citationURL": row.get("citationURL") or row.get("sourceURL") or row.get("url"), "sourceId": row.get("sourceId") or row.get("sourceID")}
            coords = None
            if ref:
                coords = {"book": ref["book"], "chapter": ref["chapter"], "startVerse": ref["startVerse"], "endVerse": ref["endVerse"]}
            elif url:
                coords = {"book": url["book"], "chapter": url["chapter"], "startVerse": url["verse"], "endVerse": url["verse"]}
            else:
                explicit = row.get("canonical") or {}
                if explicit:
                    coords = {"book": str(explicit.get("book", "")).upper(), "chapter": explicit.get("chapter"), "startVerse": explicit.get("verse"), "endVerse": explicit.get("verse")}
            raw_text = nested.get("text") if nested else row.get("text")
            if raw_text is None:
                raw_text = row.get("sourceText") or row.get("witnessText") or row.get("quotedText")
            if isinstance(raw_text, dict):
                raw_text = raw_text.get("text")
            payload_sha = row.get("sourceTextSHA256") or row.get("textSHA256") or row.get("sourceTextSha256") or (nested or {}).get("textSHA256")
            witness_version = row.get("witnessVersion") or row.get("sourceWitnessVersion") or (nested or {}).get("version")
            status = {**rec, "pointer": ptr, "coordinates": coords, "witnessVersion": witness_version, "payloadKind": "literal-quote" if isinstance(raw_text, str) else ("Japanese-paraphrase-only" if row.get("textualBasisJa") else "no-text-payload")}

            if not coords:
                explicit = (nested or {}).get("canonical") or row.get("canonical") or {}
                if explicit:
                    coords = {"book": str(explicit.get("book", (nested or {}).get("sourceBook", book))).upper(), "chapter": explicit.get("chapter", (nested or {}).get("sourceChapter")), "startVerse": explicit.get("verse", (nested or {}).get("sourceVerse")), "endVerse": explicit.get("verse", (nested or {}).get("sourceVerse"))}
                    status["coordinates"] = coords
                elif row.get("chapter") is not None and row.get("verse") is not None:
                    coords = {"book": book, "chapter": row["chapter"], "startVerse": row["verse"], "endVerse": row["verse"]}
                    status["coordinates"] = coords
            if not coords or not coords.get("chapter") or not coords.get("startVerse"):
                warnings.append({"kind": "unparseableCitationCoordinate", **status})
                citations.append(status)
                continue
            if coords["book"] not in witnesses_by_book:
                external.append({**status, "classification": "outside-fixed-Chronicles-witness-scope"})
                continue
            # A ref and a URL must point to the same canonical passage.
            if ref and url and (ref["book"], ref["chapter"], ref["startVerse"]) != (url["book"], url["chapter"], url["verse"]):
                issues.append({"kind": "refUrlCoordinateDisagreement", **status, "urlCoordinates": url})
            elif not url and (isinstance(raw_text, str) or payload_sha):
                warnings.append({"kind": "missingOrUnparseableFixedWebURL", **status})
            c_book, c_ch, first = coords["book"], int(coords["chapter"]), int(coords["startVerse"])
            end = int(coords.get("endVerse") or first)
            if end < first or end-first > 50:
                issues.append({"kind": "invalidVerseRange", **status})
                citations.append(status)
                continue
            target_rows = [witnesses.get((c_book, c_ch, v)) for v in range(first, end+1)]
            if any(t is None for t in target_rows):
                issues.append({"kind": "coordinateAbsentFromFixedWitness", **status})
                citations.append(status)
                continue
            expected_version = target_rows[0].get("version")
            if witness_version and expected_version and witness_version != expected_version:
                issues.append({"kind": "witnessVersionMismatch", **status, "expectedWitnessVersion": expected_version})
            if url and (url["book"] != c_book or url["chapter"] != c_ch or (url["verse"] is not None and url["verse"] != first)):
                issues.append({"kind": "urlDoesNotMatchFixedWitnessCoordinate", **status, "expectedURL": target_rows[0].get("citationURL"), "urlCoordinates": url})

            exact_text = "\n".join(str(t.get("text", "")) for t in target_rows)
            quote_status = "no-literal-quote"
            if isinstance(raw_text, str):
                if raw_text == exact_text:
                    quote_status = "exact-witness-text"
                elif len(target_rows) == 1 and canon_text(raw_text) == canon_text(exact_text):
                    quote_status = "whitespace-normalized-witness-text"
                elif len(target_rows) == 1 and raw_text and raw_text in exact_text:
                    quote_status = "exact-substring-of-witness"
                else:
                    quote_status = "quote-payload-differs-from-witness"
                    # A prose explanation may be stored under "text" in later schemas.
                    # Treat it as an explicit disagreement only when the row labels it as source text
                    # (hash, source id, URL, or a nested fixed witness object).
                    source_labelled = bool(payload_sha or row.get("sourceId") or row.get("sourceID") or url or nested)
                    if source_labelled:
                        issues.append({"kind": "literalQuoteMismatch", **status, "storedText": raw_text, "witnessText": exact_text})
                    else:
                        quote_status = "unverified-prose-under-text-field"
            if payload_sha:
                quote_sha = sha(raw_text) if isinstance(raw_text, str) else None
                witness_sha = sha(exact_text)
                if payload_sha == quote_sha:
                    status["hashStatus"] = "matches-payload"
                elif payload_sha == witness_sha:
                    status["hashStatus"] = "matches-fixed-witness-text"
                else:
                    status["hashStatus"] = "mismatch"
                    issues.append({"kind": "textSHA256Mismatch", **status, "storedTextSHA256": payload_sha, "payloadSHA256": quote_sha, "witnessTextSHA256": witness_sha, "quoteStatus": quote_status})
            else:
                status["hashStatus"] = "no-hash-field"
            # Check top-level explicit source coordinate fields when present.
            explicit_fields = {"sourceBook": row.get("sourceBook", (nested or {}).get("sourceBook")), "sourceChapter": row.get("sourceChapter", (nested or {}).get("sourceChapter")), "sourceVerse": row.get("sourceVerse", (nested or {}).get("sourceVerse"))}
            explicit_fields = {k: v for k, v in explicit_fields.items() if v is not None}
            if explicit_fields:
                expected = {"sourceBook": c_book, "sourceChapter": c_ch, "sourceVerse": first}
                if any(str(explicit_fields[k]).upper() != str(expected[k]).upper() for k in explicit_fields):
                    issues.append({"kind": "explicitSourceCoordinateMismatch", **status, "stored": explicit_fields, "expected": expected})
            status["quoteStatus"] = quote_status
            status["sourceTextSHA256"] = payload_sha
            status["computedQuoteSHA256"] = sha(raw_text) if isinstance(raw_text, str) else None
            status["witnessTextSHA256"] = sha(exact_text)
            citations.append(status)
    aps = obj.get("additionalPrimarySources")
    if isinstance(aps, list):
        for i, row in enumerate(aps):
            if isinstance(row, dict):
                additional.append({"index": i, "sourceId": row.get("sourceId") or row.get("sourceID"), "coordinate": row.get("coordinate") or row.get("ref"), "sourceBook": row.get("sourceBook"), "sourceURL": row.get("sourceURL") or row.get("citationURL"), "sourceEdition": row.get("sourceEdition"), "retrievedAtUTC": row.get("retrievedAtUTC"), "textSHA256": row.get("textSHA256"), "classification": "additional source; excluded from pinned fixed Chronicles witness comparison"})
    return {"sidecarPath": str(path.relative_to(ROOT)), "entityID": obj.get("entityID"), "book": obj.get("book"), "currentness": freshness, "citationCount": len(citations), "citations": citations, "externalBookCitations": external, "additionalPrimarySources": additional, "issues": issues, "warnings": warnings}


def main():
    global witnesses_by_book
    witnesses_by_book = {}
    witness_rows, witness_inputs = witness_map()
    for key, row in witness_rows.items():
        witnesses_by_book.setdefault(key[0], {})[key] = row
    records, skipped = [], Counter()
    for group in EVIDENCE_GROUPS:
        base = ROOT / "evidence" / group
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.json")):
            if "revisions" in path.relative_to(base).parts or "preservation" in path.relative_to(base).parts:
                skipped["historical-snapshot-directory"] += 1
                continue
            try:
                obj = json.loads(path.read_text(encoding="utf-8"))
            except Exception as exc:
                skipped["invalid-json"] += 1
                continue
            if is_sidecar(obj):
                records.append(scan_sidecar(path, obj, witness_rows))
            else:
                skipped["not-current-sidecar-shape"] += 1
    all_issues = [issue | {"sidecarPath": r["sidecarPath"], "entityID": r.get("entityID")} for r in records for issue in r["issues"]]
    all_warnings = [warning | {"sidecarPath": r["sidecarPath"], "entityID": r.get("entityID")} for r in records for warning in r["warnings"]]
    citation_count = sum(r["citationCount"] for r in records)
    quote_counts = Counter(c.get("quoteStatus") for r in records for c in r["citations"])
    currentness_counts = Counter(r["currentness"] for r in records)
    external_count = sum(len(r["externalBookCitations"]) for r in records)
    additional_rows = [{"sidecarPath": r["sidecarPath"], "entityID": r.get("entityID"), **a} for r in records for a in r["additionalPrimarySources"]]
    payload_kinds = Counter(c["payloadKind"] for r in records for c in r["citations"])
    hash_counts = Counter(c.get("hashStatus", "not-checked") for r in records for c in r["citations"])
    # Known historical negative control: an earlier Terah evidence payload attached
    # Genesis 11:26 wording to the Chronicles 1:27 coordinate. Keep it out of the
    # current-sidecar issue list, but verify that this checker catches the mismatch.
    terah_control_path = ROOT / "evidence/persons_2/root-author-repair-terah-fixed-quote.json"
    terah_control = json.loads(terah_control_path.read_text(encoding="utf-8"))
    terah_wrong = terah_control["wrongBeforeText"]
    terah_witness = witnesses_by_book["1CH"][("1CH", 1, 27)]
    negative_control = {
        "historicalOnly": True,
        "path": str(terah_control_path.relative_to(ROOT)),
        "ref": "1CH 1:27",
        "storedWrongText": terah_wrong.get("text"),
        "fixedWitnessText": terah_witness.get("text"),
        "mismatchDetected": terah_wrong.get("text") != terah_witness.get("text"),
        "currentTerahSidecarPath": "evidence/persons_2/1CH_person_terah_2841-sources.json",
        "currentTerahCitationResult": next((c for r in records if r["sidecarPath"] == "evidence/persons_2/1CH_person_terah_2841-sources.json" for c in r["citations"] if c.get("ref") == "1CH 1:27"), None)
    }
    report = {
        "schemaVersion": 1,
        "generatedAtUTC": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "scope": "Chronicles evidence sidecars under evidence/persons_1..3 and evidence/places_1..3; current quotation-bearing sidecar top-level fields only",
        "fixedWitnessInputs": witness_inputs,
        "method": {
            "citationArrays": list(ARRAY_FIELDS),
            "checks": ["ref/URL/book/chapter/verse consistency", "fixed witness coordinate exists", "literal quotation equals, whitespace-normalizes to, or is a substring of fixed WEB verse text", "provided quotation SHA matches payload or fixed witness text", "explicit sourceBook/sourceChapter/sourceVerse fields"],
            "historicalRepairSnapshots": "not recursively inspected; only top-level recognized sidecars are scanned, so embedded before/after history is excluded",
            "otherPrimarySources": "non-WEB URLs and additionalPrimarySources are listed separately outside pinned fixed witness comparison; live WEB GEN citations are not compared to Chronicles witnesses",
            "supportedSchemas": ["ref + text/sourceText literal", "ref + nested fixed witness object in text", "book/chapter/verse fields", "canonical coordinate object", "fixed WEB URL anchors", "textSHA256/sourceTextSHA256", "witnessVersion"],
            "semanticCaveat": "A mechanical match confirms only payload/source alignment, not whether the quoted text supports the profile or entity decision."
        },
        "negativeControl": negative_control,
        "summary": {
            "recognizedSidecars": len(records), "citationPayloads": citation_count, "externalBookCitations": external_count, "additionalPrimarySources": len(additional_rows), "payloadKinds": dict(payload_kinds),
            "currentness": dict(currentness_counts), "quoteStatus": dict(quote_counts), "hashStatus": dict(hash_counts), "issueCount": len(all_issues), "issueKinds": dict(Counter(i["kind"] for i in all_issues)), "warningCount": len(all_warnings), "warningKinds": dict(Counter(i["kind"] for i in all_warnings)), "skippedJsonFiles": dict(skipped)
        },
        "issues": all_issues,
        "warnings": all_warnings,
        "additionalPrimarySources": additional_rows,
        "sidecars": records
    }
    out = ROOT / "reviews/audit-fixed-web-citation-sidecars.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(out.relative_to(ROOT)), "sidecars": len(records), "citations": citation_count, "issues": len(all_issues), "issueKinds": dict(Counter(i["kind"] for i in all_issues)), "warnings": len(all_warnings), "warningKinds": dict(Counter(i["kind"] for i in all_warnings)), "quoteStatus": dict(quote_counts), "hashStatus": dict(hash_counts), "payloadKinds": dict(payload_kinds), "currentness": dict(currentness_counts), "externalBookCitations": external_count, "additionalPrimarySources": len(additional_rows)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
