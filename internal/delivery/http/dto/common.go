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
	TakenAt      *time.Time `json:"taken_at,omitempty"`
	UploadedAt   time.Time  `json:"uploaded_at"`
	ThumbURLs    ThumbURLs  `json:"thumb_urls"`
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

func stringPtr(value string) *string {
	if value == "" {
		return nil
	}

	return &value
}
