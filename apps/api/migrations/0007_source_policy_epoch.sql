-- An atomic content-policy epoch closes revocation/correction races during inference.
CREATE TABLE source_policy_state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL);
INSERT INTO source_policy_state(id,version) VALUES(1,1);
CREATE TRIGGER source_policy_insert AFTER INSERT ON public_sources BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
CREATE TRIGGER source_policy_update AFTER UPDATE ON public_sources BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
CREATE TRIGGER source_policy_delete AFTER DELETE ON public_sources BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
