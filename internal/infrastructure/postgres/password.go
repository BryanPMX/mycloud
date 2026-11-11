package postgres

import (
	"context"
	"github.com/google/uuid"
	"github.com/yourorg/mycloud/internal/domain"
)

func (r *UserRepository) ChangePassword(ctx context.Context, id uuid.UUID, previousHash, nextHash string) error {
	result, err := r.db.Exec(ctx, `UPDATE users SET password_hash=$3,auth_version=auth_version+1,updated_at=now() WHERE id=$1 AND password_hash=$2 AND active`, id, previousHash, nextHash)
	if err != nil {
		return err
	}
	if result.RowsAffected() != 1 {
		return domain.ErrConflict
	}
	return nil
}
