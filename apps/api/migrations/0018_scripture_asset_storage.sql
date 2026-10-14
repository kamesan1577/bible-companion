-- Optional immutable Worker Assets storage; no asset corpus is activated by this migration.
ALTER TABLE scripture_corpora ADD COLUMN storage_type TEXT NOT NULL DEFAULT 'd1' CHECK(storage_type IN('d1','assets'));
ALTER TABLE scripture_corpora ADD COLUMN asset_index_sha256 TEXT CHECK(asset_index_sha256 IS NULL OR length(asset_index_sha256)=64);
CREATE TRIGGER scripture_storage_insert BEFORE INSERT ON scripture_corpora
WHEN (NEW.storage_type='assets' AND NEW.asset_index_sha256 IS NULL) OR (NEW.storage_type='d1' AND NEW.asset_index_sha256 IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'invalid_scripture_storage_identity'); END;
CREATE TRIGGER scripture_storage_immutable BEFORE UPDATE ON scripture_corpora
WHEN NEW.storage_type<>OLD.storage_type OR NEW.asset_index_sha256 IS NOT OLD.asset_index_sha256
BEGIN SELECT RAISE(ABORT,'scripture_storage_identity_immutable'); END;
DROP TRIGGER scripture_corpus_ready;
CREATE TRIGGER scripture_corpus_ready BEFORE UPDATE OF state ON scripture_corpora
WHEN NEW.state='ready' AND (
 (NEW.storage_type='d1' AND (SELECT count(*) FROM scripture_verses WHERE corpus_id=NEW.id AND corpus_version=NEW.version)<>NEW.expected_verses)
 OR (NEW.storage_type='assets' AND (NEW.asset_index_sha256 IS NULL OR EXISTS(SELECT 1 FROM scripture_verses WHERE corpus_id=NEW.id AND corpus_version=NEW.version)))
)
BEGIN SELECT RAISE(ABORT,'scripture_corpus_incomplete'); END;
CREATE TRIGGER scripture_verse_d1_only BEFORE INSERT ON scripture_verses
WHEN NOT EXISTS(SELECT 1 FROM scripture_corpora WHERE id=NEW.corpus_id AND version=NEW.corpus_version AND storage_type='d1')
BEGIN SELECT RAISE(ABORT,'scripture_asset_revision_has_no_verse_rows'); END;
