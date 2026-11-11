package domain

import (
	"context"
	"github.com/google/uuid"
	"time"
)

type Family struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	OwnerID   uuid.UUID `json:"owner_id"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}
type FamilyMember struct {
	UserID      uuid.UUID `json:"user_id"`
	DisplayName string    `json:"display_name"`
	Role        string    `json:"role"`
}
type Post struct {
	ID         uuid.UUID `json:"id"`
	FamilyID   uuid.UUID `json:"family_id"`
	AuthorID   uuid.UUID `json:"author_id"`
	AuthorName string    `json:"author_name"`
	Caption    string    `json:"caption"`
	CreatedAt  time.Time `json:"created_at"`
	Media      []*Media  `json:"-"`
}
type PostPage struct {
	Items      []*Post
	NextCursor string
}
type FamilyRepository interface {
	ListFamilies(context.Context, uuid.UUID) ([]Family, error)
	CreateFamily(context.Context, uuid.UUID, string) (*Family, error)
	ListMembers(context.Context, uuid.UUID, uuid.UUID) ([]FamilyMember, error)
	CreateInvitation(context.Context, uuid.UUID, uuid.UUID, string, string) error
	AcceptInvitation(context.Context, uuid.UUID, string) (uuid.UUID, error)
	RemoveMember(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) error
	ListPosts(context.Context, uuid.UUID, uuid.UUID, string) (PostPage, error)
	CreatePost(context.Context, uuid.UUID, uuid.UUID, string, []uuid.UUID) (uuid.UUID, error)
	DeletePost(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) error
}
