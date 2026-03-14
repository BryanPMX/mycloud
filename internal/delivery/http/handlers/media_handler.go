package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	mediacmd "github.com/yourorg/mycloud/internal/application/commands/media"
	mediaquery "github.com/yourorg/mycloud/internal/application/queries/media"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type MediaHandler struct {
	favoriteHandler       *mediacmd.FavoriteMediaHandler
	unfavoriteHandler     *mediacmd.UnfavoriteMediaHandler
	listHandler           *mediaquery.ListMediaHandler
	initUploadHandler     *mediacmd.InitUploadHandler
	partURLHandler        *mediacmd.PresignUploadPartHandler
	completeUploadHandler *mediacmd.CompleteUploadHandler
}

func NewMediaHandler(
	listHandler *mediaquery.ListMediaHandler,
	favoriteHandler *mediacmd.FavoriteMediaHandler,
	unfavoriteHandler *mediacmd.UnfavoriteMediaHandler,
	initUploadHandler *mediacmd.InitUploadHandler,
	partURLHandler *mediacmd.PresignUploadPartHandler,
	completeUploadHandler *mediacmd.CompleteUploadHandler,
) *MediaHandler {
	return &MediaHandler{
		favoriteHandler:       favoriteHandler,
		unfavoriteHandler:     unfavoriteHandler,
		listHandler:           listHandler,
		initUploadHandler:     initUploadHandler,
		partURLHandler:        partURLHandler,
		completeUploadHandler: completeUploadHandler,
	}
}

func (h *MediaHandler) List(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
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

	favoritesOnly := false
	if raw := c.Query("favorites"); raw != "" {
		value, err := strconv.ParseBool(raw)
		if err != nil {
			writeError(c, errInvalidInput())
			return
		}
		favoritesOnly = value
	}

	page, err := h.listHandler.Execute(c.Request.Context(), mediaquery.ListMediaQuery{
		UserID:        userID,
		Cursor:        c.Query("cursor"),
		Limit:         limit,
		FavoritesOnly: favoritesOnly,
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

func (h *MediaHandler) Favorite(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	mediaID, err := parseMediaIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	if err := h.favoriteHandler.Execute(c.Request.Context(), mediacmd.FavoriteMediaCommand{
		UserID:  userID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *MediaHandler) Unfavorite(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	mediaID, err := parseMediaIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	if err := h.unfavoriteHandler.Execute(c.Request.Context(), mediacmd.UnfavoriteMediaCommand{
		UserID:  userID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *MediaHandler) InitUpload(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	var request struct {
		Filename  string `json:"filename"`
		MimeType  string `json:"mime_type"`
		SizeBytes int64  `json:"size_bytes"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.initUploadHandler.Execute(c.Request.Context(), mediacmd.InitUploadCommand{
		UserID:    userID,
		Filename:  request.Filename,
		MimeType:  request.MimeType,
		SizeBytes: request.SizeBytes,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusCreated, dto.UploadInitResponse{
		MediaID:       result.MediaID.String(),
		UploadID:      result.UploadID,
		Key:           result.Key,
		PartSizeBytes: result.PartSizeBytes,
		PartURLTTL:    result.PartURLTTL,
	})
}

func (h *MediaHandler) PresignPart(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	mediaID, err := parseMediaIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	var request struct {
		UploadID   string `json:"upload_id"`
		PartNumber int    `json:"part_number"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.partURLHandler.Execute(c.Request.Context(), mediacmd.PresignUploadPartCommand{
		UserID:     userID,
		MediaID:    mediaID,
		UploadID:   request.UploadID,
		PartNumber: request.PartNumber,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.UploadPartURLResponse{
		URL:       result.URL,
		ExpiresAt: result.ExpiresAt,
	})
}

func (h *MediaHandler) CompleteUpload(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	mediaID, err := parseMediaIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	var request struct {
		UploadID string `json:"upload_id"`
		Parts    []struct {
			PartNumber int    `json:"part_number"`
			ETag       string `json:"etag"`
		} `json:"parts"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	parts := make([]domain.CompletedPart, 0, len(request.Parts))
	for _, part := range request.Parts {
		parts = append(parts, domain.CompletedPart{
			PartNumber: part.PartNumber,
			ETag:       part.ETag,
		})
	}

	result, err := h.completeUploadHandler.Execute(c.Request.Context(), mediacmd.CompleteUploadCommand{
		UserID:   userID,
		MediaID:  mediaID,
		UploadID: request.UploadID,
		Parts:    parts,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToUploadCompleteResponse(result.Media))
}

func parseMediaIDParam(raw string) (uuid.UUID, error) {
	return uuid.Parse(raw)
}
