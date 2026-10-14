import { sha256, stableJSON } from '@bible/core';
import {
  SCRIPTURE_ASSET_SOURCE_VERSION,
  SCRIPTURE_ASSET_MANIFEST_SHA256,
  SCRIPTURE_ASSET_INDEX_SHA256,
} from './scripture-assets-pin';
/** Bump whenever reading projection, attribution, or offline-grant semantics change independently of prompt/source data. */
export const READING_RESPONSE_SCHEMA_VERSION = 2;
export const READING_RUNTIME_IDENTITY = Object.freeze({
  readingSchemaVersion: READING_RESPONSE_SCHEMA_VERSION,
  primaryRuntime: Object.freeze({
    sourceVersion: SCRIPTURE_ASSET_SOURCE_VERSION,
    manifestSha256: SCRIPTURE_ASSET_MANIFEST_SHA256,
    assetIndexSha256: SCRIPTURE_ASSET_INDEX_SHA256,
  }),
});
/** The durable epoch covers every mutable source/material/corpus publication path; ready corpus bytes are immutable. */
export function readingSourceVersion(
  policyVersion: number,
  runtimeIdentity: typeof READING_RUNTIME_IDENTITY = READING_RUNTIME_IDENTITY,
) {
  if (!Number.isSafeInteger(policyVersion) || policyVersion < 0)
    throw Error('Invalid source policy version');
  return sha256(stableJSON({ policyVersion, ...runtimeIdentity }));
}
