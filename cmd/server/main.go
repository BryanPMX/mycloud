package main

import (
	"context"
	"log"
	"net/http"
	"time"

	authcmd "github.com/yourorg/mycloud/internal/application/commands/auth"
	mediaquery "github.com/yourorg/mycloud/internal/application/queries/media"
	userquery "github.com/yourorg/mycloud/internal/application/queries/users"
	httpapi "github.com/yourorg/mycloud/internal/delivery/http"
	"github.com/yourorg/mycloud/internal/delivery/http/handlers"
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

	tokenService, err := pkgauth.NewJWTService(cfg.JWTSecret, cfg.JWTIssuer, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	if err != nil {
		log.Fatalf("create token service: %v", err)
	}

	userRepo := postgres.NewUserRepository(db)
	mediaRepo := postgres.NewMediaRepository(db)
	sessionStore := redisinfra.NewSessionStore(redisClient)

	loginHandler := authcmd.NewLoginHandler(userRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	refreshHandler := authcmd.NewRefreshHandler(userRepo, sessionStore, tokenService, cfg.JWTAccessTTL, cfg.JWTRefreshTTL)
	logoutHandler := authcmd.NewLogoutHandler(sessionStore, tokenService)
	getMeHandler := userquery.NewGetMeHandler(userRepo)
	listMediaHandler := mediaquery.NewListMediaHandler(userRepo, mediaRepo)

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
		MediaHandler: handlers.NewMediaHandler(listMediaHandler),
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
