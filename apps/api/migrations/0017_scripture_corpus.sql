-- Optional primary-text corpus. No corpus or model is enabled by this migration.
-- A ready revision is append-only: corrections require a new manifest/version.
CREATE TABLE scripture_corpora (
 id TEXT NOT NULL,
 version TEXT NOT NULL,
 edition TEXT NOT NULL,
 language TEXT NOT NULL CHECK(language='en'),
 license TEXT NOT NULL CHECK(license='public-domain'),
 manifest_sha256 TEXT NOT NULL CHECK(length(manifest_sha256)=64),
 manifest_json TEXT NOT NULL CHECK(json_valid(manifest_json) AND length(CAST(manifest_json AS BLOB))<=262144),
 expected_verses INTEGER NOT NULL CHECK(expected_verses BETWEEN 1 AND 40000),
 state TEXT NOT NULL DEFAULT 'staging' CHECK(state IN('staging','ready')),
 rights_status TEXT NOT NULL DEFAULT 'pending' CHECK(rights_status IN('pending','approved','revoked')),
 active INTEGER NOT NULL DEFAULT 0 CHECK(active IN(0,1)),
 created_at INTEGER NOT NULL,
 PRIMARY KEY(id,version),
 CHECK(active=0 OR (state='ready' AND rights_status='approved'))
);
CREATE UNIQUE INDEX scripture_one_active ON scripture_corpora(id) WHERE active=1;
CREATE TABLE scripture_verses (
 corpus_id TEXT NOT NULL,
 corpus_version TEXT NOT NULL,
 source_id TEXT NOT NULL,
 source_book TEXT NOT NULL,
 source_chapter INTEGER NOT NULL CHECK(source_chapter BETWEEN 1 AND 150),
 source_verse TEXT NOT NULL CHECK(length(source_verse) BETWEEN 1 AND 12),
 book TEXT,
 chapter INTEGER,
 verse INTEGER,
 text TEXT NOT NULL CHECK(length(CAST(text AS BLOB))<=16384),
 alignment TEXT NOT NULL CHECK(alignment IN('canonical-compatible','unsupported')),
 text_status TEXT NOT NULL CHECK(text_status IN('present','empty')),
 PRIMARY KEY(corpus_id,corpus_version,source_book,source_chapter,source_verse),
 FOREIGN KEY(corpus_id,corpus_version) REFERENCES scripture_corpora(id,version),
 CHECK((alignment='unsupported' AND book IS NULL AND chapter IS NULL AND verse IS NULL) OR (alignment='canonical-compatible' AND book IS NOT NULL AND chapter IS NOT NULL AND verse IS NOT NULL AND chapter BETWEEN 1 AND 150 AND verse BETWEEN 1 AND 176 AND book=source_book AND chapter=source_chapter AND source_verse=CAST(verse AS TEXT))),
 CHECK(source_id=corpus_id||':'||source_book||':'||source_chapter||':'||source_verse),
 CHECK((text_status='empty' AND text='') OR (text_status='present' AND length(text)>0))
);
CREATE UNIQUE INDEX scripture_source_id ON scripture_verses(source_id,corpus_version);
CREATE UNIQUE INDEX scripture_reference ON scripture_verses(corpus_id,corpus_version,book,chapter,verse) WHERE alignment='canonical-compatible';
CREATE INDEX scripture_range ON scripture_verses(book,chapter,verse,corpus_id,corpus_version) WHERE alignment='canonical-compatible' AND text_status='present';
CREATE TRIGGER scripture_corpus_immutable BEFORE UPDATE ON scripture_corpora
WHEN NEW.id<>OLD.id OR NEW.version<>OLD.version OR NEW.edition<>OLD.edition OR NEW.language<>OLD.language OR NEW.license<>OLD.license OR NEW.manifest_sha256<>OLD.manifest_sha256 OR NEW.manifest_json<>OLD.manifest_json OR NEW.expected_verses<>OLD.expected_verses OR NEW.created_at<>OLD.created_at OR (OLD.state='ready' AND NEW.state<>'ready')
BEGIN SELECT RAISE(ABORT,'scripture_revision_immutable'); END;
CREATE TRIGGER scripture_corpus_no_delete BEFORE DELETE ON scripture_corpora BEGIN SELECT RAISE(ABORT,'scripture_revision_immutable'); END;
CREATE TRIGGER scripture_corpus_ready BEFORE UPDATE OF state ON scripture_corpora
WHEN NEW.state='ready' AND (SELECT count(*) FROM scripture_verses WHERE corpus_id=NEW.id AND corpus_version=NEW.version)<>NEW.expected_verses
BEGIN SELECT RAISE(ABORT,'scripture_corpus_incomplete'); END;
CREATE TRIGGER scripture_corpus_insert_staging BEFORE INSERT ON scripture_corpora WHEN NEW.state<>'staging' OR NEW.active<>0
BEGIN SELECT RAISE(ABORT,'scripture_corpus_requires_staging'); END;
CREATE TRIGGER scripture_verse_staging BEFORE INSERT ON scripture_verses
WHEN NOT EXISTS(SELECT 1 FROM scripture_corpora WHERE id=NEW.corpus_id AND version=NEW.corpus_version AND state='staging')
BEGIN SELECT RAISE(ABORT,'scripture_revision_sealed'); END;
CREATE TRIGGER scripture_verse_no_update BEFORE UPDATE ON scripture_verses BEGIN SELECT RAISE(ABORT,'scripture_revision_immutable'); END;
CREATE TRIGGER scripture_verse_no_delete BEFORE DELETE ON scripture_verses BEGIN SELECT RAISE(ABORT,'scripture_revision_immutable'); END;
CREATE TRIGGER scripture_corpus_policy_insert AFTER INSERT ON scripture_corpora BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;
CREATE TRIGGER scripture_corpus_policy_update AFTER UPDATE ON scripture_corpora BEGIN UPDATE source_policy_state SET version=version+1 WHERE id=1; END;

-- Corpus and curated sources share citation IDs; reserve the corpus namespace.
CREATE TRIGGER public_source_reserved_scripture_insert BEFORE INSERT ON public_sources WHEN NEW.id LIKE 'webp:%' BEGIN SELECT RAISE(ABORT,'reserved_scripture_namespace'); END;
CREATE TRIGGER public_source_reserved_scripture_update BEFORE UPDATE ON public_sources WHEN NEW.id LIKE 'webp:%' BEGIN SELECT RAISE(ABORT,'reserved_scripture_namespace'); END;
