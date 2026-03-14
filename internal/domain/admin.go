package domain

import (
	"time"

	"github.com/google/uuid"
)

type InviteUserParams struct {
	Email           string
	DisplayName     string
	Role            UserRole
	QuotaBytes      int64
	PasswordHash    string
	InviteTokenHash string
	InviteExpiresAt time.Time
	CreatedAt       time.Time
}

type AcceptInviteParams struct {
	UserID          uuid.UUID
	InviteTokenHash string
	DisplayName     string
	PasswordHash    string
	AcceptedAt      time.Time
}

type AdminUpdateUserParams struct {
	UserID      uuid.UUID
	Role        *UserRole
	QuotaBytes  *int64
	Active      *bool
	ClearInvite bool
}

type SystemStats struct {
	Users   SystemUserStats
	Storage SystemStorageStats
	Media   SystemMediaStats
}

type SystemUserStats struct {
	Total  int64
	Active int64
}

type SystemStorageStats struct {
	TotalBytes int64
	UsedBytes  int64
	FreeBytes  int64
	PctUsed    float64
}

type SystemMediaStats struct {
	TotalItems  int64
	TotalImages int64
	TotalVideos int64
	PendingJobs int64
}
