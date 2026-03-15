package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	commentcmd "github.com/yourorg/mycloud/internal/application/commands/comments"
	commentquery "github.com/yourorg/mycloud/internal/application/queries/comments"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type CommentHandler struct {
	listHandler   *commentquery.ListCommentsHandler
	addHandler    *commentcmd.AddCommentHandler
	deleteHandler *commentcmd.DeleteCommentHandler
	avatars       *avatarPresenter
}

func NewCommentHandler(
	listHandler *commentquery.ListCommentsHandler,
	addHandler *commentcmd.AddCommentHandler,
	deleteHandler *commentcmd.DeleteCommentHandler,
	avatarStorage domain.AvatarAssetReader,
) *CommentHandler {
	return &CommentHandler{
		listHandler:   listHandler,
		addHandler:    addHandler,
		deleteHandler: deleteHandler,
		avatars:       newAvatarPresenter(avatarStorage, userquery.DefaultAvatarURLTTL),
	}
}

func (h *CommentHandler) List(c *gin.Context) {
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

	comments, err := h.listHandler.Execute(c.Request.Context(), commentquery.ListCommentsQuery{
		UserID:  userID,
		MediaID: mediaID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	items := make([]dto.CommentResponse, 0, len(comments))
	for _, comment := range comments {
		response, err := h.avatars.commentResponse(c.Request.Context(), comment)
		if err != nil {
			writeError(c, err)
			return
		}
		items = append(items, response)
	}

	c.JSON(http.StatusOK, gin.H{"comments": items})
}

func (h *CommentHandler) Create(c *gin.Context) {
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
		Body string `json:"body"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	comment, err := h.addHandler.Execute(c.Request.Context(), commentcmd.AddCommentCommand{
		UserID:  userID,
		MediaID: mediaID,
		Body:    request.Body,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	response, err := h.avatars.commentResponse(c.Request.Context(), comment)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusCreated, response)
}

func (h *CommentHandler) Delete(c *gin.Context) {
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

	commentID, err := uuid.Parse(c.Param("commentId"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	if err := h.deleteHandler.Execute(c.Request.Context(), commentcmd.DeleteCommentCommand{
		UserID:    userID,
		MediaID:   mediaID,
		CommentID: commentID,
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}
