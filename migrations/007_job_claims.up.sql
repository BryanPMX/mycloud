-- Retain one active processing job per asset. Existing duplicate dispatch records
-- are superseded; media and objects are never deleted by this migration.
WITH duplicates AS (
 SELECT id, row_number() OVER(PARTITION BY media_id,type ORDER BY created_at,id) AS n
 FROM jobs WHERE media_id IS NOT NULL AND status IN ('queued','running')
)
UPDATE jobs SET status='failed',error='superseded duplicate',attempts=3,completed_at=now()
WHERE id IN (SELECT id FROM duplicates WHERE n>1);
CREATE UNIQUE INDEX jobs_one_active_media ON jobs(media_id,type) WHERE media_id IS NOT NULL AND status IN ('queued','running');
