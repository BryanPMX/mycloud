package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	AppName       string
	AppEnv        string
	Port          string
	DatabaseURL   string
	RedisURL      string
	JWTSecret     string
	JWTIssuer     string
	JWTAccessTTL  time.Duration
	JWTRefreshTTL time.Duration
	ReadTimeout   time.Duration
	WriteTimeout  time.Duration
	IdleTimeout   time.Duration
}

func Load() (Config, error) {
	cfg := Config{
		AppName:      getEnv("APP_NAME", "MyCloud"),
		AppEnv:       getEnv("APP_ENV", "development"),
		Port:         getEnv("PORT", "8080"),
		DatabaseURL:  strings.TrimSpace(os.Getenv("DATABASE_URL")),
		RedisURL:     strings.TrimSpace(os.Getenv("REDIS_URL")),
		JWTSecret:    os.Getenv("JWT_SECRET"),
		JWTIssuer:    getEnv("JWT_ISSUER", "mycloud"),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	accessMinutes, err := parsePositiveInt("JWT_ACCESS_TTL_MINUTES", 15)
	if err != nil {
		return Config{}, err
	}
	refreshDays, err := parsePositiveInt("JWT_REFRESH_TTL_DAYS", 30)
	if err != nil {
		return Config{}, err
	}
	cfg.JWTAccessTTL = time.Duration(accessMinutes) * time.Minute
	cfg.JWTRefreshTTL = time.Duration(refreshDays) * 24 * time.Hour

	var missing []string
	if cfg.DatabaseURL == "" {
		missing = append(missing, "DATABASE_URL")
	}
	if cfg.RedisURL == "" {
		missing = append(missing, "REDIS_URL")
	}
	if strings.TrimSpace(cfg.JWTSecret) == "" {
		missing = append(missing, "JWT_SECRET")
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required environment variables: %s", strings.Join(missing, ", "))
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}

	return fallback
}

func parsePositiveInt(key string, fallback int) (int, error) {
	raw := getEnv(key, strconv.Itoa(fallback))
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return 0, errors.New(key + " must be a positive integer")
	}

	return value, nil
}
