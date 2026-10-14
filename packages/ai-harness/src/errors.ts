export type HarnessErrorCode =
  | 'INVALID_INPUT'
  | 'UNKNOWN_MODEL'
  | 'MODEL_UNCONNECTED'
  | 'MODEL_DISABLED'
  | 'MODEL_TERMS_UNREVIEWED'
  | 'BUDGET_UNVERIFIED'
  | 'BUDGET_EXCEEDED'
  | 'INVALID_SETTINGS'
  | 'UNSUPPORTED_SETTING'
  | 'CONTEXT_TOO_LARGE'
  | 'INVALID_SOURCE'
  | 'ABORTED'
  | 'TIMEOUT'
  | 'PROVIDER_ERROR'
  | 'INVALID_RESPONSE'
  | 'TRUNCATED_RESPONSE';
/** Error messages contain codes only: provider errors can contain private prompts or secrets. */
export class HarnessError extends Error {
  readonly code: HarnessErrorCode;
  /** Binding cancellation does not prove upstream inference or billing stopped. */
  readonly usageUnknown: boolean;
  constructor(code: HarnessErrorCode, usageUnknown = false) {
    super(code);
    this.name = 'HarnessError';
    this.code = code;
    this.usageUnknown = usageUnknown;
  }
}
