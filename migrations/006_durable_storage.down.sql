-- Requires an explicit reviewed rollback after draining reservations/deletions.
DO $$ BEGIN RAISE EXCEPTION 'Restore the verified pre-migration backup; automatic storage rollback is unsafe'; END $$;
