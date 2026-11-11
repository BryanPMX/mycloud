package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

func TestJWTServiceRoundTrip(t *testing.T) {
	t.Parallel()

	service, err := NewJWTService("12345678901234567890123456789012", "mycloud", 15*time.Minute, 24*time.Hour)
	if err != nil {
		t.Fatalf("NewJWTService() error = %v", err)
	}

	userID := uuid.New()
	accessToken, err := service.GenerateAccessToken(userID, "member")
	if err != nil {
		t.Fatalf("GenerateAccessToken() error = %v", err)
	}

	details, err := service.ValidateAccessToken(accessToken)
	if err != nil {
		t.Fatalf("ValidateAccessToken() error = %v", err)
	}
	if details.UserID != userID {
		t.Fatalf("ValidateAccessToken() userID = %s, want %s", details.UserID, userID)
	}
	if details.Role != "member" {
		t.Fatalf("ValidateAccessToken() role = %q, want member", details.Role)
	}

	refreshToken, err := service.GenerateRefreshToken(userID)
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}

	refreshDetails, err := service.ValidateRefreshToken(refreshToken)
	if err != nil {
		t.Fatalf("ValidateRefreshToken() error = %v", err)
	}
	if refreshDetails.UserID != userID {
		t.Fatalf("ValidateRefreshToken() userID = %s, want %s", refreshDetails.UserID, userID)
	}
	if refreshDetails.ID == "" {
		t.Fatal("ValidateRefreshToken() returned empty session id")
	}
}

func TestJWTServiceRejectsWrongTokenType(t *testing.T) {
	t.Parallel()

	service, err := NewJWTService("12345678901234567890123456789012", "mycloud", 15*time.Minute, 24*time.Hour)
	if err != nil {
		t.Fatalf("NewJWTService() error = %v", err)
	}

	token, err := service.GenerateRefreshToken(uuid.New())
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}

	if _, err := service.ValidateAccessToken(token); err == nil {
		t.Fatal("ValidateAccessToken() error = nil, want wrong token type failure")
	}
}

func TestJWTRejectsOtherHMACAlgorithmsAndInvalidIdentity(t *testing.T) {
	secret := "12345678901234567890123456789012"
	service, err := NewJWTService(secret, "mycloud", time.Minute, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	id := uuid.New()
	now := time.Now()
	claims := Claims{UserID: id, Role: "member", Type: TokenTypeAccess, RegisteredClaims: jwt.RegisteredClaims{Issuer: "mycloud", Subject: id.String(), IssuedAt: jwt.NewNumericDate(now), ExpiresAt: jwt.NewNumericDate(now.Add(time.Minute))}}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS384, claims).SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = service.ValidateAccessToken(token); err == nil {
		t.Fatal("accepted HS384 despite HS256-only policy")
	}
	claims.Subject = uuid.NewString()
	token, err = jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = service.ValidateAccessToken(token); err == nil {
		t.Fatal("accepted mismatched subject")
	}
}
