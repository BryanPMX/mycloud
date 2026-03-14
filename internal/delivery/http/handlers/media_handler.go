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
	getHandler             *mediaquery.GetMediaHandler
	listHandler            *mediaquery.ListMediaHandler
	searchHandler          *mediaquery.SearchMediaHandler
	listTrashHandler       *mediaquery.ListTrashHandler
	getDownloadURLHandler  *mediaquery.GetMediaDownloadURLHandler
	getThumbURLHandler     *mediaquery.GetMediaThumbURLHandler
	favoriteHandler        *mediacmd.FavoriteMediaHandler
	unfavoriteHandler      *mediacmd.UnfavoriteMediaHandler
	initUploadHandler      *mediacmd.InitUploadHandler
	partURLHandler         *mediacmd.PresignUploadPartHandler
	completeUploadHandler  *mediacmd.CompleteUploadHandler
	abortUploadHandler     *mediacmd.AbortUploadHandler
	deleteHandler          *mediacmd.DeleteMediaHandler
	restoreHandler         *mediacmd.RestoreMediaHandler
	permanentDeleteHandler *mediacmd.PermanentDeleteMediaHandler
	emptyTrashHandler      *mediacmd.EmptyTrashHandler
}

func NewMediaHandler(
	getHandler *mediaquery.GetMediaHandler,
	listHandler *mediaquery.ListMediaHandler,
	searchHandler *mediaquery.SearchMediaHandler,
	listTrashHandler *mediaquery.ListTrashHandler,
	getDownloadURLHandler *mediaquery.GetMediaDownloadURLHandler,
	getThumbURLHandler *mediaquery.GetMediaThumbURLHandler,
	favoriteHandler *mediacmd.FavoriteMediaHandler,
	unfavoriteHandler *mediacmd.UnfavoriteMediaHandler,
	initUploadHandler *mediacmd.InitUploadHandler,
	partURLHandler *mediacmd.PresignUploadPartHandler,
	completeUploadHandler *mediacmd.CompleteUploadHandler,
	abortUploadHandler *mediacmd.AbortUploadHandler,
	deleteHandler *mediacmd.DeleteMediaHandler,
	restoreHandler *mediacmd.RestoreMediaHandler,
	permanentDeleteHandler *mediacmd.PermanentDeleteMediaHandler,
	emptyTrashHandler *mediacmd.EmptyTrashHandler,
) *MediaHandler {
	return &MediaHandler{
		getHandler:             getHandler,
		listHandler:            listHandler,
		searchHandler:          searchHandler,
		listTrashHandler:       listTrashHandler,
		getDownloadURLHandler:  getDownloadURLHandler,
		getThumbURLHandler:     getThumbURLHandler,
		favoriteHandler:        favoriteHandler,
		unfavoriteHandler:      unfavoriteHandler,
		initUploadHandler:      initUploadHandler,
		partURLHandler:         partURLHandler,
		completeUploadHandler:  completeUploadHandler,
		abortUploadHandler:     abortUploadHandler,
		deleteHandler:          deleteHandler,
		restoreHandler:         restoreHandler,
		permanentDeleteHandler: permanentDeleteHandler,
		emptyTrashHandler:      emptyTrashHandler,
	}
}

func (h *MediaHandler) Get(c *gin.Context) {
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

	result, err := h.getHandler.Execute(c.Request.Context(), mediaquery.GetMediaQuery{
		UserID:  userID,
		MediaID: mediaID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToMediaResponse(result.Media))
}

func (h *MediaHandler) List(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	favoritesOnly, err := parseBoolQuery(c, "favorites")
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}
	limit, err := parseLimitQuery(c)
	if err != nil {
		writeError(c, errInvalidInput())
		return
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

	c.JSON(http.StatusOK, mediaPageResponse(page))
}

func (h *MediaHandler) Search(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}
	limit, err := parseLimitQuery(c)
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	page, err := h.searchHandler.Execute(c.Request.Context(), mediaquery.SearchMediaQuery{
		UserID: userID,
		Query:  c.Query("q"),
		Cursor: c.Query("cursor"),
		Limit:  limit,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, mediaPageResponse(page))
}

func (h *MediaHandler) ListTrash(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}
	limit, err := parseLimitQuery(c)
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	page, err := h.listTrashHandler.Execute(c.Request.Context(), mediaquery.ListTrashQuery{
		UserID: userID,
		Cursor: c.Query("cursor"),
		Limit:  limit,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, mediaPageResponse(page))
}

func (h *MediaHandler) GetDownloadURL(c *gin.Context) {
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

	ttlSeconds, err := parseIntQuery(c, "ttl")
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.getDownloadURLHandler.Execute(c.Request.Context(), mediaquery.GetMediaDownloadURLQuery{
		UserID:     userID,
		MediaID:    mediaID,
		TTLSeconds: ttlSeconds,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.AssetURLResponse{
		URL:       result.URL,
		ExpiresAt: result.ExpiresAt,
	})
}

func (h *MediaHandler) GetThumbURL(c *gin.Context) {
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

	ttlSeconds, err := parseIntQuery(c, "ttl")
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.getThumbURLHandler.Execute(c.Request.Context(), mediaquery.GetMediaThumbURLQuery{
		UserID:     userID,
		MediaID:    mediaID,
		Size:       c.Query("size"),
		TTLSeconds: ttlSeconds,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.AssetURLResponse{
		URL:       result.URL,
		ExpiresAt: result.ExpiresAt,
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

func (h *MediaHandler) AbortUpload(c *gin.Context) {
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

	if err := h.abortUploadHandler.Execute(c.Request.Context(), mediacmd.AbortUploadCommand{
		UserID:  userID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *MediaHandler) Delete(c *gin.Context) {
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

	if err := h.deleteHandler.Execute(c.Request.Context(), mediacmd.DeleteMediaCommand{
		UserID:  userID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *MediaHandler) Restore(c *gin.Context) {
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

	if err := h.restoreHandler.Execute(c.Request.Context(), mediacmd.RestoreMediaCommand{
		UserID:  userID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *MediaHandler) PermanentDelete(c *gin.Context) {
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

	if err := h.permanentDeleteHandler.Execute(c.Request.Context(), mediacmd.PermanentDeleteMediaCommand{
		UserID:  userID,
		MediaID: mediaID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *MediaHandler) EmptyTrash(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	if err := h.emptyTrashHandler.Execute(c.Request.Context(), mediacmd.EmptyTrashCommand{
		UserID: userID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func mediaPageResponse(page domain.MediaPage) gin.H {
	items := make([]dto.MediaResponse, 0, len(page.Items))
	for _, item := range page.Items {
		items = append(items, dto.ToMediaResponse(item))
	}

	return gin.H{
		"items":       items,
		"next_cursor": page.NextCursor,
		"total":       page.Total,
	}
}

func parseMediaIDParam(raw string) (uuid.UUID, error) {
	return uuid.Parse(raw)
}

func parseLimitQuery(c *gin.Context) (int, error) {
	value, err := parseIntQuery(c, "limit")
	if err != nil {
		return 0, err
	}
	if value == 0 {
		return 50, nil
	}
	if value < 0 {
		return 0, domain.ErrInvalidInput
	}

	return value, nil
}

func parseIntQuery(c *gin.Context, name string) (int, error) {
	raw := c.Query(name)
	if raw == "" {
		return 0, nil
	}

	return strconv.Atoi(raw)
}

func parseBoolQuery(c *gin.Context, name string) (bool, error) {
	raw := c.Query(name)
	if raw == "" {
		return false, nil
	}

	return strconv.ParseBool(raw)
}
