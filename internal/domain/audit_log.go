package domain

import (
	"net/netip"
	"time"

	"github.com/google/uuid"
)

// AuditLog records sensitive actions for operator visibility and compliance.
type AuditLog struct {
	ID        int64
	ActorID   *uuid.UUID
	Action    string
	TargetID  *uuid.UUID
	Meta      map[string]any
	IPAddress *netip.Addr
	CreatedAt time.Time
}

const (
	AuditActionAdminInviteUser    = "admin.user.invite"
	AuditActionAdminUpdateUser    = "admin.user.update"
	AuditActionAdminDeactivate    = "admin.user.deactivate"
	AuditActionAuthInviteAccepted = "auth.invite.accept"
)
