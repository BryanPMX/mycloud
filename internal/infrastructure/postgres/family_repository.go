package postgres

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/pagination"
	"strings"
)

type FamilyRepository struct{ db *pgxpool.Pool }

func NewFamilyRepository(db *pgxpool.Pool) *FamilyRepository { return &FamilyRepository{db: db} }
func (r *FamilyRepository) ListFamilies(ctx context.Context, user uuid.UUID) ([]domain.Family, error) {
	rows, err := r.db.Query(ctx, `SELECT f.id,f.name,f.owner_id,m.role,f.created_at FROM families f JOIN family_memberships m ON m.family_id=f.id JOIN users u ON u.id=m.user_id WHERE m.user_id=$1 AND u.active ORDER BY f.created_at,f.id`, user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []domain.Family{}
	for rows.Next() {
		var f domain.Family
		if err := rows.Scan(&f.ID, &f.Name, &f.OwnerID, &f.Role, &f.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, f)
	}
	return items, rows.Err()
}
func (r *FamilyRepository) CreateFamily(ctx context.Context, user uuid.UUID, name string) (*domain.Family, error) {
	name = strings.TrimSpace(name)
	if len(name) == 0 || len(name) > 100 {
		return nil, domain.ErrInvalidInput
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	var active bool
	if err = tx.QueryRow(ctx, `SELECT active FROM users WHERE id=$1 FOR UPDATE`, user).Scan(&active); err != nil {
		return nil, err
	}
	if !active {
		return nil, domain.ErrUnauthorized
	}
	var count int
	if err = tx.QueryRow(ctx, `SELECT count(*) FROM families WHERE owner_id=$1`, user).Scan(&count); err != nil {
		return nil, err
	}
	if count >= 10 {
		return nil, domain.ErrConflict
	}
	f := &domain.Family{ID: uuid.New(), Name: name, OwnerID: user, Role: "owner"}
	if err = tx.QueryRow(ctx, `INSERT INTO families(id,name,owner_id) VALUES($1,$2,$3) RETURNING created_at`, f.ID, name, user).Scan(&f.CreatedAt); err != nil {
		return nil, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO family_memberships(family_id,user_id,role) VALUES($1,$2,'owner')`, f.ID, user); err != nil {
		return nil, err
	}
	return f, tx.Commit(ctx)
}
func requireFamily(ctx context.Context, tx pgx.Tx, user, family uuid.UUID, admin bool) error {
	var role string
	err := tx.QueryRow(ctx, `SELECT m.role FROM family_memberships m JOIN users u ON u.id=m.user_id WHERE family_id=$1 AND user_id=$2 AND u.active FOR SHARE OF m,u`, family, user).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrNotFound
	}
	if err != nil {
		return err
	}
	if admin && role != "owner" && role != "admin" {
		return domain.ErrForbidden
	}
	return nil
}
func (r *FamilyRepository) ListMembers(ctx context.Context, user, family uuid.UUID) ([]domain.FamilyMember, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	if err = requireFamily(ctx, tx, user, family, false); err != nil {
		return nil, err
	}
	rows, err := tx.Query(ctx, `SELECT u.id,u.display_name,m.role FROM family_memberships m JOIN users u ON u.id=m.user_id WHERE family_id=$1 AND u.active ORDER BY u.display_name,u.id`, family)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []domain.FamilyMember{}
	for rows.Next() {
		var m domain.FamilyMember
		if err := rows.Scan(&m.UserID, &m.DisplayName, &m.Role); err != nil {
			return nil, err
		}
		items = append(items, m)
	}
	return items, rows.Err()
}
func (r *FamilyRepository) CreateInvitation(ctx context.Context, user, family uuid.UUID, email, hash string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err = requireFamily(ctx, tx, user, family, true); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO family_invitations(family_id,email,token_hash,created_by,expires_at) VALUES($1,lower($2),$3,$4,now()+interval '7 days')`, family, email, hash, user)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func (r *FamilyRepository) AcceptInvitation(ctx context.Context, user uuid.UUID, hash string) (uuid.UUID, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	defer tx.Rollback(ctx)
	var family uuid.UUID
	err = tx.QueryRow(ctx, `UPDATE family_invitations i SET accepted_at=now() FROM users u WHERE u.id=$1 AND u.active AND lower(u.email)=i.email AND i.token_hash=$2 AND i.accepted_at IS NULL AND i.expires_at>now() RETURNING i.family_id`, user, hash).Scan(&family)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, domain.ErrInvalidToken
	}
	if err != nil {
		return uuid.Nil, err
	}
	_, err = tx.Exec(ctx, `INSERT INTO family_memberships(family_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING`, family, user)
	if err != nil {
		return uuid.Nil, err
	}
	return family, tx.Commit(ctx)
}
func (r *FamilyRepository) RemoveMember(ctx context.Context, user, family, target uuid.UUID) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	// Lock the family to serialize ownership/membership changes and invitations.
	var owner uuid.UUID
	if err = tx.QueryRow(ctx, `SELECT owner_id FROM families WHERE id=$1 FOR UPDATE`, family).Scan(&owner); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		return err
	}
	if err = requireFamily(ctx, tx, user, family, user != target); err != nil {
		return err
	}
	if target == owner {
		return domain.ErrConflict
	}
	if user != owner && user != target {
		var role string
		if err = tx.QueryRow(ctx, `SELECT role FROM family_memberships WHERE family_id=$1 AND user_id=$2`, family, target).Scan(&role); err != nil {
			return domain.ErrNotFound
		}
		if role != "member" {
			return domain.ErrForbidden
		}
	}
	if _, err = tx.Exec(ctx, `DELETE FROM posts WHERE family_id=$1 AND author_id=$2`, family, target); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `DELETE FROM family_invitations WHERE family_id=$1 AND created_by=$2 AND accepted_at IS NULL`, family, target); err != nil {
		return err
	}
	tag, err := tx.Exec(ctx, `DELETE FROM family_memberships WHERE family_id=$1 AND user_id=$2`, family, target)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return tx.Commit(ctx)
}
func (r *FamilyRepository) CreatePost(ctx context.Context, user, family uuid.UUID, caption string, ids []uuid.UUID) (uuid.UUID, error) {
	caption = strings.TrimSpace(caption)
	if len(caption) > 2000 || len(ids) == 0 || len(ids) > 20 {
		return uuid.Nil, domain.ErrInvalidInput
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return uuid.Nil, err
	}
	defer tx.Rollback(ctx)
	if err = requireFamily(ctx, tx, user, family, false); err != nil {
		return uuid.Nil, err
	}
	// Share locks prevent ownership/status checks racing permanent deletion.
	rows, err := tx.Query(ctx, `SELECT id FROM media WHERE id=ANY($1) AND owner_id=$2 AND deleted_at IS NULL AND status='ready' FOR SHARE`, ids, user)
	if err != nil {
		return uuid.Nil, err
	}
	count := 0
	for rows.Next() {
		count++
	}
	scanErr := rows.Err()
	rows.Close()
	if scanErr != nil {
		return uuid.Nil, scanErr
	}
	if count != len(ids) {
		return uuid.Nil, domain.ErrForbidden
	}
	id := uuid.New()
	if _, err = tx.Exec(ctx, `INSERT INTO posts(id,author_id,family_id,caption) VALUES($1,$2,$3,$4)`, id, user, family, caption); err != nil {
		return uuid.Nil, err
	}
	for i, asset := range ids {
		if _, err = tx.Exec(ctx, `INSERT INTO post_media(post_id,media_id,position) VALUES($1,$2,$3)`, id, asset, i); err != nil {
			return uuid.Nil, err
		}
	}
	return id, tx.Commit(ctx)
}
func (r *FamilyRepository) DeletePost(ctx context.Context, user, family, post uuid.UUID) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM posts p WHERE p.id=$1 AND p.family_id=$2 AND p.author_id=$3 AND EXISTS(SELECT 1 FROM family_memberships m WHERE m.family_id=p.family_id AND m.user_id=$3)`, post, family, user)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}
func (r *FamilyRepository) ListPosts(ctx context.Context, user, family uuid.UUID, cursor string) (domain.PostPage, error) {
	_, at, id, err := decodePageCursor(cursor, 20)
	if err != nil {
		return domain.PostPage{}, err
	}
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead})
	if err != nil {
		return domain.PostPage{}, err
	}
	defer tx.Rollback(ctx)
	if err = requireFamily(ctx, tx, user, family, false); err != nil {
		return domain.PostPage{}, err
	}
	rows, err := tx.Query(ctx, `SELECT p.id,p.author_id,u.display_name,p.caption,p.created_at FROM posts p JOIN users u ON u.id=p.author_id AND u.active JOIN family_memberships author ON author.family_id=p.family_id AND author.user_id=p.author_id WHERE p.family_id=$1 AND ($2::timestamptz IS NULL OR (p.created_at,p.id)<($2,$3)) AND EXISTS(SELECT 1 FROM post_media pm JOIN media m ON m.id=pm.media_id WHERE pm.post_id=p.id AND m.deleted_at IS NULL AND m.status='ready') ORDER BY p.created_at DESC,p.id DESC LIMIT 21`, family, at, id)
	if err != nil {
		return domain.PostPage{}, err
	}
	page := domain.PostPage{Items: []*domain.Post{}}
	for rows.Next() {
		p := &domain.Post{FamilyID: family}
		if err := rows.Scan(&p.ID, &p.AuthorID, &p.AuthorName, &p.Caption, &p.CreatedAt); err != nil {
			rows.Close()
			return page, err
		}
		page.Items = append(page.Items, p)
	}
	scanErr := rows.Err()
	rows.Close()
	if scanErr != nil {
		return page, scanErr
	}
	if len(page.Items) > 20 {
		page.Items = page.Items[:20]
		last := page.Items[19]
		page.NextCursor, err = pagination.EncodeTimeUUID(last.CreatedAt, last.ID)
		if err != nil {
			return page, err
		}
	}
	for _, p := range page.Items {
		mediaRows, err := tx.Query(ctx, `SELECT `+mediaSelectColumns+` FROM post_media pm JOIN media m ON m.id=pm.media_id WHERE pm.post_id=$1 AND m.deleted_at IS NULL AND m.status='ready' ORDER BY pm.position`, p.ID)
		if err != nil {
			return page, err
		}
		p.Media, err = scanMediaRows(mediaRows)
		if err != nil {
			return page, err
		}
	}
	return page, tx.Commit(ctx)
}
