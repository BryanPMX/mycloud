package main

import (
	"context"
	"log"
	"net/http"
	"time"

	authcmd "github.com/yourorg/mycloud/internal/application/commands/auth"
	mediacmd "github.com/yourorg/mycloud/internal/application/commands/media"
	mediaquery "github.com/yourorg/mycloud/internal/application/queries/media"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	httpapi "github.com/yourorg/mycloud/internal/delivery/http"
	"github.com/yourorg/mycloud/internal/delivery/http/handlers"
	minioinfra "github.com/yourorg/mycloud/internal/infrastructure/minio"
	"github.com/yourorg/mycloud/internal/infrastructure/postgres"
	redisinfra "github.com/yourorg/mycloud/internal/infrastructure/redis"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
	"github.com/yourorg/mycloud/pkg/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	db, err := postgres.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("connect postgres: %v", err)
	}
	defer db.Close()

	redisClient, err := redisinfra.NewClient(cfg.RedisURL)
	if err != nil {
		log.Fatalf("connect redis: %v", err)
	}
	defer redisClient.Close()

	minioCtx, minioCancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer minioCancel()

	minioCore, err := minioinfra.NewCore(
		minioCtx,
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

	tokenService, err := pkgauth.NewJWTService(cfg.JWTSecret, cfg.JWTIssuer, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	if err != nil {
		log.Fatalf("create token service: %v", err)
	}

	userRepo := postgres.NewUserRepository(db)
	mediaRepo := postgres.NewMediaRepository(db)
	jobRepo := postgres.NewJobRepository(db)
	sessionStore := redisinfra.NewSessionStore(redisClient)
	uploadStore := redisinfra.NewUploadSessionStore(redisClient)
	jobQueue := redisinfra.NewJobQueue(redisClient)
	storageService := minioinfra.NewStorageService(minioCore, cfg.MinIOUploadsBuck, cfg.MinIOOrigBuck)
	keyBuilder := minioinfra.NewKeyBuilder()

	loginHandler := authcmd.NewLoginHandler(userRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	refreshHandler := authcmd.NewRefreshHandler(userRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	logoutHandler := authcmd.NewLogoutHandler(sessionStore, tokenService)
	getMeHandler := userquery.NewGetMeHandler(userRepo)
	listMediaHandler := mediaquery.NewListMediaHandler(userRepo, mediaRepo)
	initUploadHandler := mediacmd.NewInitUploadHandler(
		userRepo,
		storageService,
		uploadStore,
		keyBuilder,
		mediacmd.DefaultPartSizeBytes,
		15*time.Minute,
		48*time.Hour,
	)
	partURLHandler := mediacmd.NewPresignUploadPartHandler(userRepo, storageService, uploadStore, 15*time.Minute)
	completeUploadHandler := mediacmd.NewCompleteUploadHandler(userRepo, mediaRepo, jobRepo, jobQueue, storageService, uploadStore)

	router := httpapi.NewRouter(httpapi.Dependencies{
		AppName:      cfg.AppName,
		AppEnv:       cfg.AppEnv,
		TokenService: tokenService,
		AuthHandler: handlers.NewAuthHandler(
			loginHandler,
			refreshHandler,
			logoutHandler,
			cfg.AppEnv == "production",
			int(cfg.JWTRefreshTTL.Seconds()),
		),
		UserHandler:  handlers.NewUserHandler(getMeHandler),
		MediaHandler: handlers.NewMediaHandler(listMediaHandler, initUploadHandler, partURLHandler, completeUploadHandler),
	})

	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  cfg.ReadTimeout,
		WriteTimeout: cfg.WriteTimeout,
		IdleTimeout:  cfg.IdleTimeout,
	}

	log.Printf("%s API listening on :%s", cfg.AppName, cfg.Port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("serve http: %v", err)
	}
}
