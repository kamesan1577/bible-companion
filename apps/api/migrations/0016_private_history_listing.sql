CREATE INDEX conversations_owner_page ON conversations(user_id,created_at DESC,id DESC);
CREATE INDEX conversations_import_page ON conversations(user_id,import_id,created_at DESC,id DESC);
CREATE INDEX comparisons_owner_saved_page ON comparison_jobs(user_id,saved,created_at DESC,id DESC);
CREATE INDEX imports_owner_page ON imports(user_id,created_at DESC,id DESC);
