package main

import (
	"context"
	"github.com/yourorg/mycloud/internal/infrastructure/observability"
	"log"
	"log/slog"
	"os"
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
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
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
		log.Fatal("PostgreSQL connection failed")
	}
	defer db.Close()

	redisClient, err := redisinfra.NewClient(cfg.RedisURL)
	if err != nil {
		log.Fatal("Redis connection failed")
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
		log.Fatal("MinIO connection or privacy verification failed")
	}

	jobQueue := redisinfra.NewJobQueue(redisClient)
	jobRepo := postgres.NewJobRepository(db)
	mediaRepo := postgres.NewMediaRepository(db)
	shareRepo := postgres.NewShareRepository(db)
	progressBus := redisinfra.NewMediaProgressBus(redisClient)
	storage := minioinfra.NewStorageService(minioCore, nil, cfg.MinIOUploadsBuck, cfg.MinIOOrigBuck, cfg.MinIOThumbsBuck, cfg.MinIOAvatarsBuck)
	scanner := clamav.NewScanner(cfg.ClamAVSocket)
	keyBuilder := minioinfra.NewKeyBuilder()
	processor := worker.NewFFMpegMediaProcessor(storage, keyBuilder)
	cleanupHandler := maintenancecmd.NewRunCleanupHandler(mediaRepo, shareRepo, storage)
	scheduler := worker.NewCleanupScheduler(jobRepo, jobQueue, cfg.CleanupInterval)

	go scheduler.Run(ctx)
	go postgres.RunMaintenance(ctx, jobRepo, mediaRepo, postgres.NewUploadSessionStore(db), storage, jobQueue)

	runner := worker.NewJobRunner(jobQueue, jobRepo, mediaRepo, storage, scanner, progressBus, processor, cleanupHandler, 5*time.Second)

	metrics := observability.New(db, redisClient)
	runner.Observe = func(kind, outcome string) { metrics.Jobs.WithLabelValues(kind, outcome).Inc() }
	go observability.ServePrivate(ctx, ":9090", metrics, func(ctx context.Context) error {
		if err := db.Ping(ctx); err != nil {
			return err
		}
		if err := redisClient.Ping(ctx).Err(); err != nil {
			return err
		}
		if err := scanner.Ping(ctx); err != nil {
			return err
		}
		for _, bucket := range []string{cfg.MinIOUploadsBuck, cfg.MinIOOrigBuck, cfg.MinIOThumbsBuck, cfg.MinIOAvatarsBuck} {
			if _, err := minioCore.BucketExists(ctx, bucket); err != nil {
				return err
			}
		}
		return nil
	})
	log.Printf("%s worker started", cfg.AppName)
	runner.Run(ctx)
}
