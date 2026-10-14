-- Operator evidence only. No account verification or provider access is implied by this schema.
CREATE TABLE ai_free_account_receipts (
  id TEXT PRIMARY KEY CHECK(length(id) BETWEEN 1 AND 100),
  account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'),
  receipt_json TEXT NOT NULL CHECK(json_valid(receipt_json) AND length(CAST(receipt_json AS BLOB))<=16384),
  created_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE TRIGGER ai_free_receipt_immutable BEFORE UPDATE ON ai_free_account_receipts
WHEN NEW.id<>OLD.id OR NEW.account_id<>OLD.account_id OR NEW.receipt_json<>OLD.receipt_json OR NEW.created_at<>OLD.created_at OR (OLD.revoked_at IS NOT NULL AND (NEW.revoked_at IS NULL OR NEW.revoked_at<>OLD.revoked_at))
BEGIN SELECT RAISE(ABORT,'free_account_receipt_immutable'); END;
CREATE TRIGGER ai_free_receipt_no_delete BEFORE DELETE ON ai_free_account_receipts
BEGIN SELECT RAISE(ABORT,'free_account_receipt_revoke_instead'); END;
