package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	admincmd "github.com/yourorg/mycloud/internal/application/commands/admin"
	adminquery "github.com/yourorg/mycloud/internal/application/queries/admin"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type AdminHandler struct {
	listUsersHandler   *adminquery.ListUsersHandler
	inviteUserHandler  *admincmd.InviteUserHandler
	updateUserHandler  *admincmd.UpdateUserHandler
	systemStatsHandler *adminquery.SystemStatsHandler
	avatars            *avatarPresenter
}

func NewAdminHandler(
	listUsersHandler *adminquery.ListUsersHandler,
	inviteUserHandler *admincmd.InviteUserHandler,
	updateUserHandler *admincmd.UpdateUserHandler,
	systemStatsHandler *adminquery.SystemStatsHandler,
	avatarStorage domain.AvatarAssetReader,
) *AdminHandler {
	return &AdminHandler{
		listUsersHandler:   listUsersHandler,
		inviteUserHandler:  inviteUserHandler,
		updateUserHandler:  updateUserHandler,
		systemStatsHandler: systemStatsHandler,
		avatars:            newAvatarPresenter(avatarStorage, userquery.DefaultAvatarURLTTL),
	}
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	users, err := h.listUsersHandler.Execute(c.Request.Context(), adminquery.ListUsersQuery{
		UserID: userID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	items := make([]dto.AdminUserResponse, 0, len(users))
	for _, user := range users {
		response, err := h.avatars.adminUserResponse(c.Request.Context(), user)
		if err != nil {
			writeError(c, err)
			return
		}
		items = append(items, response)
	}

	c.JSON(http.StatusOK, gin.H{"users": items})
}

func (h *AdminHandler) InviteUser(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	var request struct {
		Email   string `json:"email"`
		Role    string `json:"role"`
		QuotaGB int64  `json:"quota_gb"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.inviteUserHandler.Execute(c.Request.Context(), admincmd.InviteUserCommand{
		AdminUserID: userID,
		Email:       request.Email,
		Role:        request.Role,
		QuotaGB:     request.QuotaGB,
		IPAddress:   clientIPAddr(c),
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusCreated, dto.ToInviteUserResponse(result.User, result.InviteURL, result.ExpiresAt))
}

func (h *AdminHandler) UpdateUser(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	targetUserID, err := parseAdminUserIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	var fields map[string]json.RawMessage
	if err := httpx.BindJSON(c, &fields); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	command := admincmd.UpdateUserCommand{
		AdminUserID:  userID,
		TargetUserID: targetUserID,
		IPAddress:    clientIPAddr(c),
	}
	if err := populateAdminUpdateCommand(fields, &command); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	user, err := h.updateUserHandler.Execute(c.Request.Context(), command)
	if err != nil {
		writeError(c, err)
		return
	}

	response, err := h.avatars.adminUserResponse(c.Request.Context(), user)
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, response)
}

func (h *AdminHandler) DeactivateUser(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	targetUserID, err := parseAdminUserIDParam(c.Param("id"))
	if err != nil {
		writeError(c, errInvalidInput())
		return
	}

	active := false
	if _, err := h.updateUserHandler.Execute(c.Request.Context(), admincmd.UpdateUserCommand{
		AdminUserID:  userID,
		TargetUserID: targetUserID,
		Active:       &active,
		IPAddress:    clientIPAddr(c),
	}); err != nil {
		writeError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *AdminHandler) SystemStats(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		writeError(c, errUnauthorized())
		return
	}

	stats, err := h.systemStatsHandler.Execute(c.Request.Context(), adminquery.SystemStatsQuery{
		UserID: userID,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, dto.ToSystemStatsResponse(stats))
}

func parseAdminUserIDParam(raw string) (uuid.UUID, error) {
	return uuid.Parse(raw)
}

func populateAdminUpdateCommand(fields map[string]json.RawMessage, command *admincmd.UpdateUserCommand) error {
	for key, value := range fields {
		switch key {
		case "role":
			var role string
			if err := json.Unmarshal(value, &role); err != nil {
				return err
			}
			command.Role = &role
		case "quota_bytes":
			var quotaBytes int64
			if err := json.Unmarshal(value, &quotaBytes); err != nil {
				return err
			}
			command.QuotaBytes = &quotaBytes
		case "active":
			var active bool
			if err := json.Unmarshal(value, &active); err != nil {
				return err
			}
			command.Active = &active
		default:
			return errInvalidInput()
		}
	}

	if command.Role == nil && command.QuotaBytes == nil && command.Active == nil {
		return errInvalidInput()
	}

	return nil
}
