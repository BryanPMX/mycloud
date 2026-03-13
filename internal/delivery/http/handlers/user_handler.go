package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
)

type UserHandler struct {
	getMeHandler *userquery.GetMeHandler
}

func NewUserHandler(getMeHandler *userquery.GetMeHandler) *UserHandler {
	return &UserHandler{getMeHandler: getMeHandler}
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
