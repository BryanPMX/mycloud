// account-setup creates or verifies one explicitly named account. Passwords are
// read only from stdin, never arguments, environment variables or output.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/mail"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	redisinfra "github.com/yourorg/mycloud/internal/infrastructure/redis"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	if strings.TrimSpace(os.Getenv("DATABASE_URL")) == "" {
		return errors.New("DATABASE_URL must explicitly identify the intended database")
	}
	info, statErr := os.Stdin.Stat()
	if statErr != nil || info.Mode()&os.ModeCharDevice != 0 {
		return errors.New("pipe the password from a hidden prompt; interactive password echo is not allowed")
	}

	email := flag.String("email", "", "Exact account email")
	name := flag.String("name", "", "Display name")
	role := flag.String("role", "member", "Expected role: admin or member")
	quota := flag.Int64("quota-gib", 20, "Quota for a new account; existing quotas are preserved")
	create := flag.Bool("create", false, "Create the named account if it does not already exist")
	reset := flag.Bool("reset-existing-password", false, "Reset only the named active account; API writers must be paused")
	flag.Parse()
	address, err := mail.ParseAddress(strings.TrimSpace(*email))
	if err != nil || address.Address != strings.TrimSpace(*email) || (*role != "admin" && *role != "member") || *quota < 1 || *quota > 1048576 || len(strings.TrimSpace(*name)) == 0 || len(*name) > 100 {
		return errors.New("invalid account parameters; no changes made")
	}
	data, err := io.ReadAll(io.LimitReader(os.Stdin, 1025))
	if err != nil {
		return errors.New("could not read password from stdin")
	}
	password := strings.TrimSuffix(strings.TrimSuffix(string(data), "\n"), "\r")
	if len(password) < 12 || len(password) > 72 {
		return errors.New("password must contain 12–72 bytes; no changes made")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return errors.New("private database configuration is invalid")
	}
	defer db.Close()
	tx, err := db.Begin(ctx)
	if err != nil {
		return errors.New("database unavailable; no changes made")
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext('mycloud-account-management'))`); err != nil {
		return errors.New("account lock unavailable; no changes made")
	}
	var existingID uuid.UUID
	var existingRole, hash string
	var active bool
	var existingQuota int64
	err = tx.QueryRow(ctx, `SELECT id,role,active,password_hash,quota_bytes FROM users WHERE lower(email)=lower($1) FOR UPDATE`, address.Address).Scan(&existingID, &existingRole, &active, &hash, &existingQuota)
	if err == nil {
		if !active || existingRole != *role {
			return errors.New("existing account role/status differs; nothing was overwritten")
		}
		if pkgauth.CheckPassword(hash, password) {
			fmt.Printf("Existing account verified; role=%s quota_bytes=%d. No changes made.\n", existingRole, existingQuota)
			return nil
		}
		if !*reset || os.Getenv("ACCOUNT_SETUP_WRITES_PAUSED") != "yes" {
			return errors.New("existing password differs; reset requires --reset-existing-password and ACCOUNT_SETUP_WRITES_PAUSED=yes")
		}
		client, redisErr := redisinfra.NewClient(os.Getenv("REDIS_URL"))
		if redisErr != nil {
			return errors.New("session store unavailable; password was not reset")
		}
		defer client.Close()
		if redisinfra.NewSessionStore(client).RevokeAllForUser(ctx, existingID) != nil {
			return errors.New("session revocation failed; password was not reset")
		}
		nextHash, hashErr := pkgauth.HashPassword(password)
		if hashErr != nil {
			return errors.New("password hashing failed; password was not reset")
		}
		var versioned bool
		if tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='auth_version')`).Scan(&versioned) != nil {
			return errors.New("schema verification failed; password was not reset")
		}
		query := `UPDATE users SET password_hash=$2,updated_at=now() WHERE id=$1`
		if versioned {
			query = `UPDATE users SET password_hash=$2,auth_version=auth_version+1,updated_at=now() WHERE id=$1`
		}
		if _, err = tx.Exec(ctx, query, existingID, nextHash); err != nil {
			return errors.New("password reset failed; transaction rolled back")
		}
		if err = tx.Commit(ctx); err != nil {
			return errors.New("password reset commit could not be confirmed; verify before retrying")
		}
		fmt.Printf("Named account password reset; role=%s quota_bytes=%d. Identity, quota and media preserved.\n", existingRole, existingQuota)
		return nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return errors.New("account lookup failed; no changes made")
	}
	if !*create {
		return errors.New("account not found; use --create to create this explicitly named account")
	}
	hash, err = pkgauth.HashPassword(password)
	if err != nil {
		return errors.New("password hashing failed; no changes made")
	}
	_, err = tx.Exec(ctx, `INSERT INTO users(id,email,display_name,password_hash,role,quota_bytes,active) VALUES($1,$2,$3,$4,$5,$6,true)`, uuid.New(), strings.ToLower(address.Address), strings.TrimSpace(*name), hash, *role, *quota*(1<<30))
	if err != nil {
		return errors.New("account creation failed; transaction rolled back")
	}
	if err = tx.Commit(ctx); err != nil {
		return errors.New("account commit could not be confirmed; verify before retrying")
	}
	fmt.Printf("Account created; role=%s quota_bytes=%d. Password was not printed.\n", *role, *quota*(1<<30))
	return nil
}
