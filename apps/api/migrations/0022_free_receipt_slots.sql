-- Optional stable deployment pointers. Evidence stays immutable in 0020.
CREATE TABLE ai_free_receipt_slots (
  slot_id TEXT NOT NULL CHECK(length(slot_id) BETWEEN 1 AND 100 AND slot_id NOT GLOB '*[^A-Za-z0-9_-]*'),
  account_id TEXT NOT NULL CHECK(length(account_id)=32 AND account_id NOT GLOB '*[^0-9a-f]*'),
  receipt_id TEXT NOT NULL REFERENCES ai_free_account_receipts(id),
  generation INTEGER NOT NULL CHECK(typeof(generation)='integer' AND generation BETWEEN 1 AND 9007199254740991),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(slot_id,account_id)
);
CREATE TABLE ai_free_receipt_slot_history (
  slot_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  receipt_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  PRIMARY KEY(slot_id,account_id,receipt_id),
  UNIQUE(slot_id,account_id,generation)
);
CREATE TRIGGER ai_free_slot_insert_guard BEFORE INSERT ON ai_free_receipt_slots
WHEN NEW.generation<>1
OR EXISTS(SELECT 1 FROM ai_free_receipt_slots s WHERE s.slot_id=NEW.slot_id AND s.account_id=NEW.account_id)
OR EXISTS(SELECT 1 FROM ai_free_receipt_slot_history h WHERE h.slot_id=NEW.slot_id AND h.account_id=NEW.account_id)
OR NOT EXISTS (
  SELECT 1 FROM ai_free_account_receipts r WHERE r.id=NEW.receipt_id AND r.account_id=NEW.account_id AND r.revoked_at IS NULL
  AND json_extract(r.receipt_json,'$.accountId')=NEW.account_id
  AND julianday(json_extract(r.receipt_json,'$.verifiedAt'))<=julianday('now')
  AND julianday(json_extract(r.receipt_json,'$.expiresAt'))>julianday('now')
  AND julianday(json_extract(r.receipt_json,'$.expiresAt'))>julianday(json_extract(r.receipt_json,'$.verifiedAt'))
  AND julianday(json_extract(r.receipt_json,'$.expiresAt'))-julianday(json_extract(r.receipt_json,'$.verifiedAt'))<=1
)
BEGIN SELECT RAISE(ABORT,'free_receipt_slot_invalid'); END;
CREATE TRIGGER ai_free_slot_update_guard BEFORE UPDATE ON ai_free_receipt_slots
WHEN NEW.slot_id<>OLD.slot_id OR NEW.account_id<>OLD.account_id OR NEW.generation<>OLD.generation+1 OR NEW.receipt_id=OLD.receipt_id OR NEW.updated_at<OLD.updated_at
OR EXISTS(SELECT 1 FROM ai_free_receipt_slot_history h WHERE h.slot_id=NEW.slot_id AND h.account_id=NEW.account_id AND h.receipt_id=NEW.receipt_id)
OR NOT EXISTS (
  SELECT 1 FROM ai_free_account_receipts r WHERE r.id=NEW.receipt_id AND r.account_id=NEW.account_id AND r.revoked_at IS NULL
  AND json_extract(r.receipt_json,'$.accountId')=NEW.account_id
  AND julianday(json_extract(r.receipt_json,'$.verifiedAt'))<=julianday('now')
  AND julianday(json_extract(r.receipt_json,'$.expiresAt'))>julianday('now')
  AND julianday(json_extract(r.receipt_json,'$.expiresAt'))>julianday(json_extract(r.receipt_json,'$.verifiedAt'))
  AND julianday(json_extract(r.receipt_json,'$.expiresAt'))-julianday(json_extract(r.receipt_json,'$.verifiedAt'))<=1
)
BEGIN SELECT RAISE(ABORT,'free_receipt_slot_invalid'); END;
CREATE TRIGGER ai_free_slot_insert_history AFTER INSERT ON ai_free_receipt_slots
BEGIN INSERT INTO ai_free_receipt_slot_history VALUES(NEW.slot_id,NEW.account_id,NEW.receipt_id,NEW.generation); END;
CREATE TRIGGER ai_free_slot_update_history AFTER UPDATE ON ai_free_receipt_slots
BEGIN INSERT INTO ai_free_receipt_slot_history VALUES(NEW.slot_id,NEW.account_id,NEW.receipt_id,NEW.generation); END;
CREATE TRIGGER ai_free_slot_no_delete BEFORE DELETE ON ai_free_receipt_slots
BEGIN SELECT RAISE(ABORT,'free_receipt_slot_no_delete'); END;
CREATE TRIGGER ai_free_slot_history_no_update BEFORE UPDATE ON ai_free_receipt_slot_history
BEGIN SELECT RAISE(ABORT,'free_receipt_slot_history_immutable'); END;
CREATE TRIGGER ai_free_slot_history_no_delete BEFORE DELETE ON ai_free_receipt_slot_history
BEGIN SELECT RAISE(ABORT,'free_receipt_slot_history_immutable'); END;

-- REPLACE must not silently delete/reinsert an immutable identity, even when
-- SQLite recursive_triggers is OFF. No reliance on delete triggers here.
CREATE TRIGGER ai_free_slot_history_no_replace BEFORE INSERT ON ai_free_receipt_slot_history
WHEN EXISTS(SELECT 1 FROM ai_free_receipt_slot_history h WHERE h.slot_id=NEW.slot_id AND h.account_id=NEW.account_id AND (h.receipt_id=NEW.receipt_id OR h.generation=NEW.generation))
BEGIN SELECT RAISE(ABORT,'free_receipt_slot_history_immutable'); END;
CREATE TRIGGER ai_free_receipt_no_replace BEFORE INSERT ON ai_free_account_receipts
WHEN EXISTS(SELECT 1 FROM ai_free_account_receipts r WHERE r.id=NEW.id)
BEGIN SELECT RAISE(ABORT,'free_account_receipt_immutable'); END;
