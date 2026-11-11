package postgres

import (
	"context"
	"github.com/google/uuid"
	"github.com/yourorg/mycloud/internal/domain"
)

func (r *UserRepository) DeleteAccount(ctx context.Context, id uuid.UUID, passwordHash string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	// Serialize account administration/deletion so two admins cannot remove the last
	// administrative account concurrently. The lock is scoped to MyCloud's database.
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(684306103)`); err != nil {
		return err
	}
	var role, avatar string
	if err = tx.QueryRow(ctx, `SELECT role,COALESCE(avatar_key,'') FROM users WHERE id=$1 AND active AND password_hash=$2 FOR UPDATE`, id, passwordHash).Scan(&role, &avatar); err != nil {
		return domain.ErrInvalidCredentials
	}
	var blocked bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM families f JOIN family_memberships m ON m.family_id=f.id WHERE f.owner_id=$1 AND m.user_id<>$1) OR ($2='admin' AND NOT EXISTS(SELECT 1 FROM users WHERE active AND role='admin' AND id<>$1))`, id, role).Scan(&blocked); err != nil {
		return err
	}
	if blocked {
		return domain.ErrConflict
	}
	if avatar != "" {
		if _, err = tx.Exec(ctx, `INSERT INTO avatar_deletions(object_key) VALUES($1) ON CONFLICT DO NOTHING`, avatar); err != nil {
			return err
		}
	}
	statements := []string{
		`DELETE FROM family_invitations WHERE created_by=$1 OR email=(SELECT lower(email) FROM users WHERE id=$1)`,
		`DELETE FROM posts WHERE author_id=$1`,
		`DELETE FROM families WHERE owner_id=$1`,
		`DELETE FROM family_memberships WHERE user_id=$1`,
		`DELETE FROM comments WHERE user_id=$1`,
		`DELETE FROM favorites WHERE user_id=$1`,
		`DELETE FROM shares WHERE shared_by=$1 OR shared_with=$1`,
		`DELETE FROM media WHERE owner_id=$1`,
		`DELETE FROM albums WHERE owner_id=$1`,
		`UPDATE upload_sessions SET expires_at=now() WHERE owner_id=$1`,
		`UPDATE audit_log SET actor_id=NULL,target_id=NULL,meta='{}'::jsonb WHERE actor_id=$1 OR target_id=$1`,
		`UPDATE users SET active=false,email='deleted-'||id::text||'@invalid',display_name='Deleted member',avatar_key=NULL,password_hash='',invite_token=NULL,invite_token_expires_at=NULL,deletion_requested_at=now() WHERE id=$1`,
	}
	for _, statement := range statements {
		if _, err = tx.Exec(ctx, statement, id); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (r *MediaRepository) DrainAvatarDeletions(ctx context.Context, storage domain.AvatarStorage) error {
	rows, err := r.db.Query(ctx, `SELECT object_key FROM avatar_deletions ORDER BY created_at LIMIT 100`)
	if err != nil {
		return err
	}
	var keys []string
	for rows.Next() {
		var key string
		if err := rows.Scan(&key); err != nil {
			rows.Close()
			return err
		}
		keys = append(keys, key)
	}
	scanErr := rows.Err()
	rows.Close()
	if scanErr != nil {
		return scanErr
	}
	for _, key := range keys {
		if err := storage.DeleteAvatar(ctx, key); err != nil {
			return err
		}
		if _, err := r.db.Exec(ctx, `DELETE FROM avatar_deletions WHERE object_key=$1`, key); err != nil {
			return err
		}
	}
	return nil
}
