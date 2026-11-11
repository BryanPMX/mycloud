package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type TokenType string

const (
	TokenTypeAccess  TokenType = "access"
	TokenTypeRefresh TokenType = "refresh"
)

type Claims struct {
	AuthVersion int64     `json:"av,omitempty"`
	UserID      uuid.UUID `json:"uid"`
	Role        string    `json:"role,omitempty"`
	Type        TokenType `json:"typ"`
	jwt.RegisteredClaims
}

type TokenDetails struct {
	AuthVersion int64
	UserID      uuid.UUID
	Role        string
	Type        TokenType
	ID          string
	IssuedAt    time.Time
	ExpiresAt   time.Time
}

type Service interface {
	GenerateAccessToken(userID uuid.UUID, role string, version ...int64) (string, error)
	GenerateRefreshToken(userID uuid.UUID, version ...int64) (string, error)
	ValidateAccessToken(token string) (*TokenDetails, error)
	ValidateRefreshToken(token string) (*TokenDetails, error)
}

type service struct {
	secret          []byte
	issuer          string
	accessTokenTTL  time.Duration
	refreshTokenTTL time.Duration
}

func NewJWTService(secret, issuer string, accessTTL, refreshTTL time.Duration) (Service, error) {
	if len(secret) < 32 {
		return nil, errors.New("jwt secret must be at least 32 bytes")
	}
	if accessTTL <= 0 || refreshTTL <= 0 {
		return nil, errors.New("token lifetimes must be positive")
	}
	if issuer == "" {
		return nil, errors.New("jwt issuer is required")
	}

	return &service{
		secret:          []byte(secret),
		issuer:          issuer,
		accessTokenTTL:  accessTTL,
		refreshTokenTTL: refreshTTL,
	}, nil
}

func (s *service) GenerateAccessToken(userID uuid.UUID, role string, version ...int64) (string, error) {
	now := time.Now().UTC()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, Claims{
		UserID:      userID,
		AuthVersion: tokenVersion(version),
		Role:        role,
		Type:        TokenTypeAccess,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    s.issuer,
			Subject:   userID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.accessTokenTTL)),
		},
	})

	return token.SignedString(s.secret)
}

func (s *service) GenerateRefreshToken(userID uuid.UUID, version ...int64) (string, error) {
	now := time.Now().UTC()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, Claims{
		UserID:      userID,
		AuthVersion: tokenVersion(version),
		Type:        TokenTypeRefresh,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        uuid.NewString(),
			Issuer:    s.issuer,
			Subject:   userID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.refreshTokenTTL)),
		},
	})

	return token.SignedString(s.secret)
}

func (s *service) ValidateAccessToken(token string) (*TokenDetails, error) {
	return s.validate(token, TokenTypeAccess)
}

func (s *service) ValidateRefreshToken(token string) (*TokenDetails, error) {
	return s.validate(token, TokenTypeRefresh)
}

func (s *service) validate(raw string, expected TokenType) (*TokenDetails, error) {
	parsed, err := jwt.ParseWithClaims(raw, &Claims{}, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}

		return s.secret, nil
	}, jwt.WithValidMethods([]string{"HS256"}), jwt.WithIssuer(s.issuer), jwt.WithExpirationRequired(), jwt.WithIssuedAt())
	if err != nil {
		return nil, err
	}

	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid token")
	}
	if claims.Type != expected {
		return nil, errors.New("unexpected token type")
	}
	if claims.Issuer != s.issuer {
		return nil, errors.New("unexpected token issuer")
	}
	if claims.AuthVersion < 0 || claims.UserID == uuid.Nil || claims.Subject != claims.UserID.String() || (expected == TokenTypeRefresh && claims.ID == "") {
		return nil, errors.New("invalid token identity")
	}
	if claims.ExpiresAt == nil || claims.IssuedAt == nil {
		return nil, errors.New("missing token timestamps")
	}

	return &TokenDetails{
		UserID:      claims.UserID,
		AuthVersion: claims.AuthVersion,
		Role:        claims.Role,
		Type:        claims.Type,
		ID:          claims.ID,
		IssuedAt:    claims.IssuedAt.Time,
		ExpiresAt:   claims.ExpiresAt.Time,
	}, nil
}

func tokenVersion(values []int64) int64 {
	if len(values) > 0 {
		return values[0]
	}
	return 0
}
