-- Client-driven comparisons: one durable trial claim per HTTP invocation.
ALTER TABLE comparison_jobs ADD COLUMN plan_fingerprint TEXT;
ALTER TABLE comparison_jobs ADD COLUMN policy_version INTEGER;
ALTER TABLE comparison_jobs ADD COLUMN expires_at INTEGER;
ALTER TABLE comparison_jobs ADD COLUMN trial_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE comparison_jobs ADD COLUMN error_code TEXT;
CREATE UNIQUE INDEX comparison_owner_identity ON comparison_jobs(id,user_id);
CREATE TABLE comparison_trials (
 job_id TEXT NOT NULL,
 user_id TEXT NOT NULL,
 trial_index INTEGER NOT NULL CHECK(trial_index BETWEEN 0 AND 19),
 question_index INTEGER NOT NULL,
 model_index INTEGER NOT NULL,
 model_id TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','running','complete','failed','cancelled')),
 amount INTEGER NOT NULL CHECK(amount>0),
 proof_fingerprint TEXT NOT NULL,
 dispatched INTEGER NOT NULL DEFAULT 0 CHECK(dispatched IN (0,1)),
 model_invoked INTEGER CHECK(model_invoked IN (0,1)),
 lease_token TEXT,
 lease_expires_at INTEGER,
 metrics_json TEXT,
 PRIMARY KEY(job_id,trial_index),
 FOREIGN KEY(job_id,user_id) REFERENCES comparison_jobs(id,user_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX comparison_one_trial_running ON comparison_trials(job_id) WHERE state='running';
CREATE TRIGGER comparison_terminal_settlement AFTER UPDATE OF status ON comparison_jobs
WHEN NEW.status IN ('complete','cancelled','failed','expired') AND NEW.trial_count>0
BEGIN
 UPDATE budget_reservations SET actual=COALESCE((SELECT SUM(amount*dispatched) FROM comparison_trials WHERE job_id=NEW.id AND user_id=NEW.user_id),0),state='settled' WHERE id='comparison:'||NEW.id AND user_id=NEW.user_id AND state='reserved';
 UPDATE comparison_trials SET state=CASE WHEN state='running' THEN 'failed' ELSE 'cancelled' END WHERE job_id=NEW.id AND state IN ('queued','running');
END;
CREATE TRIGGER comparison_delete_settlement BEFORE DELETE ON comparison_jobs WHEN OLD.trial_count>0
BEGIN
 UPDATE budget_reservations SET actual=COALESCE((SELECT SUM(amount*dispatched) FROM comparison_trials WHERE job_id=OLD.id AND user_id=OLD.user_id),0),state='settled' WHERE id='comparison:'||OLD.id AND user_id=OLD.user_id AND state='reserved';
END;
CREATE TRIGGER comparison_reserve_active BEFORE INSERT ON budget_reservations
WHEN substr(NEW.id,1,11)='comparison:' AND NOT EXISTS(SELECT 1 FROM comparison_jobs WHERE id=substr(NEW.id,12) AND user_id=NEW.user_id AND status IN ('reserved','running'))
BEGIN SELECT RAISE(ABORT,'comparison_inactive'); END;
-- An older all-at-once invocation has no trial evidence and cannot be resumed safely.
UPDATE budget_reservations SET state='settled' WHERE state='reserved' AND id IN (SELECT 'comparison:'||id FROM comparison_jobs WHERE trial_count=0 AND status IN ('reserved','running'));
UPDATE comparison_jobs SET status='failed',error_code='legacy_execution_interrupted' WHERE trial_count=0 AND status IN ('reserved','running');
-- A live invocation can prove it aborted before calling the provider after the dispatch CAS.
-- Reconcile even if cancellation already settled the held allowance; a second clear cannot credit twice.
CREATE TRIGGER comparison_proven_no_dispatch AFTER UPDATE OF dispatched ON comparison_trials
WHEN OLD.dispatched=1 AND NEW.dispatched=0 AND OLD.model_invoked IS NULL AND NEW.model_invoked=0
BEGIN
 UPDATE budget_days SET consumed=consumed-OLD.amount WHERE day=(SELECT day FROM budget_reservations WHERE id='comparison:'||OLD.job_id AND user_id=OLD.user_id AND state='settled' AND COALESCE(actual,amount)>=OLD.amount);
 UPDATE user_budget_days SET consumed=consumed-OLD.amount WHERE user_id=OLD.user_id AND day=(SELECT day FROM budget_reservations WHERE id='comparison:'||OLD.job_id AND user_id=OLD.user_id AND state='settled' AND COALESCE(actual,amount)>=OLD.amount);
 UPDATE budget_reservations SET actual=COALESCE(actual,amount)-OLD.amount WHERE id='comparison:'||OLD.job_id AND user_id=OLD.user_id AND state='settled' AND COALESCE(actual,amount)>=OLD.amount;
END;
