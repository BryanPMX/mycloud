package auth

import "testing"

func TestHashPasswordAndCheckPassword(t *testing.T) {
	t.Parallel()

	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("HashPassword() error = %v", err)
	}
	if hash == "" {
		t.Fatal("HashPassword() returned empty hash")
	}
	if !CheckPassword(hash, "correct horse battery staple") {
		t.Fatal("CheckPassword() = false, want true")
	}
	if CheckPassword(hash, "wrong password") {
		t.Fatal("CheckPassword() = true, want false")
	}
}
