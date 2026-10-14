-- Reviewed material summaries become citable commentary. Preserve semantic version identity.
CREATE TABLE material_revisions (
 material_id TEXT NOT NULL,
 version TEXT NOT NULL,
 content_identity TEXT NOT NULL,
 PRIMARY KEY(material_id,version)
);
INSERT INTO material_revisions(material_id,version,content_identity)
SELECT id,version,json_object('kind',kind,'book',book,'data_json',data_json) FROM public_materials;
CREATE TRIGGER material_revision_before_insert BEFORE INSERT ON public_materials
WHEN EXISTS(SELECT 1 FROM material_revisions WHERE material_id=NEW.id AND version=NEW.version AND content_identity<>json_object('kind',NEW.kind,'book',NEW.book,'data_json',NEW.data_json))
BEGIN SELECT RAISE(ABORT,'material_version_content_conflict'); END;
CREATE TRIGGER material_revision_after_insert AFTER INSERT ON public_materials BEGIN
INSERT OR IGNORE INTO material_revisions(material_id,version,content_identity) VALUES(NEW.id,NEW.version,json_object('kind',NEW.kind,'book',NEW.book,'data_json',NEW.data_json)); END;
CREATE TRIGGER material_revision_before_update BEFORE UPDATE ON public_materials
WHEN EXISTS(SELECT 1 FROM material_revisions WHERE material_id=NEW.id AND version=NEW.version AND content_identity<>json_object('kind',NEW.kind,'book',NEW.book,'data_json',NEW.data_json))
BEGIN SELECT RAISE(ABORT,'material_version_content_conflict'); END;
CREATE TRIGGER material_revision_after_update AFTER UPDATE ON public_materials BEGIN
INSERT OR IGNORE INTO material_revisions(material_id,version,content_identity) VALUES(NEW.id,NEW.version,json_object('kind',NEW.kind,'book',NEW.book,'data_json',NEW.data_json)); END;
CREATE TRIGGER material_source_namespace_insert BEFORE INSERT ON public_sources WHEN NEW.id LIKE 'material:%'
BEGIN SELECT RAISE(ABORT,'material_source_namespace_reserved'); END;
CREATE TRIGGER material_source_namespace_update BEFORE UPDATE ON public_sources WHEN NEW.id LIKE 'material:%'
BEGIN SELECT RAISE(ABORT,'material_source_namespace_reserved'); END;
