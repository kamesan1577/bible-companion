-- Public citation identity is immutable even across deletion and reinsertion.
-- Rights/active flags remain mutable policy state and are checked separately at read time.
CREATE TABLE source_revisions (
 source_id TEXT NOT NULL,
 version TEXT NOT NULL,
 content_identity TEXT NOT NULL,
 PRIMARY KEY(source_id,version)
);
INSERT INTO source_revisions(source_id,version,content_identity)
SELECT id,version,json_object('book',book,'start_chapter',start_chapter,'start_verse',start_verse,'end_chapter',end_chapter,'end_verse',end_verse,'kind',kind,'title',title,'content_json',content_json) FROM public_sources;
CREATE TRIGGER source_revision_before_insert BEFORE INSERT ON public_sources
WHEN EXISTS(SELECT 1 FROM source_revisions WHERE source_id=NEW.id AND version=NEW.version AND content_identity<>json_object('book',NEW.book,'start_chapter',NEW.start_chapter,'start_verse',NEW.start_verse,'end_chapter',NEW.end_chapter,'end_verse',NEW.end_verse,'kind',NEW.kind,'title',NEW.title,'content_json',NEW.content_json))
BEGIN SELECT RAISE(ABORT,'source_version_content_conflict'); END;
CREATE TRIGGER source_revision_after_insert AFTER INSERT ON public_sources BEGIN
INSERT OR IGNORE INTO source_revisions(source_id,version,content_identity) VALUES(NEW.id,NEW.version,json_object('book',NEW.book,'start_chapter',NEW.start_chapter,'start_verse',NEW.start_verse,'end_chapter',NEW.end_chapter,'end_verse',NEW.end_verse,'kind',NEW.kind,'title',NEW.title,'content_json',NEW.content_json)); END;
CREATE TRIGGER source_revision_before_update BEFORE UPDATE ON public_sources
WHEN EXISTS(SELECT 1 FROM source_revisions WHERE source_id=NEW.id AND version=NEW.version AND content_identity<>json_object('book',NEW.book,'start_chapter',NEW.start_chapter,'start_verse',NEW.start_verse,'end_chapter',NEW.end_chapter,'end_verse',NEW.end_verse,'kind',NEW.kind,'title',NEW.title,'content_json',NEW.content_json))
BEGIN SELECT RAISE(ABORT,'source_version_content_conflict'); END;
CREATE TRIGGER source_revision_after_update AFTER UPDATE ON public_sources BEGIN
INSERT OR IGNORE INTO source_revisions(source_id,version,content_identity) VALUES(NEW.id,NEW.version,json_object('book',NEW.book,'start_chapter',NEW.start_chapter,'start_verse',NEW.start_verse,'end_chapter',NEW.end_chapter,'end_verse',NEW.end_verse,'kind',NEW.kind,'title',NEW.title,'content_json',NEW.content_json)); END;
