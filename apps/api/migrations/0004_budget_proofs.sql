-- No proof rows are seeded. Provision only from an authorized, reviewed account/model calibration.
CREATE TABLE model_budget_proofs (
 model_id TEXT PRIMARY KEY,
 pricing_version TEXT NOT NULL,
 bounds_json TEXT NOT NULL,
 created_at INTEGER NOT NULL
);
