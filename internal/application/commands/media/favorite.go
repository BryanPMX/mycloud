package media

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type FavoriteMediaCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type FavoriteMediaHandler struct {
	userRepo     domain.UserRepository
	mediaRepo    domain.MediaRepository
	favoriteRepo domain.FavoriteRepository
}

func NewFavoriteMediaHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaRepository,
	favoriteRepo domain.FavoriteRepository,
) *FavoriteMediaHandler {
	return &FavoriteMediaHandler{
		userRepo:     userRepo,
		mediaRepo:    mediaRepo,
		favoriteRepo: favoriteRepo,
	}
}

func (h *FavoriteMediaHandler) Execute(ctx context.Context, command FavoriteMediaCommand) error {
	if command.MediaID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return err
	}
	if _, err := h.mediaRepo.FindByIDForUser(ctx, command.MediaID, user.ID); err != nil {
		return err
	}

	return h.favoriteRepo.Create(ctx, &domain.Favorite{
		UserID:    user.ID,
		MediaID:   command.MediaID,
		CreatedAt: time.Now().UTC(),
	})
}

type UnfavoriteMediaCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type UnfavoriteMediaHandler struct {
	userRepo     domain.UserRepository
	mediaRepo    domain.MediaRepository
	favoriteRepo domain.FavoriteRepository
}

func NewUnfavoriteMediaHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaRepository,
	favoriteRepo domain.FavoriteRepository,
) *UnfavoriteMediaHandler {
	return &UnfavoriteMediaHandler{
		userRepo:     userRepo,
		mediaRepo:    mediaRepo,
		favoriteRepo: favoriteRepo,
	}
}

func (h *UnfavoriteMediaHandler) Execute(ctx context.Context, command UnfavoriteMediaCommand) error {
	if command.MediaID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return err
	}
	if _, err := h.mediaRepo.FindByIDForUser(ctx, command.MediaID, user.ID); err != nil {
		return err
	}

	return h.favoriteRepo.Delete(ctx, user.ID, command.MediaID)
}
