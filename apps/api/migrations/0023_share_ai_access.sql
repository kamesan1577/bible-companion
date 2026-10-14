-- Share-only capabilities never become general API sessions.
CREATE TABLE share_ai_access (
 token_hash TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 source_session_hash TEXT NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
 data_epoch INTEGER NOT NULL,
 expires_at INTEGER NOT NULL,
 created_at INTEGER NOT NULL
);
CREATE INDEX share_ai_access_owner ON share_ai_access(user_id,expires_at);
CREATE TABLE share_ai_readings (
 id TEXT PRIMARY KEY,
 access_hash TEXT NOT NULL REFERENCES share_ai_access(token_hash) ON DELETE CASCADE,
 request_id TEXT NOT NULL,
 request_hash TEXT NOT NULL,
 import_id TEXT NOT NULL REFERENCES imports(id) ON DELETE CASCADE,
 UNIQUE(access_hash,request_id)
);
CREATE TABLE share_ai_conversations (
 conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
 reading_id TEXT NOT NULL REFERENCES share_ai_readings(id) ON DELETE CASCADE
);
