package handlers

import (
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	usercmd "github.com/yourorg/mycloud/internal/application/commands/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
	"net/http"
	"net/mail"
	"strings"
)

type FamilyHandler struct{ repo domain.FamilyRepository }

func NewFamilyHandler(repo domain.FamilyRepository) *FamilyHandler { return &FamilyHandler{repo: repo} }
func familyParams(c *gin.Context) (uuid.UUID, uuid.UUID, error) {
	user, ok := middleware.UserIDFromContext(c)
	if !ok {
		return uuid.Nil, uuid.Nil, domain.ErrUnauthorized
	}
	family, err := uuid.Parse(c.Param("familyID"))
	if err != nil {
		return uuid.Nil, uuid.Nil, domain.ErrInvalidInput
	}
	return user, family, nil
}
func (h *FamilyHandler) List(c *gin.Context) {
	user, _ := middleware.UserIDFromContext(c)
	items, err := h.repo.ListFamilies(c.Request.Context(), user)
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(200, gin.H{"families": items})
}
func (h *FamilyHandler) Create(c *gin.Context) {
	var req struct {
		Name string `json:"name"`
	}
	if c.ShouldBindJSON(&req) != nil {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	user, _ := middleware.UserIDFromContext(c)
	family, err := h.repo.CreateFamily(c.Request.Context(), user, req.Name)
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(http.StatusCreated, family)
}
func (h *FamilyHandler) Members(c *gin.Context) {
	user, family, err := familyParams(c)
	if err != nil {
		writeError(c, err)
		return
	}
	items, err := h.repo.ListMembers(c.Request.Context(), user, family)
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(200, gin.H{"members": items})
}
func (h *FamilyHandler) Invite(c *gin.Context) {
	user, family, err := familyParams(c)
	if err != nil {
		writeError(c, err)
		return
	}
	var req struct {
		Email string `json:"email"`
	}
	if c.ShouldBindJSON(&req) != nil {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))
	parsed, err := mail.ParseAddress(email)
	if err != nil || parsed.Address != email || len(email) > 254 {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	token, err := pkgauth.GenerateInviteToken()
	if err != nil {
		writeError(c, err)
		return
	}
	if err = h.repo.CreateInvitation(c.Request.Context(), user, family, email, pkgauth.HashInviteToken(token)); err != nil {
		writeError(c, err)
		return
	}
	c.JSON(201, gin.H{"token": token, "expires_in_days": 7})
}
func (h *FamilyHandler) Accept(c *gin.Context) {
	var req struct {
		Token string `json:"token"`
	}
	if c.ShouldBindJSON(&req) != nil || len(req.Token) != 43 {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	user, _ := middleware.UserIDFromContext(c)
	family, err := h.repo.AcceptInvitation(c.Request.Context(), user, pkgauth.HashInviteToken(req.Token))
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(200, gin.H{"family_id": family})
}
func (h *FamilyHandler) RemoveMember(c *gin.Context) {
	user, family, err := familyParams(c)
	target, parseErr := uuid.Parse(c.Param("userID"))
	if err != nil || parseErr != nil {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	if err = h.repo.RemoveMember(c.Request.Context(), user, family, target); err != nil {
		writeError(c, err)
		return
	}
	c.Status(204)
}
func (h *FamilyHandler) Feed(c *gin.Context) {
	user, family, err := familyParams(c)
	if err != nil {
		writeError(c, err)
		return
	}
	page, err := h.repo.ListPosts(c.Request.Context(), user, family, c.Query("cursor"))
	if err != nil {
		writeError(c, err)
		return
	}
	items := make([]gin.H, 0, len(page.Items))
	for _, p := range page.Items {
		assets := make([]dto.MediaResponse, 0, len(p.Media))
		for _, asset := range p.Media {
			assets = append(assets, dto.ToMediaResponse(asset))
		}
		items = append(items, gin.H{"id": p.ID, "family_id": p.FamilyID, "author_id": p.AuthorID, "author_name": p.AuthorName, "caption": p.Caption, "created_at": p.CreatedAt, "media": assets})
	}
	c.JSON(200, gin.H{"posts": items, "next_cursor": page.NextCursor})
}
func (h *FamilyHandler) Post(c *gin.Context) {
	user, family, err := familyParams(c)
	if err != nil {
		writeError(c, err)
		return
	}
	var req struct {
		Caption  string      `json:"caption"`
		MediaIDs []uuid.UUID `json:"media_ids"`
	}
	if c.ShouldBindJSON(&req) != nil {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	id, err := h.repo.CreatePost(c.Request.Context(), user, family, req.Caption, req.MediaIDs)
	if err != nil {
		writeError(c, err)
		return
	}
	c.JSON(201, gin.H{"id": id})
}
func (h *FamilyHandler) Unshare(c *gin.Context) {
	user, family, err := familyParams(c)
	post, parseErr := uuid.Parse(c.Param("postID"))
	if err != nil || parseErr != nil {
		writeError(c, domain.ErrInvalidInput)
		return
	}
	if err = h.repo.DeletePost(c.Request.Context(), user, family, post); err != nil {
		writeError(c, err)
		return
	}
	c.Status(204)
}

func DeleteAccount(handler *usercmd.DeleteAccountHandler) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req struct {
			Password     string `json:"password"`
			Confirmation string `json:"confirmation"`
		}
		if c.ShouldBindJSON(&req) != nil || req.Confirmation != "DELETE" || len(req.Password) > 1024 {
			writeError(c, domain.ErrInvalidInput)
			return
		}
		user, _ := middleware.UserIDFromContext(c)
		if err := handler.Execute(c.Request.Context(), user, req.Password); err != nil {
			writeError(c, err)
			return
		}
		c.SetCookie("access_token", "", -1, "/", "", true, true)
		c.SetCookie("refresh_token", "", -1, "/api/v1/auth", "", true, true)
		c.Status(http.StatusAccepted)
	}
}
