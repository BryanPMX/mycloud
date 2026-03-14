package media

import (
	"context"
	"testing"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeFavoriteRepo struct {
	created *domain.Favorite
	deleted struct {
		userID  uuid.UUID
		mediaID uuid.UUID
	}
	mediaIDs []uuid.UUID
}

func (r *fakeFavoriteRepo) Create(_ context.Context, favorite *domain.Favorite) error {
	copied := *favorite
	r.created = &copied
	return nil
}

func (r *fakeFavoriteRepo) Delete(_ context.Context, userID, mediaID uuid.UUID) error {
	r.deleted.userID = userID
	r.deleted.mediaID = mediaID
	return nil
}

func (r *fakeFavoriteRepo) ListMediaIDsByUser(context.Context, uuid.UUID, []uuid.UUID) ([]uuid.UUID, error) {
	return r.mediaIDs, nil
}

func TestFavoriteMediaHandlerExecuteCreatesFavoriteForVisibleMedia(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	media := &domain.Media{ID: uuid.New(), OwnerID: user.ID}
	favoriteRepo := &fakeFavoriteRepo{}

	handler := NewFavoriteMediaHandler(
		&fakeMediaUserRepo{user: user},
		&fakeMediaRepo{existing: media},
		favoriteRepo,
	)

	if err := handler.Execute(context.Background(), FavoriteMediaCommand{
		UserID:  user.ID,
		MediaID: media.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if favoriteRepo.created == nil {
		t.Fatal("Execute() did not persist the favorite")
	}
	if favoriteRepo.created.UserID != user.ID || favoriteRepo.created.MediaID != media.ID {
		t.Fatalf("Execute() persisted unexpected favorite: %#v", favoriteRepo.created)
	}
}

func TestUnfavoriteMediaHandlerExecuteDeletesFavoriteForVisibleMedia(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	media := &domain.Media{ID: uuid.New(), OwnerID: user.ID}
	favoriteRepo := &fakeFavoriteRepo{}

	handler := NewUnfavoriteMediaHandler(
		&fakeMediaUserRepo{user: user},
		&fakeMediaRepo{existing: media},
		favoriteRepo,
	)

	if err := handler.Execute(context.Background(), UnfavoriteMediaCommand{
		UserID:  user.ID,
		MediaID: media.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if favoriteRepo.deleted.userID != user.ID || favoriteRepo.deleted.mediaID != media.ID {
		t.Fatalf("Execute() deleted unexpected favorite: %#v", favoriteRepo.deleted)
	}
}
