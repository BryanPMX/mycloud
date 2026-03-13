package domain

import (
	"time"

	"github.com/google/uuid"
)

type JobType string

const (
	JobTypeProcessMedia JobType = "process_media"
	JobTypeCleanup      JobType = "cleanup"
)

type JobStatus string

const (
	JobStatusQueued  JobStatus = "queued"
	JobStatusRunning JobStatus = "running"
	JobStatusDone    JobStatus = "done"
	JobStatusFailed  JobStatus = "failed"
)

// Job represents asynchronous work handled by the worker subsystem.
type Job struct {
	ID          uuid.UUID
	MediaID     *uuid.UUID
	Type        JobType
	Status      JobStatus
	Payload     map[string]any
	Error       string
	Attempts    int
	CreatedAt   time.Time
	StartedAt   *time.Time
	CompletedAt *time.Time
}
