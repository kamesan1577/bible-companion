# Security boundaries

Do not post vulnerabilities or private account material to public issues. This private repository has no public service endpoint. Contact the repository owner privately with a reproduction and affected commit; never attach live session tokens, passkey assertions, invitations, API credentials, prayer text or account exports.

## Application controls

- WebAuthn verification uses the established SimpleWebAuthn server package, exact configured RP ID/origin and required user verification.
- Hashed single-use browser challenges, native PKCE exchange codes and bearer sessions; no private passkey key material is stored.
- Invite-created roles; no first-registrant or client-asserted owner privilege.
- Authenticated owner predicates on every private data path; FK cascades protect deletion.
- Strict input schemas, bounded streaming request reads, burst limits and atomic per-user/global budgets.
- Provider IDs/settings are allowlisted; paid model approvals are empty. No arbitrary URL provider path exists.
- Live inference requires an existing approved model connection, explicit AI transmission consent and current server-owned budget authority. Strict calibrated proof is the default; the optional Free-account mode requires an explicit, expiring, account-bound hard-stop receipt. No real proof or account receipt is seeded.
- Reviewed sources, rights state, versions and spoiler boundary are checked before prompt construction or display. User text cannot create trusted evidence records.

The experimental grounded-generation harness path is not a proof of semantic correctness or spoiler-free freeform prose. The default selection renderer only displays reviewed claim text. Do not turn warnings into acceptance claims.

## Operational boundaries

The Worker does not log request bodies or tokens, and observability is disabled in the scaffold. Review platform-level logging, retention and provider terms before deployment. The public source fixture license is documented separately. No production secrets belong in source control, CI artifacts, app bundles or screenshots.

CI is manual-only until GitHub access and usage quota are verified, with read-only repository permission and no deployment steps. Dependency versions are lockfile-pinned. Use `npm ci`, `npm audit` and `npm run validate` when updating them.
