package dto

import (
	"time"

	"github.com/yourorg/mycloud/internal/domain"
)

type UserResponse struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	DisplayName string     `json:"display_name"`
	Role        string     `json:"role"`
	StorageUsed int64      `json:"storage_used"`
	QuotaBytes  int64      `json:"quota_bytes"`
	StoragePct  float64    `json:"storage_pct"`
	CreatedAt   time.Time  `json:"created_at"`
	LastLoginAt *time.Time `json:"last_login_at,omitempty"`
}

type ThumbURLs struct {
	Small  *string `json:"small"`
	Medium *string `json:"medium"`
	Large  *string `json:"large"`
	Poster *string `json:"poster"`
}

type MediaResponse struct {
	ID           string     `json:"id"`
	OwnerID      string     `json:"owner_id"`
	Filename     string     `json:"filename"`
	MimeType     string     `json:"mime_type"`
	SizeBytes    int64      `json:"size_bytes"`
	Width        int        `json:"width"`
	Height       int        `json:"height"`
	DurationSecs float64    `json:"duration_secs"`
	Status       string     `json:"status"`
	IsFavorite   bool       `json:"is_favorite"`
	TakenAt      *time.Time `json:"taken_at,omitempty"`
	UploadedAt   time.Time  `json:"uploaded_at"`
	ThumbURLs    ThumbURLs  `json:"thumb_urls"`
}

type UploadInitResponse struct {
	MediaID       string `json:"media_id"`
	UploadID      string `json:"upload_id"`
	Key           string `json:"key"`
	PartSizeBytes int64  `json:"part_size_bytes"`
	PartURLTTL    int    `json:"part_url_ttl"`
}

type UploadPartURLResponse struct {
	URL       string    `json:"url"`
	ExpiresAt time.Time `json:"expires_at"`
}

type UploadCompleteResponse struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	Filename  string `json:"filename"`
	SizeBytes int64  `json:"size_bytes"`
}

type AlbumResponse struct {
	ID           string    `json:"id"`
	OwnerID      string    `json:"owner_id"`
	Name         string    `json:"name"`
	Description  string    `json:"description"`
	CoverMediaID *string   `json:"cover_media_id"`
	MediaCount   int       `json:"media_count"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type ShareRecipientResponse struct {
	ID          string  `json:"id"`
	DisplayName string  `json:"display_name"`
	AvatarURL   *string `json:"avatar_url"`
}

type ShareResponse struct {
	ID         string                  `json:"id"`
	AlbumID    string                  `json:"album_id"`
	SharedBy   string                  `json:"shared_by"`
	SharedWith string                  `json:"shared_with"`
	Recipient  *ShareRecipientResponse `json:"recipient,omitempty"`
	Permission string                  `json:"permission"`
	ExpiresAt  *time.Time              `json:"expires_at,omitempty"`
	CreatedAt  time.Time               `json:"created_at"`
}

type CommentAuthorResponse struct {
	ID          string  `json:"id"`
	DisplayName string  `json:"display_name"`
	AvatarURL   *string `json:"avatar_url"`
}

type CommentResponse struct {
	ID        string                `json:"id"`
	Author    CommentAuthorResponse `json:"author"`
	Body      string                `json:"body"`
	CreatedAt time.Time             `json:"created_at"`
}

func ToUserResponse(user *domain.User) UserResponse {
	return UserResponse{
		ID:          user.ID.String(),
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Role:        string(user.Role),
		StorageUsed: user.StorageUsed,
		QuotaBytes:  user.QuotaBytes,
		StoragePct:  user.StoragePercent(),
		CreatedAt:   user.CreatedAt,
		LastLoginAt: user.LastLoginAt,
	}
}

func ToMediaResponse(media *domain.Media) MediaResponse {
	return MediaResponse{
		ID:           media.ID.String(),
		OwnerID:      media.OwnerID.String(),
		Filename:     media.Filename,
		MimeType:     media.MimeType,
		SizeBytes:    media.SizeBytes,
		Width:        media.Width,
		Height:       media.Height,
		DurationSecs: media.DurationSecs,
		Status:       string(media.Status),
		IsFavorite:   media.IsFavorite,
		TakenAt:      media.TakenAt,
		UploadedAt:   media.UploadedAt,
		ThumbURLs: ThumbURLs{
			Small:  stringPtr(media.ThumbKeys.Small),
			Medium: stringPtr(media.ThumbKeys.Medium),
			Large:  stringPtr(media.ThumbKeys.Large),
			Poster: stringPtr(media.ThumbKeys.Poster),
		},
	}
}

func ToUploadCompleteResponse(media *domain.Media) UploadCompleteResponse {
	return UploadCompleteResponse{
		ID:        media.ID.String(),
		Status:    string(media.Status),
		Filename:  media.Filename,
		SizeBytes: media.SizeBytes,
	}
}

func ToAlbumResponse(album *domain.Album) AlbumResponse {
	var coverMediaID *string
	if album.CoverMediaID != nil {
		value := album.CoverMediaID.String()
		coverMediaID = &value
	}

	return AlbumResponse{
		ID:           album.ID.String(),
		OwnerID:      album.OwnerID.String(),
		Name:         album.Name,
		Description:  album.Description,
		CoverMediaID: coverMediaID,
		MediaCount:   album.MediaCount,
		CreatedAt:    album.CreatedAt,
		UpdatedAt:    album.UpdatedAt,
	}
}

func ToShareResponse(share *domain.Share) ShareResponse {
	var recipient *ShareRecipientResponse
	if share.Recipient != nil {
		recipient = &ShareRecipientResponse{
			ID:          share.Recipient.ID.String(),
			DisplayName: share.Recipient.DisplayName,
			AvatarURL:   stringPtr(share.Recipient.AvatarKey),
		}
	}

	return ShareResponse{
		ID:         share.ID.String(),
		AlbumID:    share.AlbumID.String(),
		SharedBy:   share.SharedBy.String(),
		SharedWith: share.SharedWith.String(),
		Recipient:  recipient,
		Permission: string(share.Permission),
		ExpiresAt:  share.ExpiresAt,
		CreatedAt:  share.CreatedAt,
	}
}

func ToCommentResponse(comment *domain.Comment) CommentResponse {
	return CommentResponse{
		ID: comment.ID.String(),
		Author: CommentAuthorResponse{
			ID:          comment.Author.ID.String(),
			DisplayName: comment.Author.DisplayName,
			AvatarURL:   stringPtr(comment.Author.AvatarKey),
		},
		Body:      comment.Body,
		CreatedAt: comment.CreatedAt,
	}
}

func stringPtr(value string) *string {
	if value == "" {
		return nil
	}

	return &value
}
