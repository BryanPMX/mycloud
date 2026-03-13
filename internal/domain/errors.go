package domain

import "errors"

var (
	// ErrNotFound is the shared missing-resource error.
	ErrNotFound = errors.New("not found")
)
