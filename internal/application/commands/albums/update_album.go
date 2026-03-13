package albums

import (
	"context"
	"strings"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type UpdateAlbumCommand struct {
	UserID        uuid.UUID
	AlbumID       uuid.UUID
	Name          *string
	Description   *string
	CoverMediaID  *uuid.UUID
	CoverMediaSet bool
}

type UpdateAlbumHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
}

func NewUpdateAlbumHandler(userRepo domain.UserRepository, albumRepo domain.AlbumRepository) *UpdateAlbumHandler {
	return &UpdateAlbumHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
	}
}

func (h *UpdateAlbumHandler) Execute(ctx context.Context, command UpdateAlbumCommand) (*domain.Album, error) {
	if command.AlbumID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}
	if command.Name == nil && command.Description == nil && !command.CoverMediaSet {
		return nil, domain.ErrInvalidInput
	}

	_, album, err := requireManageableAlbum(ctx, h.userRepo, h.albumRepo, command.UserID, command.AlbumID)
	if err != nil {
		return nil, err
	}

	if command.Name != nil {
		name := strings.TrimSpace(*command.Name)
		if name == "" {
			return nil, domain.ErrInvalidInput
		}
		album.Name = name
	}

	if command.Description != nil {
		album.Description = strings.TrimSpace(*command.Description)
	}

	if command.CoverMediaSet {
		if command.CoverMediaID == nil {
			album.CoverMediaID = nil
		} else {
			hasMedia, err := h.albumRepo.HasMedia(ctx, album.ID, *command.CoverMediaID)
			if err != nil {
				return nil, err
			}
			if !hasMedia {
				return nil, domain.ErrInvalidInput
			}

			coverMediaID := *command.CoverMediaID
			album.CoverMediaID = &coverMediaID
		}
	}

	if err := h.albumRepo.Update(ctx, album); err != nil {
		return nil, err
	}

	return album, nil
}
