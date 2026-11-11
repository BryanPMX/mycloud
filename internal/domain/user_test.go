package domain

import (
	"math"
	"testing"
)

func TestQuotaRejectsNegativeAndOverflow(t *testing.T) {
	for _, user := range []User{{StorageUsed: math.MaxInt64 - 1, QuotaBytes: math.MaxInt64}, {StorageUsed: -1, QuotaBytes: 10}, {StorageUsed: 11, QuotaBytes: 10}} {
		if user.HasQuotaFor(math.MaxInt64) {
			t.Fatal("quota accepted overflow or inconsistent accounting")
		}
		if user.HasQuotaFor(-1) {
			t.Fatal("quota accepted negative bytes")
		}
	}
	if !(User{StorageUsed: 9, QuotaBytes: 10}).HasQuotaFor(1) {
		t.Fatal("exact quota boundary rejected")
	}
}
