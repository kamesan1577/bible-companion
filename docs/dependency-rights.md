# Dependency and source rights record

Checked on2026-10-13 against installed package metadata and the lockfile. This is an inventory, not legal advice or acceptance of a provider's terms.

- Application code is covered by the repository `LICENSE`.
- Hono, Zod, SimpleWebAuthn and the build/test tooling retain their respective package licenses. `package-lock.json` records the exact installed versions, registry integrity hashes and package license identifiers; installed package license texts remain authoritative.
- `saxes`6.0.0 (ISC) and its `xmlchars` dependency are used only by the offline XML preparation CLI. The Worker entrypoint does not import the XML parser or full corpus. The strict parser rejects DTDs/entities and unknown selected-book markup rather than resolving external resources.
- World English Bible primary text is public domain according to [eBible's rights statement](https://ebible.org/engwebp/copyright.htm). The World English Bible name is a trademark; the prepared corpus preserves primary wording and records extraction/whitespace policy. Unsupported references, empty source markers, notes and unversified headings are not silently rewritten into numbered scripture.
- The pinned USFX download contains additional books despite the Protestant download label. The preparation manifest explicitly selects the canonical66 and reports excluded blocks. This selection is not a claim that the source archive itself has only66 books.
- Original Japanese curated commentary is separate from literal primary text. Primary byte/hash verification does not mark scripture as editorially reviewed Japanese explanation. JCB text redistribution and reference alignment are not granted by this record.
- Model-page links and terms-review metadata do not constitute accepting model licenses. Production model review flags remain empty.

The production dependency audit after adding `saxes` reported zero vulnerabilities. Audit status is time-bound and does not replace pinned dependency review or future security updates. No corpus download is needed by ordinary unit tests; real corpus preparation/import is an explicit optional operator command.
