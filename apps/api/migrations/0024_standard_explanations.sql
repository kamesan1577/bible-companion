-- Only fixed public-scripture explanations. No owner, question, or chat history columns.
CREATE TABLE standard_explanations (
 cache_key TEXT PRIMARY KEY,
 descriptor_json TEXT NOT NULL,
 result_json TEXT,
 lease_token TEXT NOT NULL,
 lease_until INTEGER NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('generating','complete','failed')),
 created_at INTEGER NOT NULL,
 updated_at INTEGER NOT NULL
);
