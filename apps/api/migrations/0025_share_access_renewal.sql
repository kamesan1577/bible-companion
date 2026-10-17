-- Stable share scope survives short-lived token renewal. Refresh is bounded by parent login.
ALTER TABLE share_ai_access ADD COLUMN refresh_hash TEXT;
ALTER TABLE share_ai_access ADD COLUMN refresh_expires_at INTEGER;
CREATE UNIQUE INDEX share_ai_refresh_hash ON share_ai_access(refresh_hash);
CREATE TABLE share_ai_tokens (
 token_hash TEXT PRIMARY KEY,
 access_hash TEXT NOT NULL REFERENCES share_ai_access(token_hash) ON DELETE CASCADE,
 expires_at INTEGER NOT NULL
);
CREATE INDEX share_ai_tokens_scope ON share_ai_tokens(access_hash);
