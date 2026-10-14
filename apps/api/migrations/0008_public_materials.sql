CREATE TABLE public_materials (
 id TEXT PRIMARY KEY,
 kind TEXT NOT NULL CHECK(kind IN ('person','place','artwork')),
 book TEXT NOT NULL,
 data_json TEXT NOT NULL,
 version TEXT NOT NULL,
 rights_status TEXT NOT NULL CHECK(rights_status IN ('approved','pending','revoked')),
 active INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX material_book ON public_materials(book,kind,active);
CREATE TRIGGER material_policy_insert AFTER INSERT ON public_materials BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
CREATE TRIGGER material_policy_update AFTER UPDATE ON public_materials BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
CREATE TRIGGER material_policy_delete AFTER DELETE ON public_materials BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
