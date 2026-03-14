package email

import (
	"bytes"
	"context"
	_ "embed"
	"fmt"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"strings"
	"text/template"
	"time"

	"github.com/yourorg/mycloud/internal/domain"
)

//go:embed templates/invite_email.tmpl
var inviteEmailTemplate string

type SMTPSender struct {
	appName    string
	host       string
	port       int
	user       string
	pass       string
	from       *mail.Address
	inviteTmpl *template.Template
}

func NewSMTPSender(appName, host string, port int, user, pass, from string) (*SMTPSender, error) {
	host = strings.TrimSpace(host)
	from = strings.TrimSpace(from)
	if host == "" || from == "" {
		return nil, nil
	}
	if port <= 0 {
		return nil, fmt.Errorf("smtp port must be positive")
	}

	fromAddr, err := mail.ParseAddress(from)
	if err != nil {
		return nil, fmt.Errorf("parse SMTP_FROM: %w", err)
	}

	tmpl, err := template.New("invite_email").Parse(inviteEmailTemplate)
	if err != nil {
		return nil, fmt.Errorf("parse invite email template: %w", err)
	}

	return &SMTPSender{
		appName:    strings.TrimSpace(appName),
		host:       host,
		port:       port,
		user:       strings.TrimSpace(user),
		pass:       pass,
		from:       fromAddr,
		inviteTmpl: tmpl,
	}, nil
}

func (s *SMTPSender) SendInviteEmail(ctx context.Context, invite domain.InviteEmail) error {
	if s == nil {
		return nil
	}
	if err := ctx.Err(); err != nil {
		return err
	}

	toAddr, err := mail.ParseAddress(strings.TrimSpace(invite.To))
	if err != nil {
		return fmt.Errorf("parse invite recipient: %w", err)
	}

	body, err := s.renderInviteBody(invite)
	if err != nil {
		return err
	}

	msg := buildPlainTextMessage(messageHeaders{
		From:    s.from.String(),
		To:      toAddr.String(),
		Subject: fmt.Sprintf("%s invite", s.appNameOrDefault(invite.AppName)),
		Date:    time.Now().UTC(),
	}, body)

	addr := net.JoinHostPort(s.host, fmt.Sprintf("%d", s.port))
	var auth smtp.Auth
	if s.user != "" || s.pass != "" {
		auth = smtp.PlainAuth("", s.user, s.pass, s.host)
	}

	if err := smtp.SendMail(addr, auth, s.from.Address, []string{toAddr.Address}, msg); err != nil {
		return fmt.Errorf("send invite email: %w", err)
	}

	return nil
}

type inviteTemplateData struct {
	AppName      string
	DisplayName  string
	InviteURL    string
	ExpiresAt    string
	SupportEmail string
}

func (s *SMTPSender) renderInviteBody(invite domain.InviteEmail) ([]byte, error) {
	displayName := strings.TrimSpace(invite.DisplayName)
	if displayName == "" {
		displayName = "there"
	}

	data := inviteTemplateData{
		AppName:      s.appNameOrDefault(invite.AppName),
		DisplayName:  displayName,
		InviteURL:    strings.TrimSpace(invite.InviteURL),
		ExpiresAt:    invite.ExpiresAt.UTC().Format(time.RFC1123),
		SupportEmail: s.from.Address,
	}

	var body bytes.Buffer
	if err := s.inviteTmpl.Execute(&body, data); err != nil {
		return nil, fmt.Errorf("render invite email: %w", err)
	}

	return body.Bytes(), nil
}

func (s *SMTPSender) appNameOrDefault(value string) string {
	if trimmed := strings.TrimSpace(value); trimmed != "" {
		return trimmed
	}
	if trimmed := strings.TrimSpace(s.appName); trimmed != "" {
		return trimmed
	}
	return "MyCloud"
}

type messageHeaders struct {
	From    string
	To      string
	Subject string
	Date    time.Time
}

func buildPlainTextMessage(headers messageHeaders, body []byte) []byte {
	subject := mime.QEncoding.Encode("utf-8", strings.TrimSpace(headers.Subject))
	message := bytes.NewBuffer(nil)
	fmt.Fprintf(message, "From: %s\r\n", headers.From)
	fmt.Fprintf(message, "To: %s\r\n", headers.To)
	fmt.Fprintf(message, "Subject: %s\r\n", subject)
	fmt.Fprintf(message, "Date: %s\r\n", headers.Date.UTC().Format(time.RFC1123Z))
	fmt.Fprintf(message, "MIME-Version: 1.0\r\n")
	fmt.Fprintf(message, "Content-Type: text/plain; charset=UTF-8\r\n")
	fmt.Fprintf(message, "Content-Transfer-Encoding: 8bit\r\n")
	fmt.Fprintf(message, "\r\n")
	message.Write(bytes.ReplaceAll(body, []byte("\n"), []byte("\r\n")))
	if !bytes.HasSuffix(message.Bytes(), []byte("\r\n")) {
		message.WriteString("\r\n")
	}
	return message.Bytes()
}
