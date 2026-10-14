-- Erase cached private generation payloads when their parent conversation/import is deleted.
CREATE TABLE generation_requests_new (
 id TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 conversation_id TEXT NOT NULL,
 request_hash TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('reserved','running','complete','failed','cancelled')),
 result_json TEXT,
 created_at INTEGER NOT NULL,
 updated_at INTEGER NOT NULL,
 UNIQUE(id,user_id),
 FOREIGN KEY(conversation_id,user_id) REFERENCES conversations(id,user_id) ON DELETE CASCADE
);
INSERT INTO generation_requests_new SELECT g.* FROM generation_requests g JOIN conversations c ON c.id=g.conversation_id AND c.user_id=g.user_id;
DROP TABLE generation_requests;
ALTER TABLE generation_requests_new RENAME TO generation_requests;
