package handlers

import (
	"errors"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"

	usercmd "github.com/yourorg/mycloud/internal/application/commands/users"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type UserHandler struct {
	getMeHandler         *userquery.GetMeHandler
	updateProfileHandler *usercmd.UpdateProfileHandler
	updateAvatarHandler  *usercmd.UpdateAvatarHandler
}

func NewUserHandler(
	getMeHandler *userquery.GetMeHandler,
	updateProfileHandler *usercmd.UpdateProfileHandler,
	updateAvatarHandler *usercmd.UpdateAvatarHandler,
) *UserHandler {
	return &UserHandler{
		getMeHandler:         getMeHandler,
		updateProfileHandler: updateProfileHandler,
		updateAvatarHandler:  updateAvatarHandler,
	}
}

func (h *UserHandler) GetMe(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	user, err := h.getMeHandler.Execute(c.Request.Context(), userquery.GetMeQuery{
		UserID: userID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToUserResponse(user))
}

func (h *UserHandler) UpdateMe(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	var request struct {
		DisplayName string `json:"display_name"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	user, err := h.updateProfileHandler.Execute(c.Request.Context(), usercmd.UpdateProfileCommand{
		UserID:      userID,
		DisplayName: request.DisplayName,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToUserResponse(user))
}

func (h *UserHandler) UpdateAvatar(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, usercmd.MaxAvatarBytes)
	content, err := io.ReadAll(c.Request.Body)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{
				"error": "request body too large",
				"code":  "PAYLOAD_TOO_LARGE",
			})
			return
		}
		writeError(c, errInvalidInput())
		return
	}

	user, err := h.updateAvatarHandler.Execute(c.Request.Context(), usercmd.UpdateAvatarCommand{
		UserID:   userID,
		MimeType: c.ContentType(),
		Content:  content,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.AvatarURLResponse{
		AvatarURL: dto.ToUserResponse(user).AvatarURL,
	})
}
