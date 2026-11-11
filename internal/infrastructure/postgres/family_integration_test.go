//go:build integration

package postgres

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/yourorg/mycloud/internal/domain"
	"testing"
)

func TestIntegrationFamilyFeedAuthorizationAndInvitations(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	owner := testUser(t, db, 1<<30, "member")
	member := testUser(t, db, 1<<30, "member")
	outsider := testUser(t, db, 1<<30, "admin")
	repo := NewFamilyRepository(db)
	family, err := repo.CreateFamily(ctx, owner, "Private family")
	if err != nil {
		t.Fatal(err)
	}
	item := testMedia(owner, 100)
	media := NewMediaRepository(db)
	if err = media.Create(ctx, item); err != nil {
		t.Fatal(err)
	}
	post, err := repo.CreatePost(ctx, owner, family.ID, "A moment", []uuid.UUID{item.ID})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = repo.ListPosts(ctx, outsider, family.ID, ""); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("outsider/admin read private feed")
	}
	if _, err = media.FindByIDForUser(ctx, item.ID, member); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("uninvited member read private asset")
	}
	if err = repo.CreateInvitation(ctx, outsider, family.ID, "x@invalid", "unauthorized"); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("outsider created family invitation")
	}
	email := member.String() + "@validation.invalid"
	hash := uuid.NewString()
	if err = repo.CreateInvitation(ctx, owner, family.ID, email, hash); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.AcceptInvitation(ctx, outsider, hash); !errors.Is(err, domain.ErrInvalidToken) {
		t.Fatal("wrong email accepted invitation")
	}
	if _, err = repo.AcceptInvitation(ctx, member, hash); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.AcceptInvitation(ctx, member, hash); !errors.Is(err, domain.ErrInvalidToken) {
		t.Fatal("invitation was replayed")
	}
	if _, err = media.FindByIDForUser(ctx, item.ID, member); err != nil {
		t.Fatal("authorized post media unavailable", err)
	}
	if _, err = repo.CreatePost(ctx, member, family.ID, "Stolen photo", []uuid.UUID{item.ID}); !errors.Is(err, domain.ErrForbidden) {
		t.Fatal("member re-shared another owner's original")
	}
	if err = repo.DeletePost(ctx, member, family.ID, post); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("member removed another author's post")
	}
	if err = repo.DeletePost(ctx, outsider, family.ID, post); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("admin removed private post")
	}
	page, err := repo.ListPosts(ctx, member, family.ID, "")
	if err != nil || len(page.Items) != 1 {
		t.Fatalf("feed=%v err=%v", page, err)
	}
	if err = repo.RemoveMember(ctx, owner, family.ID, member); err != nil {
		t.Fatal(err)
	}
	if _, err = media.FindByIDForUser(ctx, item.ID, member); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("removed member retained media access")
	}
	if err = repo.DeletePost(ctx, owner, family.ID, post); err != nil {
		t.Fatal(err)
	}
	if _, err = media.FindByIDForUser(ctx, item.ID, owner); err != nil {
		t.Fatal("unsharing deleted owner's original")
	}
}
func TestIntegrationAccountDeletionRetainsRetryableObjects(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	owner := testUser(t, db, 1<<30, "member")
	item := testMedia(owner, 500)
	media := NewMediaRepository(db)
	if err := media.Create(ctx, item); err != nil {
		t.Fatal(err)
	}
	userRepo := NewUserRepository(db)
	if err := userRepo.DeleteAccount(ctx, owner, "wrong-password"); !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatal("account deletion accepted wrong reauthentication")
	}
	if err := userRepo.DeleteAccount(ctx, owner, "not-a-login-hash"); err != nil {
		t.Fatal(err)
	}
	user, err := userRepo.FindByID(ctx, owner)
	if err != nil {
		t.Fatal(err)
	}
	if user.Active || user.PasswordHash != "" || user.DisplayName != "Deleted member" {
		t.Fatal("account identity was not removed")
	}
	if _, err := media.FindByIDForUser(ctx, item.ID, owner); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("deleted account retained media")
	}
	var count int
	if err = db.QueryRow(ctx, `SELECT count(*) FROM media_deletions WHERE media_id=$1`, item.ID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatal("object cleanup was not durably retained")
	}
	if err = media.DrainDeletions(ctx, &integrationCleaner{}); err != nil {
		t.Fatal(err)
	}
}
