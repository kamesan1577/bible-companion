/** Only pinned, independently checked official corpus identities belong here.
 * No registration API and no client-supplied allowlist. Import/retrieval must additionally
 * enforce immutable server rows, approved ready revision and verse-to-manifest integrity. */
export interface PrimaryTextManifestIdentity {
  corpusId: string;
  edition: string;
  manifestSha256: string;
  sourceVersion: string;
  language: 'en';
  referenceSystem: 'web-protestant';
}
export const TRUSTED_PRIMARY_TEXT_MANIFESTS: readonly Readonly<PrimaryTextManifestIdentity>[] =
  Object.freeze([
    Object.freeze({
      corpusId: 'webp',
      edition: 'engwebp',
      manifestSha256: 'd2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e',
      sourceVersion: 'webp-usfx-2026-10-13-35a6adf626e5',
      language: 'en',
      referenceSystem: 'web-protestant',
    }),
  ]);

/** Manifest identity only. Callers must still enforce approved revision, row immutability and rights. */
export function isTrustedPrimaryCorpus(identity: {
  corpusId: string;
  edition: string;
  manifestSha256: string;
  sourceVersion?: string;
}): boolean {
  return TRUSTED_PRIMARY_TEXT_MANIFESTS.some(
    (m) =>
      m.corpusId === identity.corpusId &&
      m.edition === identity.edition &&
      m.manifestSha256 === identity.manifestSha256 &&
      (identity.sourceVersion === undefined || m.sourceVersion === identity.sourceVersion),
  );
}
