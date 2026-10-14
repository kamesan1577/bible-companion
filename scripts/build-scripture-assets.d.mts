/** Type boundary for the offline Node builder consumed by integration tests. */
export interface ScriptureAssetInputs {
  manifest: Buffer;
  verses: Buffer;
  unversified: Buffer;
}
export interface ScriptureAssetPlan {
  readonly files: readonly { readonly path: string; readonly contents: string }[];
  readonly bookIndexPins: Readonly<Record<string, { sha256: string; bytes: number }>>;
  readonly summary: {
    corpusId: string;
    sourceVersion: string;
    manifestSha256: string;
    chapterCount: number;
    verseCount: number;
    indexPath: string;
    indexSha256: string;
    indexBytes: number;
    totalChapterBytes: number;
    maxChapterBytes: number;
    totalBytes: number;
    networkRequests: number;
  };
}
export function readBundledScriptureAssetInputs(): ScriptureAssetInputs;
export function planScriptureAssets(inputs: ScriptureAssetInputs): ScriptureAssetPlan;
