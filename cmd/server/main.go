package main

import (
	"context"
	"log"
	"net/http"
	"time"

	admincmd "github.com/yourorg/mycloud/internal/application/commands/admin"
	albumcmd "github.com/yourorg/mycloud/internal/application/commands/albums"
	authcmd "github.com/yourorg/mycloud/internal/application/commands/auth"
	commentcmd "github.com/yourorg/mycloud/internal/application/commands/comments"
	mediacmd "github.com/yourorg/mycloud/internal/application/commands/media"
	sharecmd "github.com/yourorg/mycloud/internal/application/commands/shares"
	usercmd "github.com/yourorg/mycloud/internal/application/commands/users"
	adminquery "github.com/yourorg/mycloud/internal/application/queries/admin"
	albumquery "github.com/yourorg/mycloud/internal/application/queries/albums"
	commentquery "github.com/yourorg/mycloud/internal/application/queries/comments"
	mediaquery "github.com/yourorg/mycloud/internal/application/queries/media"
	sharequery "github.com/yourorg/mycloud/internal/application/queries/shares"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	httpapi "github.com/yourorg/mycloud/internal/delivery/http"
	"github.com/yourorg/mycloud/internal/delivery/http/handlers"
	wsdelivery "github.com/yourorg/mycloud/internal/delivery/ws"
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
	adminRepo := postgres.NewAdminRepository(db)
	mediaRepo := postgres.NewMediaRepository(db)
	albumRepo := postgres.NewAlbumRepository(db)
	shareRepo := postgres.NewShareRepository(db)
	commentRepo := postgres.NewCommentRepository(db)
	favoriteRepo := postgres.NewFavoriteRepository(db)
	jobRepo := postgres.NewJobRepository(db)
	sessionStore := redisinfra.NewSessionStore(redisClient)
	uploadStore := redisinfra.NewUploadSessionStore(redisClient)
	jobQueue := redisinfra.NewJobQueue(redisClient)
	progressBus := redisinfra.NewMediaProgressBus(redisClient)
	storageService := minioinfra.NewStorageService(minioCore, cfg.MinIOUploadsBuck, cfg.MinIOOrigBuck, cfg.MinIOThumbsBuck, cfg.MinIOAvatarsBuck)
	keyBuilder := minioinfra.NewKeyBuilder()
	progressHub := wsdelivery.NewProgressHub(progressBus)
	go func() {
		if err := progressHub.Run(context.Background()); err != nil && err != context.Canceled {
			log.Printf("progress hub stopped: %v", err)
		}
	}()

	loginHandler := authcmd.NewLoginHandler(userRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	refreshHandler := authcmd.NewRefreshHandler(userRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	logoutHandler := authcmd.NewLogoutHandler(sessionStore, tokenService)
	acceptInviteHandler := authcmd.NewAcceptInviteHandler(adminRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	getMeHandler := userquery.NewGetMeHandler(userRepo)
	updateProfileHandler := usercmd.NewUpdateProfileHandler(userRepo)
	updateAvatarHandler := usercmd.NewUpdateAvatarHandler(userRepo, storageService, keyBuilder)
	listUsersHandler := adminquery.NewListUsersHandler(userRepo, adminRepo)
	systemStatsHandler := adminquery.NewSystemStatsHandler(userRepo, adminRepo)
	getMediaHandler := mediaquery.NewGetMediaHandler(userRepo, mediaRepo, favoriteRepo)
	listMediaHandler := mediaquery.NewListMediaHandler(userRepo, mediaRepo, favoriteRepo)
	searchMediaHandler := mediaquery.NewSearchMediaHandler(userRepo, mediaRepo, favoriteRepo)
	listTrashHandler := mediaquery.NewListTrashHandler(userRepo, mediaRepo, favoriteRepo)
	getDownloadURLHandler := mediaquery.NewGetMediaDownloadURLHandler(userRepo, mediaRepo, storageService)
	getThumbURLHandler := mediaquery.NewGetMediaThumbURLHandler(userRepo, mediaRepo, storageService)
	getAlbumHandler := albumquery.NewGetAlbumHandler(userRepo, albumRepo)
	listAlbumsHandler := albumquery.NewListAlbumsHandler(userRepo, albumRepo)
	listAlbumMediaHandler := albumquery.NewListAlbumMediaHandler(userRepo, albumRepo, mediaRepo, favoriteRepo)
	favoriteMediaHandler := mediacmd.NewFavoriteMediaHandler(userRepo, mediaRepo, favoriteRepo)
	unfavoriteMediaHandler := mediacmd.NewUnfavoriteMediaHandler(userRepo, mediaRepo, favoriteRepo)
	createAlbumHandler := albumcmd.NewCreateAlbumHandler(userRepo, albumRepo)
	updateAlbumHandler := albumcmd.NewUpdateAlbumHandler(userRepo, albumRepo)
	deleteAlbumHandler := albumcmd.NewDeleteAlbumHandler(userRepo, albumRepo)
	addAlbumMediaHandler := albumcmd.NewAddMediaHandler(userRepo, albumRepo, mediaRepo)
	removeAlbumMediaHandler := albumcmd.NewRemoveMediaHandler(userRepo, albumRepo)
	listSharesHandler := sharequery.NewListSharesHandler(userRepo, albumRepo, shareRepo)
	createShareHandler := sharecmd.NewCreateShareHandler(userRepo, albumRepo, shareRepo)
	revokeShareHandler := sharecmd.NewRevokeShareHandler(userRepo, albumRepo, shareRepo)
	listCommentsHandler := commentquery.NewListCommentsHandler(userRepo, mediaRepo, commentRepo)
	addCommentHandler := commentcmd.NewAddCommentHandler(userRepo, mediaRepo, commentRepo)
	deleteCommentHandler := commentcmd.NewDeleteCommentHandler(userRepo, commentRepo)
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
	abortUploadHandler := mediacmd.NewAbortUploadHandler(userRepo, storageService, uploadStore)
	deleteMediaHandler := mediacmd.NewDeleteMediaHandler(userRepo, mediaRepo)
	restoreMediaHandler := mediacmd.NewRestoreMediaHandler(userRepo, mediaRepo)
	permanentDeleteMediaHandler := mediacmd.NewPermanentDeleteMediaHandler(userRepo, mediaRepo, storageService)
	emptyTrashHandler := mediacmd.NewEmptyTrashHandler(userRepo, mediaRepo, storageService)
	inviteUserHandler := admincmd.NewInviteUserHandler(userRepo, adminRepo, cfg.AppBaseURL)
	updateUserHandler := admincmd.NewUpdateUserHandler(userRepo, adminRepo, sessionStore)

	router := httpapi.NewRouter(httpapi.Dependencies{
		AppName:      cfg.AppName,
		AppEnv:       cfg.AppEnv,
		TokenService: tokenService,
		AuthHandler: handlers.NewAuthHandler(
			loginHandler,
			refreshHandler,
			logoutHandler,
			acceptInviteHandler,
			cfg.AppEnv == "production",
			int(cfg.JWTRefreshTTL.Seconds()),
		),
		AlbumHandler: handlers.NewAlbumHandler(
			getAlbumHandler,
			listAlbumsHandler,
			listAlbumMediaHandler,
			createAlbumHandler,
			updateAlbumHandler,
			deleteAlbumHandler,
			addAlbumMediaHandler,
			removeAlbumMediaHandler,
		),
		ShareHandler: handlers.NewShareHandler(
			listSharesHandler,
			createShareHandler,
			revokeShareHandler,
		),
		UserHandler: handlers.NewUserHandler(getMeHandler, updateProfileHandler, updateAvatarHandler),
		ProgressHub: progressHub,
		MediaHandler: handlers.NewMediaHandler(
			getMediaHandler,
			listMediaHandler,
			searchMediaHandler,
			listTrashHandler,
			getDownloadURLHandler,
			getThumbURLHandler,
			favoriteMediaHandler,
			unfavoriteMediaHandler,
			initUploadHandler,
			partURLHandler,
			completeUploadHandler,
			abortUploadHandler,
			deleteMediaHandler,
			restoreMediaHandler,
			permanentDeleteMediaHandler,
			emptyTrashHandler,
		),
		CommentHandler: handlers.NewCommentHandler(listCommentsHandler, addCommentHandler, deleteCommentHandler),
		AdminHandler: handlers.NewAdminHandler(
			listUsersHandler,
			inviteUserHandler,
			updateUserHandler,
			systemStatsHandler,
		),
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
