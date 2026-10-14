export interface Env {
  DB: D1Database;
  /** Explicit account IDs; unset disables developer access, including owners. */
  DEBUG_ACCOUNT_IDS?: string;
  SCRIPTURE_ASSETS?: { fetch(request: Request): Promise<Response> };
  ENVIRONMENT: 'development' | 'production';
  RP_ID: string;
  AUTH_ORIGIN: string;
  NATIVE_CALLBACK: string;
  AI_ENABLED: string;
  ALLOWED_ANSWER_MODES?: string;
  DEFAULT_ANSWER_MODE?: string;
  CONNECTED_MODELS: string;
  TERMS_REVIEWED_MODELS: string;
  TERMS_REVIEW_VERSION: string;
  DEFAULT_MODEL_ID: string;
  DAILY_APP_BUDGET: string;
  DAILY_USER_BUDGET: string;
  AI_RESERVATION_UNITS: string;
  AI_BUDGET_MODE?: string;
  WORKERS_AI_ACCOUNT_ID?: string;
  AI_FREE_RECEIPT_ID?: string;
  AI_FREE_RECEIPT_MODE?: string;
  AI_FREE_RECEIPT_SLOT?: string;
  AI?: {
    run(
      model: string,
      input: Record<string, unknown>,
      options?: Record<string, unknown>,
    ): Promise<unknown>;
  };
}
export type User = { id: string; display_name: string; role: 'owner' | 'member' };
export type AppEnv = {
  Bindings: Env;
  Variables: { user: User; tokenHash: string; requestId: string; dataEpoch: number };
};
