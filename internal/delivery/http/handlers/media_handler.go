package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	mediaquery "github.com/yourorg/mycloud/internal/application/queries/media"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
)

type MediaHandler struct {
	listHandler *mediaquery.ListMediaHandler
}

func NewMediaHandler(listHandler *mediaquery.ListMediaHandler) *MediaHandler {
	return &MediaHandler{listHandler: listHandler}
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

	page, err := h.listHandler.Execute(c.Request.Context(), mediaquery.ListMediaQuery{
		UserID: userID,
		Cursor: c.Query("cursor"),
		Limit:  limit,
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
