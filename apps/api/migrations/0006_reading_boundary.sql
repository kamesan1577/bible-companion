-- Question target can be a subset; the reader's actual end remains the spoiler cutoff.
ALTER TABLE conversations ADD COLUMN reading_boundary_json TEXT;
UPDATE conversations SET reading_boundary_json=passage_json WHERE reading_boundary_json IS NULL;
