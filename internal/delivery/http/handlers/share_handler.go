package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	sharecmd "github.com/yourorg/mycloud/internal/application/commands/shares"
	sharequery "github.com/yourorg/mycloud/internal/application/queries/shares"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type ShareHandler struct {
	listHandler   *sharequery.ListSharesHandler
	createHandler *sharecmd.CreateShareHandler
	deleteHandler *sharecmd.RevokeShareHandler
	avatars       *avatarPresenter
}

func NewShareHandler(
	listHandler *sharequery.ListSharesHandler,
	createHandler *sharecmd.CreateShareHandler,
	deleteHandler *sharecmd.RevokeShareHandler,
	avatarStorage domain.AvatarAssetReader,
) *ShareHandler {
	return &ShareHandler{
		listHandler:   listHandler,
		createHandler: createHandler,
		deleteHandler: deleteHandler,
		avatars:       newAvatarPresenter(avatarStorage, userquery.DefaultAvatarURLTTL),
	}
}

func (h *ShareHandler) List(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	albumID, err := parseAlbumIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	shares, err := h.listHandler.Execute(c.Request.Context(), sharequery.ListSharesQuery{
		UserID:  userID,
		AlbumID: albumID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	items := make([]dto.ShareResponse, 0, len(shares))
	for _, share := range shares {
		response, err := h.avatars.shareResponse(c.Request.Context(), share)
		if err != nil {
			writeError(c, err)
			return
		}
		items = append(items, response)
	}

	c.JSON(http.StatusOK, gin.H{"shares": items})
}

func (h *ShareHandler) Create(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	albumID, err := parseAlbumIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	var request struct {
		SharedWith *string    `json:"shared_with"`
		Permission string     `json:"permission"`
		ExpiresAt  *time.Time `json:"expires_at"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	var sharedWithID *uuid.UUID
	if request.SharedWith != nil && *request.SharedWith != "" {
		value, err := uuid.Parse(*request.SharedWith)
		if err != nil {
			writeError(c, errInvalidInput())
			return
		}
		sharedWithID = &value
	}

	share, err := h.createHandler.Execute(c.Request.Context(), sharecmd.CreateShareCommand{
		UserID:     userID,
		AlbumID:    albumID,
		SharedWith: sharedWithID,
		Permission: request.Permission,
		ExpiresAt:  request.ExpiresAt,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	response, err := h.avatars.shareResponse(c.Request.Context(), share)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusCreated, response)
}

func (h *ShareHandler) Delete(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	albumID, err := parseAlbumIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	shareID, err := uuid.Parse(c.Param("shareId"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	if err := h.deleteHandler.Execute(c.Request.Context(), sharecmd.RevokeShareCommand{
		UserID:  userID,
		AlbumID: albumID,
		ShareID: shareID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}
