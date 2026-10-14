-- Retained until account deletion: a cancelled UUID must never become a fresh inference later.
CREATE TABLE request_cancellations (
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 id TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('question','comparison')),
 created_at INTEGER NOT NULL,
 PRIMARY KEY(user_id,id,kind)
);
