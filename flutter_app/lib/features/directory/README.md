# `flutter_app/lib/features/directory`

This feature owns the non-admin family directory plus the signed-avatar cache that is keyed by `user_id`.

Current slice on March 15, 2026:
- `GET /users/directory` now hydrates recipient picking for album sharing without relying on admin-only user listing
- signed `avatar_url` values from `/users/me`, `/users/directory`, comments, and album shares are cached by `user_id`
- when a cached avatar URL expires or fails, Flutter refreshes it through `GET /users/:id/avatar`
