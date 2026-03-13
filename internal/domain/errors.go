package domain

import "errors"

var (
	ErrNotFound           = errors.New("not found")
	ErrForbidden          = errors.New("forbidden")
	ErrUnauthorized       = errors.New("unauthorized")
	ErrConflict           = errors.New("conflict")
	ErrInvalidInput       = errors.New("invalid input")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInactiveUser       = errors.New("inactive user")
	ErrInvalidToken       = errors.New("invalid token")
	ErrMissingToken       = errors.New("missing token")
	ErrInactiveSession    = errors.New("inactive session")
	ErrQuotaExceeded      = errors.New("quota exceeded")
	ErrUnsupportedMIME    = errors.New("unsupported mime type")
)
