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

func (r *fakeMediaRepo) UpdateStatus(context.Context, uuid.UUID, domain.MediaStatus) error {
	return nil
}

func (r *fakeMediaRepo) ApplyProcessingResult(context.Context, uuid.UUID, domain.MediaProcessingResult) error {
	return nil
}

type fakeCommentRepo struct {
	comments []*domain.Comment
}

func (r *fakeCommentRepo) Create(context.Context, *domain.Comment) error {
	return nil
}

func (r *fakeCommentRepo) FindByID(context.Context, uuid.UUID) (*domain.Comment, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeCommentRepo) ListByMedia(context.Context, uuid.UUID) ([]*domain.Comment, error) {
	return r.comments, nil
}

func (r *fakeCommentRepo) SoftDelete(context.Context, uuid.UUID, time.Time) error {
	return nil
}

func TestListCommentsHandlerExecuteReturnsOrderedThread(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	media := &domain.Media{ID: uuid.New()}
	comments := []*domain.Comment{
		{ID: uuid.New(), MediaID: media.ID, Body: "first"},
		{ID: uuid.New(), MediaID: media.ID, Body: "second"},
	}

	handler := NewListCommentsHandler(
		&fakeUserRepo{user: user},
		&fakeMediaRepo{media: media},
		&fakeCommentRepo{comments: comments},
	)

	result, err := handler.Execute(context.Background(), ListCommentsQuery{
		UserID:  user.ID,
		MediaID: media.ID,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if len(result) != 2 || result[0].Body != "first" || result[1].Body != "second" {
		t.Fatalf("Execute() returned unexpected comments: %#v", result)
	}
}

func TestListCommentsHandlerExecuteRequiresVisibleMedia(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	media := &domain.Media{ID: uuid.New()}

	handler := NewListCommentsHandler(
		&fakeUserRepo{user: user},
		&fakeMediaRepo{media: media, err: domain.ErrNotFound},
		&fakeCommentRepo{},
	)

	if _, err := handler.Execute(context.Background(), ListCommentsQuery{
		UserID:  user.ID,
		MediaID: media.ID,
	}); err != domain.ErrNotFound {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrNotFound)
	}
}
