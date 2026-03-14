package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type AdminRepository struct {
	db *pgxpool.Pool
}

func NewAdminRepository(db *pgxpool.Pool) *AdminRepository {
	return &AdminRepository{db: db}
}

func (r *AdminRepository) ListUsers(ctx context.Context) ([]*domain.User, error) {
	const query = `
		SELECT id, email, display_name, avatar_key, role, password_hash, storage_used,
		       quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		FROM users
		ORDER BY created_at DESC, id DESC
	`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	users := make([]*domain.User, 0)
	for rows.Next() {
		record := userRow{}
		if err := rows.Scan(
			&record.ID,
			&record.Email,
			&record.DisplayName,
			&record.AvatarKey,
			&record.Role,
			&record.PasswordHash,
			&record.StorageUsed,
			&record.QuotaBytes,
			&record.Active,
			&record.InviteToken,
			&record.InviteExpiry,
			&record.CreatedAt,
			&record.UpdatedAt,
			&record.LastLoginAt,
		); err != nil {
			return nil, err
		}
		users = append(users, record.toDomain())
	}

	return users, rows.Err()
}

func (r *AdminRepository) CreateOrRefreshInvite(
	ctx context.Context,
	params domain.InviteUserParams,
	audit *domain.AuditLog,
) (*domain.User, error) {
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer rollbackTx(ctx, tx)

	const selectQuery = `
		SELECT id, email, display_name, avatar_key, role, password_hash, storage_used,
		       quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		FROM users
		WHERE lower(email) = lower($1)
	`

	existing, err := scanUser(tx.QueryRow(ctx, selectQuery, params.Email))
	switch {
	case err == nil:
		if existing.Active {
			return nil, domain.ErrConflict
		}
	case errors.Is(err, domain.ErrNotFound):
		existing = nil
	default:
		return nil, err
	}

	var invited *domain.User
	if existing == nil {
		const insertQuery = `
			INSERT INTO users (
				id, email, display_name, role, password_hash, quota_bytes, active,
				invite_token, invite_token_expires_at, created_at, updated_at
			)
			VALUES ($1, $2, $3, $4, $5, $6, false, $7, $8, $9, $9)
			RETURNING id, email, display_name, avatar_key, role, password_hash, storage_used,
			          quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		`

		invited, err = scanUser(tx.QueryRow(
			ctx,
			insertQuery,
			uuid.New(),
			params.Email,
			params.DisplayName,
			params.Role,
			params.PasswordHash,
			params.QuotaBytes,
			params.InviteTokenHash,
			params.InviteExpiresAt,
			params.CreatedAt,
		))
		if err != nil {
			return nil, mapPGError(err)
		}
	} else {
		const updateQuery = `
			UPDATE users
			SET role = $2,
			    quota_bytes = $3,
			    active = false,
			    invite_token = $4,
			    invite_token_expires_at = $5,
			    updated_at = $6
			WHERE id = $1
			RETURNING id, email, display_name, avatar_key, role, password_hash, storage_used,
			          quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		`

		invited, err = scanUser(tx.QueryRow(
			ctx,
			updateQuery,
			existing.ID,
			params.Role,
			params.QuotaBytes,
			params.InviteTokenHash,
			params.InviteExpiresAt,
			params.CreatedAt,
		))
		if err != nil {
			return nil, err
		}
	}

	if audit != nil && audit.TargetID == nil {
		targetID := invited.ID
		audit.TargetID = &targetID
	}
	if err := insertAuditLogTx(ctx, tx, audit); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return invited, nil
}

func (r *AdminRepository) FindInviteByTokenHash(ctx context.Context, tokenHash string) (*domain.User, error) {
	const query = `
		SELECT id, email, display_name, avatar_key, role, password_hash, storage_used,
		       quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		FROM users
		WHERE invite_token = $1
	`

	return scanUser(r.db.QueryRow(ctx, query, tokenHash))
}

func (r *AdminRepository) AcceptInvite(
	ctx context.Context,
	params domain.AcceptInviteParams,
	audit *domain.AuditLog,
) (*domain.User, error) {
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer rollbackTx(ctx, tx)

	const query = `
		UPDATE users
		SET display_name = $3,
		    password_hash = $4,
		    active = true,
		    invite_token = NULL,
		    invite_token_expires_at = NULL,
		    last_login_at = $5,
		    updated_at = $5
		WHERE id = $1
		  AND invite_token = $2
		  AND invite_token_expires_at IS NOT NULL
		  AND invite_token_expires_at > NOW()
		  AND active = false
		RETURNING id, email, display_name, avatar_key, role, password_hash, storage_used,
		          quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
	`

	user, err := scanUser(tx.QueryRow(
		ctx,
		query,
		params.UserID,
		params.InviteTokenHash,
		params.DisplayName,
		params.PasswordHash,
		params.AcceptedAt,
	))
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return nil, domain.ErrInvalidToken
		}
		return nil, err
	}

	if err := insertAuditLogTx(ctx, tx, audit); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return user, nil
}

func (r *AdminRepository) UpdateUser(
	ctx context.Context,
	params domain.AdminUpdateUserParams,
	audit *domain.AuditLog,
) (*domain.User, error) {
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer rollbackTx(ctx, tx)

	roleSet := params.Role != nil
	roleValue := string(domain.RoleMember)
	if params.Role != nil {
		roleValue = string(*params.Role)
	}

	quotaSet := params.QuotaBytes != nil
	var quotaValue int64
	if params.QuotaBytes != nil {
		quotaValue = *params.QuotaBytes
	}

	activeSet := params.Active != nil
	activeValue := false
	if params.Active != nil {
		activeValue = *params.Active
	}

	const query = `
		UPDATE users
		SET role = CASE WHEN $2 THEN $3::user_role ELSE role END,
		    quota_bytes = CASE WHEN $4 THEN $5 ELSE quota_bytes END,
		    active = CASE WHEN $6 THEN $7 ELSE active END,
		    invite_token = CASE WHEN $8 THEN NULL ELSE invite_token END,
		    invite_token_expires_at = CASE WHEN $8 THEN NULL ELSE invite_token_expires_at END,
		    updated_at = NOW()
		WHERE id = $1
		RETURNING id, email, display_name, avatar_key, role, password_hash, storage_used,
		          quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
	`

	user, err := scanUser(tx.QueryRow(
		ctx,
		query,
		params.UserID,
		roleSet,
		roleValue,
		quotaSet,
		quotaValue,
		activeSet,
		activeValue,
		params.ClearInvite,
	))
	if err != nil {
		return nil, err
	}

	if err := insertAuditLogTx(ctx, tx, audit); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return user, nil
}

func (r *AdminRepository) GetSystemStats(ctx context.Context) (*domain.SystemStats, error) {
	const query = `
		WITH user_stats AS (
			SELECT
				COUNT(*)::bigint AS total_users,
				COUNT(*) FILTER (WHERE active)::bigint AS active_users,
				COALESCE(SUM(quota_bytes), 0)::bigint AS total_quota_bytes,
				COALESCE(SUM(storage_used), 0)::bigint AS used_storage_bytes
			FROM users
		),
		media_stats AS (
			SELECT
				COUNT(*)::bigint AS total_items,
				COUNT(*) FILTER (WHERE mime_type LIKE 'image/%')::bigint AS total_images,
				COUNT(*) FILTER (WHERE mime_type LIKE 'video/%')::bigint AS total_videos
			FROM media
			WHERE deleted_at IS NULL
		),
		job_stats AS (
			SELECT
				COUNT(*) FILTER (WHERE status IN ('queued', 'running'))::bigint AS pending_jobs
			FROM jobs
		)
		SELECT
			us.total_users,
			us.active_users,
			us.total_quota_bytes,
			us.used_storage_bytes,
			GREATEST(us.total_quota_bytes - us.used_storage_bytes, 0)::bigint AS free_storage_bytes,
			CASE
				WHEN us.total_quota_bytes = 0 THEN 0
				ELSE ROUND((100.0 * us.used_storage_bytes::numeric) / us.total_quota_bytes::numeric, 1)
			END::float8 AS storage_pct_used,
			ms.total_items,
			ms.total_images,
			ms.total_videos,
			js.pending_jobs
		FROM user_stats us
		CROSS JOIN media_stats ms
		CROSS JOIN job_stats js
	`

	stats := &domain.SystemStats{}
	if err := r.db.QueryRow(ctx, query).Scan(
		&stats.Users.Total,
		&stats.Users.Active,
		&stats.Storage.TotalBytes,
		&stats.Storage.UsedBytes,
		&stats.Storage.FreeBytes,
		&stats.Storage.PctUsed,
		&stats.Media.TotalItems,
		&stats.Media.TotalImages,
		&stats.Media.TotalVideos,
		&stats.Media.PendingJobs,
	); err != nil {
		return nil, err
	}

	return stats, nil
}

func insertAuditLogTx(ctx context.Context, tx pgx.Tx, audit *domain.AuditLog) error {
	if audit == nil {
		return nil
	}

	payload, err := json.Marshal(audit.Meta)
	if err != nil {
		return err
	}

	var ipAddress any
	if audit.IPAddress != nil {
		ipAddress = audit.IPAddress.String()
	}

	const query = `
		INSERT INTO audit_log (actor_id, action, target_id, meta, ip_address, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	_, err = tx.Exec(ctx, query, audit.ActorID, audit.Action, audit.TargetID, payload, ipAddress, audit.CreatedAt)
	return err
}

func rollbackTx(ctx context.Context, tx pgx.Tx) {
	_ = tx.Rollback(ctx)
}

func mapPGError(err error) error {
	if err == nil {
		return nil
	}

	// The repo only needs a narrow mapping for this slice.
	if strings.Contains(err.Error(), "duplicate key") {
		return domain.ErrConflict
	}

	return err
}
