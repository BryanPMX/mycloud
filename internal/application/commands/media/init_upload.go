package media

import (
	"context"
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
	UserID    uuid.UUID
	Filename  string
	MimeType  string
	SizeBytes int64
}

type InitUploadResult struct {
	MediaID       uuid.UUID
	UploadID      string
	Key           string
	PartSizeBytes int64
	PartURLTTL    int
}

type InitUploadHandler struct {
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
) *InitUploadHandler {
	if partSizeBytes <= 0 {
		partSizeBytes = DefaultPartSizeBytes
	}

	return &InitUploadHandler{
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
	if filename == "" || mimeType == "" || command.SizeBytes <= 0 {
		return nil, domain.ErrInvalidInput
	}
	if !pkgmime.IsAllowed(mimeType) {
		return nil, domain.ErrUnsupportedMIME
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return nil, err
	}
	if !user.HasQuotaFor(command.SizeBytes) {
		return nil, domain.ErrQuotaExceeded
	}

	mediaID := uuid.New()
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
