ALTER TABLE budget_reservations ADD COLUMN app_limit INTEGER NOT NULL DEFAULT 9000;
ALTER TABLE budget_reservations ADD COLUMN user_limit INTEGER NOT NULL DEFAULT 2000;
CREATE TRIGGER reserve_budget BEFORE INSERT ON budget_reservations
BEGIN
 SELECT CASE WHEN (SELECT reserved+consumed+NEW.amount FROM budget_days WHERE day=NEW.day)>NEW.app_limit THEN RAISE(ABORT,'budget_exceeded') END;
 SELECT CASE WHEN (SELECT reserved+consumed+NEW.amount FROM user_budget_days WHERE day=NEW.day AND user_id=NEW.user_id)>NEW.user_limit THEN RAISE(ABORT,'budget_exceeded') END;
 UPDATE budget_days SET reserved=reserved+NEW.amount WHERE day=NEW.day;
 UPDATE user_budget_days SET reserved=reserved+NEW.amount WHERE day=NEW.day AND user_id=NEW.user_id;
END;
CREATE TRIGGER settle_budget AFTER UPDATE OF state ON budget_reservations WHEN OLD.state='reserved' AND NEW.state='settled'
BEGIN
 UPDATE budget_days SET reserved=reserved-OLD.amount,consumed=consumed+COALESCE(NEW.actual,OLD.amount) WHERE day=OLD.day;
 UPDATE user_budget_days SET reserved=reserved-OLD.amount,consumed=consumed+COALESCE(NEW.actual,OLD.amount) WHERE day=OLD.day AND user_id=OLD.user_id;
END;
