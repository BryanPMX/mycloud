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
	AppName             string
	AppEnv              string
	AppBaseURL          string
	AllowedOrigins      []string
	Port                string
	DatabaseURL         string
	RedisURL            string
	MinIOEndpoint       string
	MinIOPublicEndpoint string
	MinIOAccessKey      string
	MinIOSecretKey      string
	MinIOSecure         bool
	MinIOPublicSecure   bool
	MinIOUploadsBuck    string
	MinIOOrigBuck       string
	MinIOThumbsBuck     string
	MinIOAvatarsBuck    string
	ClamAVSocket        string
	SMTPHost            string
	SMTPPort            int
	SMTPUser            string
	SMTPPass            string
	SMTPFrom            string
	JWTSecret           string
	JWTIssuer           string
	JWTAccessTTL        time.Duration
	JWTRefreshTTL       time.Duration
	CleanupInterval     time.Duration
	ReadTimeout         time.Duration
	WriteTimeout        time.Duration
	IdleTimeout         time.Duration
}

func Load() (Config, error) {
	cfg := Config{
		AppName:             getEnv("APP_NAME", "MyCloud"),
		AppEnv:              getEnv("APP_ENV", "development"),
		AppBaseURL:          getEnv("APP_BASE_URL", "http://localhost:8080"),
		AllowedOrigins:      parseCSVEnv("ALLOWED_ORIGINS"),
		Port:                getEnv("PORT", "8080"),
		DatabaseURL:         strings.TrimSpace(os.Getenv("DATABASE_URL")),
		RedisURL:            strings.TrimSpace(os.Getenv("REDIS_URL")),
		MinIOEndpoint:       strings.TrimSpace(os.Getenv("MINIO_ENDPOINT")),
		MinIOPublicEndpoint: strings.TrimSpace(os.Getenv("MINIO_PUBLIC_ENDPOINT")),
		MinIOAccessKey:      strings.TrimSpace(os.Getenv("MINIO_ACCESS_KEY")),
		MinIOSecretKey:      strings.TrimSpace(os.Getenv("MINIO_SECRET_KEY")),
		MinIOUploadsBuck:    getEnv("MINIO_UPLOADS_BUCKET", "fc-uploads"),
		MinIOOrigBuck:       getEnv("MINIO_ORIGINALS_BUCKET", "fc-originals"),
		MinIOThumbsBuck:     getEnv("MINIO_THUMBS_BUCKET", "fc-thumbs"),
		MinIOAvatarsBuck:    getEnv("MINIO_AVATARS_BUCKET", "fc-avatars"),
		ClamAVSocket:        strings.TrimSpace(os.Getenv("CLAMAV_SOCKET")),
		SMTPHost:            strings.TrimSpace(os.Getenv("SMTP_HOST")),
		SMTPUser:            strings.TrimSpace(os.Getenv("SMTP_USER")),
		SMTPPass:            os.Getenv("SMTP_PASS"),
		SMTPFrom:            strings.TrimSpace(os.Getenv("SMTP_FROM")),
		JWTSecret:           os.Getenv("JWT_SECRET"),
		JWTIssuer:           getEnv("JWT_ISSUER", "mycloud"),
		ReadTimeout:         10 * time.Second,
		WriteTimeout:        15 * time.Second,
		IdleTimeout:         60 * time.Second,
	}
	if len(cfg.AllowedOrigins) == 0 && strings.TrimSpace(cfg.AppBaseURL) != "" {
		cfg.AllowedOrigins = []string{strings.TrimRight(cfg.AppBaseURL, "/")}
	}
	minioSecure, err := parseBool("MINIO_SECURE", false)
	if err != nil {
		return Config{}, err
	}
	cfg.MinIOSecure = minioSecure
	if cfg.MinIOPublicEndpoint == "" {
		cfg.MinIOPublicEndpoint = cfg.MinIOEndpoint
	}
	minioPublicSecure, err := parseBool("MINIO_PUBLIC_SECURE", cfg.MinIOSecure)
	if err != nil {
		return Config{}, err
	}
	cfg.MinIOPublicSecure = minioPublicSecure

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

	smtpPort, err := parsePositiveInt("SMTP_PORT", 1025)
	if err != nil {
		return Config{}, err
	}
	cfg.SMTPPort = smtpPort

	cleanupMinutes, err := parsePositiveInt("CLEANUP_INTERVAL_MINUTES", 60)
	if err != nil {
		return Config{}, err
	}
	cfg.CleanupInterval = time.Duration(cleanupMinutes) * time.Minute

	var missing []string
	if cfg.DatabaseURL == "" {
		missing = append(missing, "DATABASE_URL")
	}
	if cfg.RedisURL == "" {
		missing = append(missing, "REDIS_URL")
	}
	if cfg.MinIOEndpoint == "" {
		missing = append(missing, "MINIO_ENDPOINT")
	}
	if cfg.MinIOAccessKey == "" {
		missing = append(missing, "MINIO_ACCESS_KEY")
	}
	if cfg.MinIOSecretKey == "" {
		missing = append(missing, "MINIO_SECRET_KEY")
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

func parseBool(key string, fallback bool) (bool, error) {
	raw := getEnv(key, strconv.FormatBool(fallback))
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, errors.New(key + " must be a boolean")
	}

	return value, nil
}

func parseCSVEnv(key string) []string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return nil
	}

	parts := strings.Split(raw, ",")
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		value := strings.TrimRight(strings.TrimSpace(part), "/")
		if value == "" {
			continue
		}
		values = append(values, value)
	}

	return values
}
