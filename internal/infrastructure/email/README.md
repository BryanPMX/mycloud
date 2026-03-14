# `internal/infrastructure/email`

Email delivery adapters live here.

Keep transport logic here and message bodies in `templates/`.

The current SMTP sender renders the invite email template and delivers admin invites when `SMTP_HOST` and `SMTP_FROM` are configured.
