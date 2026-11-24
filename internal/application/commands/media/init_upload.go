package media

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
	pkgmime "github.com/yourorg/mycloud/pkg/mime"
)

const (
	DefaultPartSizeBytes = 5 * 1024 * 1024
)

type InitUploadCommand struct {
	ClientUploadID uuid.UUID
	UserID         uuid.UUID
	Filename       string
	MimeType       string
	SizeBytes      int64
}

type InitUploadResult struct {
	MediaID       uuid.UUID
	UploadID      string
	Key           string
	PartSizeBytes int64
	PartURLTTL    int
}

type InitUploadHandler struct {
	mediaRepo     domain.MediaRepository
	userRepo      domain.UserRepository
	storage       domain.StorageService
	uploadStore   domain.UploadSessionStore
	keyBuilder    domain.MediaKeyBuilder
	partSizeBytes int64
	partURLTTL    time.Duration
	sessionTTL    time.Duration
}

func NewInitUploadHandler(
	userRepo domain.UserRepository,
	storage domain.StorageService,
	uploadStore domain.UploadSessionStore,
	keyBuilder domain.MediaKeyBuilder,
	partSizeBytes int64,
	partURLTTL time.Duration,
	sessionTTL time.Duration,
	mediaRepo domain.MediaRepository,
) *InitUploadHandler {
	if partSizeBytes <= 0 {
		partSizeBytes = DefaultPartSizeBytes
	}

	return &InitUploadHandler{
		mediaRepo:     mediaRepo,
		userRepo:      userRepo,
		storage:       storage,
		uploadStore:   uploadStore,
		keyBuilder:    keyBuilder,
		partSizeBytes: partSizeBytes,
		partURLTTL:    partURLTTL,
		sessionTTL:    sessionTTL,
	}
}

func (h *InitUploadHandler) Execute(ctx context.Context, command InitUploadCommand) (*InitUploadResult, error) {
	filename := strings.TrimSpace(command.Filename)
	mimeType := strings.ToLower(strings.TrimSpace(command.MimeType))
	if filename == "" || mimeType == "" || command.SizeBytes <= 0 || command.SizeBytes > domain.MaxUploadSizeBytes || len(filename) > 255 || strings.IndexFunc(filename, func(r rune) bool { return r < 32 || r == 127 }) >= 0 || strings.ContainsAny(filename, "/\\\x00\r\n") {
		return nil, domain.ErrInvalidInput
	}
	if !pkgmime.IsAllowed(mimeType) {
		return nil, domain.ErrUnsupportedMIME
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return nil, err
	}
	// The client may have lost the first HTTP response. Reuse the same owned
	// reservation instead of reserving quota and creating a second multipart job.
	if command.ClientUploadID != uuid.Nil {
		session, lookupErr := h.uploadStore.GetUploadSession(ctx, command.ClientUploadID)
		if lookupErr == nil {
			return h.existingSession(session, command, filename, mimeType)
		}
		if !errors.Is(lookupErr, domain.ErrNotFound) {
			return nil, lookupErr
		}
		if _, lookupErr = h.mediaRepo.FindByIDForUser(ctx, command.ClientUploadID, command.UserID); lookupErr == nil {
			return nil, domain.ErrConflict
		} else if !errors.Is(lookupErr, domain.ErrNotFound) {
			return nil, lookupErr
		}
	}
	if !user.HasQuotaFor(command.SizeBytes + domain.DerivativeBudgetBytes) {
		return nil, domain.ErrQuotaExceeded
	}

	mediaID := uuid.New()
	if command.ClientUploadID != uuid.Nil {
		mediaID = command.ClientUploadID
	}
	now := time.Now().UTC()
	key := h.keyBuilder.BuildMediaObjectKey(user.ID, mediaID, filename, mimeType, now)

	uploadID, err := h.storage.InitiateUpload(ctx, key, mimeType)
	if err != nil {
		return nil, err
	}

	session := domain.UploadSession{
		MediaID:   mediaID,
		OwnerID:   user.ID,
		Filename:  filename,
		MimeType:  mimeType,
		SizeBytes: command.SizeBytes,
		ObjectKey: key,
		UploadID:  uploadID,
		CreatedAt: now,
	}
	if err := h.uploadStore.SaveUploadSession(ctx, session, h.sessionTTL); err != nil {
		_ = h.storage.AbortUpload(ctx, key, uploadID)
		if command.ClientUploadID != uuid.Nil {
			if existing, lookupErr := h.uploadStore.GetUploadSession(ctx, mediaID); lookupErr == nil {
				return h.existingSession(existing, command, filename, mimeType)
			}
		}
		return nil, err
	}

	return &InitUploadResult{
		MediaID:       mediaID,
		UploadID:      uploadID,
		Key:           key,
		PartSizeBytes: h.partSizeBytes,
		PartURLTTL:    int(h.partURLTTL.Seconds()),
	}, nil
}

func (h *InitUploadHandler) existingSession(session *domain.UploadSession, command InitUploadCommand, filename, mimeType string) (*InitUploadResult, error) {
	if session.OwnerID != command.UserID {
		return nil, domain.ErrNotFound
	}
	if session.MediaID != command.ClientUploadID || session.Filename != filename || session.MimeType != mimeType || session.SizeBytes != command.SizeBytes {
		return nil, domain.ErrConflict
	}
	return &InitUploadResult{MediaID: session.MediaID, UploadID: session.UploadID, Key: session.ObjectKey,
		PartSizeBytes: h.partSizeBytes, PartURLTTL: int(h.partURLTTL.Seconds())}, nil
}
