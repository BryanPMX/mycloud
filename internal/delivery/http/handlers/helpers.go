package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yourorg/mycloud/internal/domain"
)

func errInvalidInput() error {
	return domain.ErrInvalidInput
}

func errUnauthorized() error {
	return domain.ErrUnauthorized
}

func writeError(c *gin.Context, err error) {
	status := http.StatusInternalServerError
	code := "INTERNAL_ERROR"
	message := "internal server error"

	switch {
	case errors.Is(err, domain.ErrInvalidInput):
		status = http.StatusBadRequest
		code = "INVALID_INPUT"
		message = "invalid request"
	case errors.Is(err, domain.ErrInvalidCredentials):
		status = http.StatusUnauthorized
		code = "INVALID_CREDENTIALS"
		message = "invalid email or password"
	case errors.Is(err, domain.ErrMissingToken):
		status = http.StatusUnauthorized
		code = "MISSING_TOKEN"
		message = "missing token"
	case errors.Is(err, domain.ErrInvalidToken):
		status = http.StatusUnauthorized
		code = "INVALID_TOKEN"
		message = "invalid token"
	case errors.Is(err, domain.ErrInactiveSession):
		status = http.StatusUnauthorized
		code = "INACTIVE_SESSION"
		message = "refresh token revoked or expired"
	case errors.Is(err, domain.ErrUnauthorized):
		status = http.StatusUnauthorized
		code = "UNAUTHORIZED"
		message = "unauthorized"
	case errors.Is(err, domain.ErrForbidden):
		status = http.StatusForbidden
		code = "FORBIDDEN"
		message = "forbidden"
	case errors.Is(err, domain.ErrNotFound):
		status = http.StatusNotFound
		code = "NOT_FOUND"
		message = "resource not found"
	case errors.Is(err, domain.ErrConflict):
		status = http.StatusConflict
		code = "CONFLICT"
		message = "resource conflict"
	case errors.Is(err, domain.ErrQuotaExceeded):
		status = http.StatusConflict
		code = "QUOTA_EXCEEDED"
		message = "storage quota exceeded"
	case errors.Is(err, domain.ErrUnsupportedMIME):
		status = http.StatusUnsupportedMediaType
		code = "UNSUPPORTED_MEDIA_TYPE"
		message = "unsupported media type"
	}

	c.JSON(status, gin.H{
		"error": message,
		"code":  code,
	})
}
