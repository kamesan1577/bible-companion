ALTER TABLE users ADD COLUMN export_epoch INTEGER NOT NULL DEFAULT 0;
CREATE TABLE export_snapshots (
 id TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 export_epoch INTEGER NOT NULL,
 data_epoch INTEGER NOT NULL,
 source_policy_version INTEGER NOT NULL,
 upper_rows_json TEXT NOT NULL,
 created_at INTEGER NOT NULL,
 expires_at INTEGER NOT NULL
);
CREATE INDEX export_snapshot_owner ON export_snapshots(user_id,expires_at);
CREATE TRIGGER export_user_settings AFTER UPDATE OF display_name,role,settings_json ON users BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.id; END;
CREATE TRIGGER export_imports_insert AFTER INSERT ON imports BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_imports_delete AFTER DELETE ON imports BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=OLD.user_id; END;
CREATE TRIGGER export_imports_update AFTER UPDATE ON imports BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_conversations_insert AFTER INSERT ON conversations BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_conversations_delete AFTER DELETE ON conversations BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=OLD.user_id; END;
CREATE TRIGGER export_conversations_update AFTER UPDATE ON conversations BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_messages_insert AFTER INSERT ON messages BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_messages_delete AFTER DELETE ON messages BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=OLD.user_id; END;
CREATE TRIGGER export_messages_update AFTER UPDATE ON messages BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_comparison_jobs_insert AFTER INSERT ON comparison_jobs BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_comparison_jobs_delete AFTER DELETE ON comparison_jobs BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=OLD.user_id; END;
CREATE TRIGGER export_comparison_jobs_update AFTER UPDATE ON comparison_jobs BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_model_preferences_insert AFTER INSERT ON model_preferences BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
CREATE TRIGGER export_model_preferences_delete AFTER DELETE ON model_preferences BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=OLD.user_id; END;
CREATE TRIGGER export_model_preferences_update AFTER UPDATE ON model_preferences BEGIN UPDATE users SET export_epoch=export_epoch+1 WHERE id=NEW.user_id; END;
