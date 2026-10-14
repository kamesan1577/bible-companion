-- Stops a comparison prepared before bulk deletion from publishing/recreating private data afterward.
ALTER TABLE users ADD COLUMN data_epoch INTEGER NOT NULL DEFAULT 0;
