package domain

import (
	"time"

	"github.com/google/uuid"
)

type UserRole string

const (
	RoleMember UserRole = "member"
	RoleAdmin  UserRole = "admin"
)

// User is the core account entity.
type User struct {
	ID           uuid.UUID
	Email        string
	DisplayName  string
	AvatarKey    string
	Role         UserRole
	PasswordHash string
	StorageUsed  int64
	QuotaBytes   int64
	Active       bool
	InviteToken  string
	InviteExpiry *time.Time
	CreatedAt    time.Time
	UpdatedAt    time.Time
	LastLoginAt  *time.Time
}

func (u User) IsAdmin() bool {
	return u.Role == RoleAdmin
}

func (u User) HasQuotaFor(bytes int64) bool {
	return u.StorageUsed+bytes <= u.QuotaBytes
}

func (u User) StoragePercent() float64 {
	if u.QuotaBytes == 0 {
		return 0
	}

	return float64(u.StorageUsed) / float64(u.QuotaBytes) * 100
}
