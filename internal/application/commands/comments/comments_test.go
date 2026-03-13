package comments

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeUserRepo struct {
	user *domain.User
}

func (r *fakeUserRepo) FindByID(context.Context, uuid.UUID) (*domain.User, error) {
	if r.user == nil {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeMediaRepo struct {
	media *domain.Media
	err   error
}

func (r *fakeMediaRepo) Create(context.Context, *domain.Media) error {
	return nil
}

func (r *fakeMediaRepo) FindByID(context.Context, uuid.UUID) (*domain.Media, error) {
	if r.media == nil {
		return nil, domain.ErrNotFound
	}

	return r.media, nil
}

func (r *fakeMediaRepo) FindByIDForUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	if r.err != nil {
		return nil, r.err
	}
	if r.media == nil {
		return nil, domain.ErrNotFound
	}

	return r.media, nil
}

func (r *fakeMediaRepo) ListVisibleToUser(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeMediaRepo) ListByAlbum(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeMediaRepo) UpdateStatus(context.Context, uuid.UUID, domain.MediaStatus) error {
	return nil
}

func (r *fakeMediaRepo) ApplyProcessingResult(context.Context, uuid.UUID, domain.MediaProcessingResult) error {
	return nil
}

type fakeCommentRepo struct {
	existing  *domain.Comment
	created   *domain.Comment
	deletedID uuid.UUID

	createErr error
	findErr   error
	deleteErr error
}

func (r *fakeCommentRepo) Create(_ context.Context, comment *domain.Comment) error {
	if r.createErr != nil {
		return r.createErr
	}

	copied := *comment
	r.created = &copied
	r.existing = &copied
	return nil
}

func (r *fakeCommentRepo) FindByID(context.Context, uuid.UUID) (*domain.Comment, error) {
	if r.findErr != nil {
		return nil, r.findErr
	}
	if r.existing == nil {
		return nil, domain.ErrNotFound
	}

	return r.existing, nil
}

func (r *fakeCommentRepo) ListByMedia(context.Context, uuid.UUID) ([]*domain.Comment, error) {
	return nil, nil
}

func (r *fakeCommentRepo) SoftDelete(_ context.Context, id uuid.UUID, _ time.Time) error {
	if r.deleteErr != nil {
		return r.deleteErr
	}

	r.deletedID = id
	return nil
}

func TestAddCommentHandlerExecuteCreatesTrimmedComment(t *testing.T) {
	t.Parallel()

	user := &domain.User{
		ID:          uuid.New(),
		Active:      true,
		DisplayName: "Bryan",
		AvatarKey:   "avatars/bryan.webp",
	}
	media := &domain.Media{ID: uuid.New(), OwnerID: user.ID}
	commentRepo := &fakeCommentRepo{}

	handler := NewAddCommentHandler(
		&fakeUserRepo{user: user},
		&fakeMediaRepo{media: media},
		commentRepo,
	)

	comment, err := handler.Execute(context.Background(), AddCommentCommand{
		UserID:  user.ID,
		MediaID: media.ID,
		Body:    "  Great shot!  ",
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if comment.Body != "Great shot!" {
		t.Fatalf("Execute() body = %q, want trimmed comment", comment.Body)
	}
	if comment.Author.DisplayName != user.DisplayName {
		t.Fatalf("Execute() author display name = %q, want %q", comment.Author.DisplayName, user.DisplayName)
	}
	if commentRepo.created == nil || commentRepo.created.MediaID != media.ID {
		t.Fatal("Execute() did not persist the comment")
	}
}

func TestAddCommentHandlerExecuteRejectsOversizedBody(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	media := &domain.Media{ID: uuid.New(), OwnerID: user.ID}
	body := make([]rune, maxCommentLength+1)
	for i := range body {
		body[i] = 'a'
	}

	handler := NewAddCommentHandler(
		&fakeUserRepo{user: user},
		&fakeMediaRepo{media: media},
		&fakeCommentRepo{},
	)

	if _, err := handler.Execute(context.Background(), AddCommentCommand{
		UserID:  user.ID,
		MediaID: media.ID,
		Body:    string(body),
	}); err != domain.ErrInvalidInput {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrInvalidInput)
	}
}

func TestDeleteCommentHandlerExecuteDeletesAuthorComment(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleMember}
	comment := &domain.Comment{
		ID:      uuid.New(),
		MediaID: uuid.New(),
		UserID:  user.ID,
	}
	commentRepo := &fakeCommentRepo{existing: comment}

	handler := NewDeleteCommentHandler(&fakeUserRepo{user: user}, commentRepo)
	if err := handler.Execute(context.Background(), DeleteCommentCommand{
		UserID:    user.ID,
		MediaID:   comment.MediaID,
		CommentID: comment.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if commentRepo.deletedID != comment.ID {
		t.Fatal("Execute() did not soft-delete the target comment")
	}
}

func TestDeleteCommentHandlerExecuteRejectsOtherUsers(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleMember}
	comment := &domain.Comment{
		ID:      uuid.New(),
		MediaID: uuid.New(),
		UserID:  uuid.New(),
	}

	handler := NewDeleteCommentHandler(
		&fakeUserRepo{user: user},
		&fakeCommentRepo{existing: comment},
	)

	if err := handler.Execute(context.Background(), DeleteCommentCommand{
		UserID:    user.ID,
		MediaID:   comment.MediaID,
		CommentID: comment.ID,
	}); err != domain.ErrForbidden {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrForbidden)
	}
}
