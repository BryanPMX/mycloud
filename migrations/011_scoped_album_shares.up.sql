ALTER TABLE shares ADD COLUMN family_id uuid REFERENCES families(id) ON DELETE CASCADE;
-- Preserve the original installation's existing all-family album grants.
UPDATE shares SET family_id=(SELECT id FROM families WHERE legacy)
 WHERE shared_with='00000000-0000-0000-0000-000000000000'::uuid;
DROP INDEX idx_shares_unique;
CREATE UNIQUE INDEX shares_user_unique ON shares(album_id,shared_with)
 WHERE shared_with<>'00000000-0000-0000-0000-000000000000'::uuid;
CREATE UNIQUE INDEX shares_family_unique ON shares(album_id,family_id)
 WHERE shared_with='00000000-0000-0000-0000-000000000000'::uuid;
CREATE FUNCTION share_applies_to(viewer uuid,grant_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM shares s WHERE s.id=grant_id AND (s.expires_at IS NULL OR s.expires_at>now()) AND (
 (s.shared_with=viewer AND users_share_family(viewer,s.shared_by)) OR
 (s.shared_with='00000000-0000-0000-0000-000000000000'::uuid AND EXISTS(
 SELECT 1 FROM family_memberships viewer_member JOIN family_memberships owner_member USING(family_id)
 WHERE viewer_member.family_id=s.family_id AND viewer_member.user_id=viewer AND owner_member.user_id=s.shared_by))))
$$;
CREATE FUNCTION can_view_album(viewer uuid,album uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM albums a JOIN users u ON u.id=viewer AND u.active
 WHERE a.id=album AND (a.owner_id=viewer OR EXISTS(SELECT 1 FROM shares s WHERE s.album_id=a.id AND share_applies_to(viewer,s.id))))
$$;
CREATE OR REPLACE FUNCTION can_view_media(viewer uuid,asset uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM media m JOIN users viewer_account ON viewer_account.id=viewer AND viewer_account.active
 WHERE m.id=asset AND m.deleted_at IS NULL AND (
 m.owner_id=viewer OR EXISTS(SELECT 1 FROM album_media am JOIN shares s ON s.album_id=am.album_id
 WHERE am.media_id=m.id AND share_applies_to(viewer,s.id)) OR EXISTS(
 SELECT 1 FROM post_media pm JOIN posts p ON p.id=pm.post_id
 JOIN family_memberships fm ON fm.family_id=p.family_id AND fm.user_id=viewer
 JOIN family_memberships author_member ON author_member.family_id=p.family_id AND author_member.user_id=p.author_id
 WHERE pm.media_id=m.id)))
$$;
