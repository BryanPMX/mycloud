package albums

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type CreateAlbumCommand struct {
	UserID      uuid.UUID
	Name        string
	Description string
}

type CreateAlbumHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
}

func NewCreateAlbumHandler(userRepo domain.UserRepository, albumRepo domain.AlbumRepository) *CreateAlbumHandler {
	return &CreateAlbumHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
	}
}

func (h *CreateAlbumHandler) Execute(ctx context.Context, command CreateAlbumCommand) (*domain.Album, error) {
	name := strings.TrimSpace(command.Name)
	description := strings.TrimSpace(command.Description)
	if name == "" {
		return nil, domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	album := &domain.Album{
		ID:          uuid.New(),
		OwnerID:     user.ID,
		Name:        name,
		Description: description,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := h.albumRepo.Create(ctx, album); err != nil {
		return nil, err
	}

	return album, nil
}
