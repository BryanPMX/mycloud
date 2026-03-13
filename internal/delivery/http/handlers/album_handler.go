package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	albumcmd "github.com/yourorg/mycloud/internal/application/commands/albums"
	albumquery "github.com/yourorg/mycloud/internal/application/queries/albums"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type AlbumHandler struct {
	getHandler         *albumquery.GetAlbumHandler
	listHandler        *albumquery.ListAlbumsHandler
	listMediaHandler   *albumquery.ListAlbumMediaHandler
	createHandler      *albumcmd.CreateAlbumHandler
	updateHandler      *albumcmd.UpdateAlbumHandler
	deleteHandler      *albumcmd.DeleteAlbumHandler
	addMediaHandler    *albumcmd.AddMediaHandler
	removeMediaHandler *albumcmd.RemoveMediaHandler
}

func NewAlbumHandler(
	getHandler *albumquery.GetAlbumHandler,
	listHandler *albumquery.ListAlbumsHandler,
	listMediaHandler *albumquery.ListAlbumMediaHandler,
	createHandler *albumcmd.CreateAlbumHandler,
	updateHandler *albumcmd.UpdateAlbumHandler,
	deleteHandler *albumcmd.DeleteAlbumHandler,
	addMediaHandler *albumcmd.AddMediaHandler,
	removeMediaHandler *albumcmd.RemoveMediaHandler,
) *AlbumHandler {
	return &AlbumHandler{
		getHandler:         getHandler,
		listHandler:        listHandler,
		listMediaHandler:   listMediaHandler,
		createHandler:      createHandler,
		updateHandler:      updateHandler,
		deleteHandler:      deleteHandler,
		addMediaHandler:    addMediaHandler,
		removeMediaHandler: removeMediaHandler,
	}
}

func (h *AlbumHandler) Get(c *gin.Context) {
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

	album, err := h.getHandler.Execute(c.Request.Context(), albumquery.GetAlbumQuery{
		UserID:  userID,
		AlbumID: albumID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToAlbumResponse(album))
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

func (h *AlbumHandler) Update(c *gin.Context) {
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

	var fields map[string]json.RawMessage
	if err := httpx.BindJSON(c, &fields); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	command := albumcmd.UpdateAlbumCommand{
		UserID:  userID,
		AlbumID: albumID,
	}
	if err := populateAlbumUpdateCommand(fields, &command); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	album, err := h.updateHandler.Execute(c.Request.Context(), command)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToAlbumResponse(album))
}

func (h *AlbumHandler) Delete(c *gin.Context) {
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

	if err := h.deleteHandler.Execute(c.Request.Context(), albumcmd.DeleteAlbumCommand{
		UserID:  userID,
		AlbumID: albumID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *AlbumHandler) ListMedia(c *gin.Context) {
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

	limit := 50
	if raw := c.Query("limit"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil {
			writeError(c, errInvalidInput())
			return
		}
		limit = value
	}

	page, err := h.listMediaHandler.Execute(c.Request.Context(), albumquery.ListAlbumMediaQuery{
		UserID:  userID,
		AlbumID: albumID,
		Cursor:  c.Query("cursor"),
		Limit:   limit,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	items := make([]dto.MediaResponse, 0, len(page.Items))
	for _, item := range page.Items {
		items = append(items, dto.ToMediaResponse(item))
	}

	c.JSON(http.StatusOK, gin.H{
		"items":       items,
		"next_cursor": page.NextCursor,
		"total":       page.Total,
	})
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

func populateAlbumUpdateCommand(fields map[string]json.RawMessage, command *albumcmd.UpdateAlbumCommand) error {
	for key, raw := range fields {
		switch key {
		case "name":
			var name string
			if err := json.Unmarshal(raw, &name); err != nil {
				return err
			}
			command.Name = &name
		case "description":
			var description string
			if err := json.Unmarshal(raw, &description); err != nil {
				return err
			}
			command.Description = &description
		case "cover_media_id":
			command.CoverMediaSet = true
			if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
				command.CoverMediaID = nil
				continue
			}

			var coverMediaID string
			if err := json.Unmarshal(raw, &coverMediaID); err != nil {
				return err
			}

			parsedID, err := uuid.Parse(coverMediaID)
			if err != nil {
				return err
			}
			command.CoverMediaID = &parsedID
		default:
			return errInvalidInput()
		}
	}

	return nil
}
