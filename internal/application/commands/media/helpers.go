package media

import (
	"context"
	"sort"
	"strings"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

func requireActiveUser(ctx context.Context, userRepo domain.UserRepository, userID uuid.UUID) (*domain.User, error) {
	user, err := userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	return user, nil
}

func normalizeCompletedParts(parts []domain.CompletedPart) ([]domain.CompletedPart, error) {
	if len(parts) == 0 {
		return nil, domain.ErrInvalidInput
	}

	normalized := make([]domain.CompletedPart, len(parts))
	copy(normalized, parts)
	sort.Slice(normalized, func(i, j int) bool {
		return normalized[i].PartNumber < normalized[j].PartNumber
	})

	lastPartNumber := 0
	for _, part := range normalized {
		if part.PartNumber <= 0 || strings.TrimSpace(part.ETag) == "" {
			return nil, domain.ErrInvalidInput
		}
		if part.PartNumber == lastPartNumber {
			return nil, domain.ErrInvalidInput
		}

		lastPartNumber = part.PartNumber
	}

	return normalized, nil
}

func loadOwnedOrAdminMedia(
	ctx context.Context,
	repo domain.MediaTrashRepository,
	user *domain.User,
	mediaID uuid.UUID,
) (*domain.Media, error) {
	if user.IsAdmin() {
		return repo.FindByIDIncludingDeleted(ctx, mediaID)
	}

	return repo.FindOwnedByUserIncludingDeleted(ctx, mediaID, user.ID)
}
