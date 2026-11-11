CREATE TABLE families (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
 owner_id uuid NOT NULL REFERENCES users(id),
 legacy boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX families_legacy ON families(legacy) WHERE legacy;
CREATE TABLE family_memberships (
 family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES users(id),
 role text NOT NULL CHECK(role IN ('owner','admin','member')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(family_id,user_id)
);
CREATE INDEX family_memberships_user ON family_memberships(user_id,family_id);
-- Preserve the original installation's sharing scope; do not invent new access.
INSERT INTO families(name,owner_id,legacy)
 SELECT 'Our family',id,true FROM users WHERE active ORDER BY (role='admin') DESC,created_at,id LIMIT 1;
INSERT INTO family_memberships(family_id,user_id,role)
 SELECT f.id,u.id,CASE WHEN u.id=f.owner_id THEN 'owner' WHEN u.role='admin' THEN 'admin' ELSE 'member' END FROM families f CROSS JOIN users u WHERE f.legacy;
CREATE FUNCTION add_legacy_family_member() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 INSERT INTO family_memberships(family_id,user_id,role) SELECT id,NEW.id,CASE WHEN NEW.role='admin' THEN 'admin' ELSE 'member' END FROM families WHERE legacy;
 RETURN NEW;
END $$;
CREATE TRIGGER users_legacy_membership AFTER INSERT ON users FOR EACH ROW EXECUTE FUNCTION add_legacy_family_member();
CREATE TABLE family_invitations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 email text NOT NULL,
 token_hash text NOT NULL UNIQUE,
 created_by uuid NOT NULL REFERENCES users(id),
 expires_at timestamptz NOT NULL,
 accepted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE posts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 author_id uuid NOT NULL REFERENCES users(id),
 family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
 caption text NOT NULL DEFAULT '' CHECK(length(caption)<=2000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX posts_family_chronological ON posts(family_id,created_at DESC,id DESC);
CREATE TABLE post_media (
 post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
 media_id uuid NOT NULL REFERENCES media(id) ON DELETE CASCADE,
 position integer NOT NULL,
 PRIMARY KEY(post_id,media_id),
 UNIQUE(post_id,position)
);
CREATE INDEX post_media_asset ON post_media(media_id);
CREATE FUNCTION users_share_family(a uuid,b uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM family_memberships x JOIN family_memberships y USING(family_id)
 JOIN users u ON u.id=x.user_id JOIN users v ON v.id=y.user_id WHERE x.user_id=a AND y.user_id=b AND u.active AND v.active)
$$;
CREATE FUNCTION can_view_media(viewer uuid,asset uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM media m JOIN users viewer_account ON viewer_account.id=viewer AND viewer_account.active
 WHERE m.id=asset AND m.deleted_at IS NULL AND (
 m.owner_id=viewer OR EXISTS(SELECT 1 FROM album_media am JOIN shares s ON s.album_id=am.album_id
 JOIN albums a ON a.id=am.album_id WHERE am.media_id=m.id AND (s.shared_with=viewer OR
 (s.shared_with='00000000-0000-0000-0000-000000000000'::uuid AND users_share_family(viewer,a.owner_id)))
 AND (s.expires_at IS NULL OR s.expires_at>now())) OR EXISTS(
 SELECT 1 FROM post_media pm JOIN posts p ON p.id=pm.post_id
 JOIN family_memberships fm ON fm.family_id=p.family_id AND fm.user_id=viewer
 JOIN family_memberships author_member ON author_member.family_id=p.family_id AND author_member.user_id=p.author_id
 WHERE pm.media_id=m.id)))
$$;
