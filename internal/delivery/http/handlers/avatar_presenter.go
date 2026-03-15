package handlers

import (
	"context"
	"strings"
	"time"

	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/domain"
)

type avatarPresenter struct {
	storage domain.AvatarAssetReader
	ttl     time.Duration
}

func newAvatarPresenter(storage domain.AvatarAssetReader, ttl time.Duration) *avatarPresenter {
	if ttl <= 0 {
		ttl = userquery.DefaultAvatarURLTTL
	}

	return &avatarPresenter{
		storage: storage,
		ttl:     ttl,
	}
}

func (p *avatarPresenter) url(ctx context.Context, avatarKey string) (*string, error) {
	key := strings.TrimSpace(avatarKey)
	if key == "" || p.storage == nil {
		return nil, nil
	}

	exists, err := p.storage.AvatarExists(ctx, key)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}

	url, err := p.storage.PresignAvatar(ctx, key, p.ttl)
	if err != nil {
		return nil, err
	}

	return &url, nil
}

func (p *avatarPresenter) userResponse(ctx context.Context, user *domain.User) (dto.UserResponse, error) {
	avatarURL, err := p.url(ctx, user.AvatarKey)
	if err != nil {
		return dto.UserResponse{}, err
	}

	return dto.UserResponse{
		ID:          user.ID.String(),
		Email:       user.Email,
		DisplayName: user.DisplayName,
		AvatarURL:   avatarURL,
		Role:        string(user.Role),
		StorageUsed: user.StorageUsed,
		QuotaBytes:  user.QuotaBytes,
		StoragePct:  user.StoragePercent(),
		CreatedAt:   user.CreatedAt,
		LastLoginAt: user.LastLoginAt,
	}, nil
}

func (p *avatarPresenter) avatarURLResponse(ctx context.Context, avatarKey string) (dto.AvatarURLResponse, error) {
	avatarURL, err := p.url(ctx, avatarKey)
	if err != nil {
		return dto.AvatarURLResponse{}, err
	}

	return dto.AvatarURLResponse{AvatarURL: avatarURL}, nil
}

func (p *avatarPresenter) directoryUserResponse(ctx context.Context, entry userquery.ListDirectoryEntry) (dto.DirectoryUserResponse, error) {
	return dto.DirectoryUserResponse{
		ID:          entry.ID.String(),
		DisplayName: entry.DisplayName,
		AvatarURL:   entry.AvatarURL,
	}, nil
}

func (p *avatarPresenter) adminUserResponse(ctx context.Context, user *domain.User) (dto.AdminUserResponse, error) {
	avatarURL, err := p.url(ctx, user.AvatarKey)
	if err != nil {
		return dto.AdminUserResponse{}, err
	}

	return dto.AdminUserResponse{
		ID:          user.ID.String(),
		Email:       user.Email,
		DisplayName: user.DisplayName,
		AvatarURL:   avatarURL,
		Role:        string(user.Role),
		StorageUsed: user.StorageUsed,
		QuotaBytes:  user.QuotaBytes,
		Active:      user.Active,
		CreatedAt:   user.CreatedAt,
		LastLoginAt: user.LastLoginAt,
	}, nil
}

func (p *avatarPresenter) shareResponse(ctx context.Context, share *domain.Share) (dto.ShareResponse, error) {
	var recipient *dto.ShareRecipientResponse
	if share.Recipient != nil {
		avatarURL, err := p.url(ctx, share.Recipient.AvatarKey)
		if err != nil {
			return dto.ShareResponse{}, err
		}

		recipient = &dto.ShareRecipientResponse{
			ID:          share.Recipient.ID.String(),
			DisplayName: share.Recipient.DisplayName,
			AvatarURL:   avatarURL,
		}
	}

	return dto.ShareResponse{
		ID:         share.ID.String(),
		AlbumID:    share.AlbumID.String(),
		SharedBy:   share.SharedBy.String(),
		SharedWith: share.SharedWith.String(),
		Recipient:  recipient,
		Permission: string(share.Permission),
		ExpiresAt:  share.ExpiresAt,
		CreatedAt:  share.CreatedAt,
	}, nil
}

func (p *avatarPresenter) commentResponse(ctx context.Context, comment *domain.Comment) (dto.CommentResponse, error) {
	avatarURL, err := p.url(ctx, comment.Author.AvatarKey)
	if err != nil {
		return dto.CommentResponse{}, err
	}

	return dto.CommentResponse{
		ID: comment.ID.String(),
		Author: dto.CommentAuthorResponse{
			ID:          comment.Author.ID.String(),
			DisplayName: comment.Author.DisplayName,
			AvatarURL:   avatarURL,
		},
		Body:      comment.Body,
		CreatedAt: comment.CreatedAt,
	}, nil
}
