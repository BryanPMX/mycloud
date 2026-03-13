package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	albumcmd "github.com/yourorg/mycloud/internal/application/commands/albums"
	albumquery "github.com/yourorg/mycloud/internal/application/queries/albums"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type AlbumHandler struct {
	listHandler        *albumquery.ListAlbumsHandler
	createHandler      *albumcmd.CreateAlbumHandler
	addMediaHandler    *albumcmd.AddMediaHandler
	removeMediaHandler *albumcmd.RemoveMediaHandler
}

func NewAlbumHandler(
	listHandler *albumquery.ListAlbumsHandler,
	createHandler *albumcmd.CreateAlbumHandler,
	addMediaHandler *albumcmd.AddMediaHandler,
	removeMediaHandler *albumcmd.RemoveMediaHandler,
) *AlbumHandler {
	return &AlbumHandler{
		listHandler:        listHandler,
		createHandler:      createHandler,
		addMediaHandler:    addMediaHandler,
		removeMediaHandler: removeMediaHandler,
	}
}

func (h *AlbumHandler) List(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	result, err := h.listHandler.Execute(c.Request.Context(), albumquery.ListAlbumsQuery{
		UserID: userID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	owned := make([]dto.AlbumResponse, 0, len(result.Owned))
	for _, album := range result.Owned {
		owned = append(owned, dto.ToAlbumResponse(album))
	}

	shared := make([]dto.AlbumResponse, 0, len(result.SharedWithMe))
	for _, album := range result.SharedWithMe {
		shared = append(shared, dto.ToAlbumResponse(album))
	}

	c.JSON(http.StatusOK, gin.H{
		"owned":          owned,
		"shared_with_me": shared,
	})
}

func (h *AlbumHandler) Create(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	var request struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	album, err := h.createHandler.Execute(c.Request.Context(), albumcmd.CreateAlbumCommand{
		UserID:      userID,
		Name:        request.Name,
		Description: request.Description,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusCreated, dto.ToAlbumResponse(album))
}

func (h *AlbumHandler) AddMedia(c *gin.Context) {
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
		MediaIDs []string `json:"media_ids"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	mediaIDs := make([]uuid.UUID, 0, len(request.MediaIDs))
	for _, rawID := range request.MediaIDs {
		mediaID, err := uuid.Parse(rawID)
		if err != nil {
			writeError(c, errInvalidInput())
			return
		}
		mediaIDs = append(mediaIDs, mediaID)
	}

	result, err := h.addMediaHandler.Execute(c.Request.Context(), albumcmd.AddMediaCommand{
		UserID:   userID,
		AlbumID:  albumID,
		MediaIDs: mediaIDs,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"added":            result.Added,
		"already_in_album": result.AlreadyInAlbum,
	})
}

func (h *AlbumHandler) RemoveMedia(c *gin.Context) {
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

	mediaID, err := parseMediaIDParam(c.Param("mediaId"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	if err := h.removeMediaHandler.Execute(c.Request.Context(), albumcmd.RemoveMediaCommand{
		UserID:  userID,
		AlbumID: albumID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func parseAlbumIDParam(raw string) (uuid.UUID, error) {
	return uuid.Parse(raw)
}
