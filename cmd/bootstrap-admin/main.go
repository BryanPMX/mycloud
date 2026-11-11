// bootstrap-admin provisions only an empty installation. It never changes an
// existing account and never accepts a password in process arguments.
package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
	"io"
	"net/mail"
	"os"
	"strings"
	"time"
)

func main() {
	if run() != nil {
		fmt.Fprintln(os.Stderr, "Bootstrap refused or failed. It requires an empty, migrated installation, a valid email, and an 8–72 byte password through stdin.")
		os.Exit(1)
	}
}
func run() error {
	email := flag.String("email", "", "First administrator email")
	stdin := flag.Bool("password-stdin", false, "Read password from stdin; never pass it as an argument")
	confirm := flag.Bool("confirm-empty-installation", false, "Acknowledge this provisions only a new empty installation")
	flag.Parse()
	value := strings.ToLower(strings.TrimSpace(*email))
	parsed, err := mail.ParseAddress(value)
	if err != nil || parsed.Address != value || len(value) > 254 || !*stdin || !*confirm {
		return fmt.Errorf("invalid bootstrap arguments")
	}
	if info, err := os.Stdin.Stat(); err != nil || info.Mode()&os.ModeCharDevice != 0 {
		return fmt.Errorf("pipe the password from a secure prompt")
	}
	password, err := io.ReadAll(io.LimitReader(os.Stdin, 74))
	if err != nil {
		return err
	}
	password = []byte(strings.TrimSuffix(string(password), "\n"))
	if len(password) > 72 {
		return fmt.Errorf("password too long")
	}
	hash, err := pkgauth.HashPassword(string(password))
	for i := range password {
		password[i] = 0
	}
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	tx, err := db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(684306103)`); err != nil {
		return err
	}
	var count int
	if err = tx.QueryRow(ctx, `SELECT count(*) FROM users`).Scan(&count); err != nil {
		return err
	}
	if count != 0 {
		return fmt.Errorf("installation is not empty")
	}
	user, family := uuid.New(), uuid.New()
	if _, err = tx.Exec(ctx, `INSERT INTO users(id,email,display_name,password_hash,role) VALUES($1,$2,'Family administrator',$3,'admin')`, user, value, hash); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO families(id,name,owner_id,legacy) VALUES($1,'Our family',$2,true)`, family, user); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO family_memberships(family_id,user_id,role) VALUES($1,$2,'owner')`, family, user); err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	fmt.Println("First administrator and private family created. Sign in to invite your family.")
	return nil
}
