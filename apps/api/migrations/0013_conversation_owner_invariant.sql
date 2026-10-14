-- Keep the existing FK cascade without rebuilding a parent table that has private children.
-- These triggers additionally enforce the composite parent/owner invariant for direct SQL writers.
CREATE TRIGGER conversation_import_owner_insert BEFORE INSERT ON conversations
WHEN NOT EXISTS(SELECT 1 FROM imports WHERE id=NEW.import_id AND user_id=NEW.user_id)
BEGIN SELECT RAISE(ABORT,'conversation_import_owner_mismatch'); END;
CREATE TRIGGER conversation_import_owner_update BEFORE UPDATE OF import_id,user_id ON conversations
WHEN NOT EXISTS(SELECT 1 FROM imports WHERE id=NEW.import_id AND user_id=NEW.user_id)
BEGIN SELECT RAISE(ABORT,'conversation_import_owner_mismatch'); END;
