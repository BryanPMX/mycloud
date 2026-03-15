package handlers

import (
	"errors"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	usercmd "github.com/yourorg/mycloud/internal/application/commands/users"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type UserHandler struct {
	getMeHandler         *userquery.GetMeHandler
	getAvatarURLHandler  *userquery.GetAvatarURLHandler
	listDirectoryHandler *userquery.ListDirectoryHandler
	updateProfileHandler *usercmd.UpdateProfileHandler
	updateAvatarHandler  *usercmd.UpdateAvatarHandler
	avatars              *avatarPresenter
}

func NewUserHandler(
	getMeHandler *userquery.GetMeHandler,
	getAvatarURLHandler *userquery.GetAvatarURLHandler,
	listDirectoryHandler *userquery.ListDirectoryHandler,
	updateProfileHandler *usercmd.UpdateProfileHandler,
	updateAvatarHandler *usercmd.UpdateAvatarHandler,
	avatarStorage domain.AvatarAssetReader,
) *UserHandler {
	return &UserHandler{
		getMeHandler:         getMeHandler,
		getAvatarURLHandler:  getAvatarURLHandler,
		listDirectoryHandler: listDirectoryHandler,
		updateProfileHandler: updateProfileHandler,
		updateAvatarHandler:  updateAvatarHandler,
		avatars:              newAvatarPresenter(avatarStorage, userquery.DefaultAvatarURLTTL),
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

	response, err := h.avatars.userResponse(c.Request.Context(), user)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, response)
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

	response, err := h.avatars.userResponse(c.Request.Context(), user)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, response)
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

	response, err := h.avatars.avatarURLResponse(c.Request.Context(), user.AvatarKey)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, response)
}

func (h *UserHandler) GetAvatarURL(c *gin.Context) {
	requestUserID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	targetUserID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	ttlSeconds, err := parseIntQuery(c, "ttl")
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.getAvatarURLHandler.Execute(c.Request.Context(), userquery.GetAvatarURLQuery{
		RequestUserID: requestUserID,
		TargetUserID:  targetUserID,
		TTLSeconds:    ttlSeconds,
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

func (h *UserHandler) ListDirectory(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	users, err := h.listDirectoryHandler.Execute(c.Request.Context(), userquery.ListDirectoryQuery{
		UserID: userID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	items := make([]dto.DirectoryUserResponse, 0, len(users))
	for _, user := range users {
		response, err := h.avatars.directoryUserResponse(c.Request.Context(), user)
		if err != nil {
			writeError(c, err)
			return
		}
		items = append(items, response)
	}

	c.JSON(http.StatusOK, gin.H{"users": items})
}
