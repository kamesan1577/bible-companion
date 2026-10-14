/** Verified deterministic artifact pin from the offline chapter builder.
 * This is public provenance, never a credential or a runtime-configurable trust override. */
export const SCRIPTURE_ASSET_INDEX_SHA256 =
  'da5c4a2528021be29be09d532bcaab493c05020ff6b4ad2b58a5f1115b8c5f2c';
export const SCRIPTURE_ASSET_SOURCE_VERSION = 'webp-usfx-2026-10-13-35a6adf626e5';
export const SCRIPTURE_ASSET_MANIFEST_SHA256 =
  'd2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e';
/** Exact absent set, verified against every canonical coordinate in the pinned source. */
export const SCRIPTURE_ABSENT_CANONICAL = Object.freeze([
  'LUK:17:36',
  'ACT:8:37',
  'ACT:15:34',
  'ACT:24:7',
  'ROM:16:25',
  'ROM:16:26',
  'ROM:16:27',
]);
