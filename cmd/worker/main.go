package main

import (
	"context"
	"log"
	"os/signal"
	"syscall"
	"time"

	maintenancecmd "github.com/yourorg/mycloud/internal/application/commands/maintenance"
	"github.com/yourorg/mycloud/internal/infrastructure/clamav"
	minioinfra "github.com/yourorg/mycloud/internal/infrastructure/minio"
	"github.com/yourorg/mycloud/internal/infrastructure/postgres"
	redisinfra "github.com/yourorg/mycloud/internal/infrastructure/redis"
	"github.com/yourorg/mycloud/internal/infrastructure/worker"
	"github.com/yourorg/mycloud/pkg/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	bootCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	db, err := postgres.NewPool(bootCtx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("connect postgres: %v", err)
	}
	defer db.Close()

	redisClient, err := redisinfra.NewClient(cfg.RedisURL)
	if err != nil {
		log.Fatalf("connect redis: %v", err)
	}
	defer redisClient.Close()

	minioCore, err := minioinfra.NewCore(
		bootCtx,
		cfg.MinIOEndpoint,
		cfg.MinIOAccessKey,
		cfg.MinIOSecretKey,
		cfg.MinIOSecure,
		cfg.MinIOUploadsBuck,
		cfg.MinIOOrigBuck,
		cfg.MinIOThumbsBuck,
		cfg.MinIOAvatarsBuck,
	)
	if err != nil {
		log.Fatalf("connect minio: %v", err)
	}

	jobQueue := redisinfra.NewJobQueue(redisClient)
	jobRepo := postgres.NewJobRepository(db)
	mediaRepo := postgres.NewMediaRepository(db)
	shareRepo := postgres.NewShareRepository(db)
	progressBus := redisinfra.NewMediaProgressBus(redisClient)
	storage := minioinfra.NewStorageService(minioCore, cfg.MinIOUploadsBuck, cfg.MinIOOrigBuck, cfg.MinIOThumbsBuck, cfg.MinIOAvatarsBuck)
	scanner := clamav.NewScanner(cfg.ClamAVSocket)
	keyBuilder := minioinfra.NewKeyBuilder()
	processor := worker.NewFFMpegMediaProcessor(storage, keyBuilder)
	cleanupHandler := maintenancecmd.NewRunCleanupHandler(mediaRepo, shareRepo, storage)
	scheduler := worker.NewCleanupScheduler(jobRepo, jobQueue, cfg.CleanupInterval)

	go scheduler.Run(ctx)

	runner := worker.NewJobRunner(jobQueue, jobRepo, mediaRepo, storage, scanner, progressBus, processor, cleanupHandler, 5*time.Second)

	log.Printf("%s worker started", cfg.AppName)
	runner.Run(ctx)
}
