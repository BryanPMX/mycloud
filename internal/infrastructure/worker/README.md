# `internal/infrastructure/worker`

Media-processing runtime components live here.

The current slice handles queue polling, staged upload scanning, promotion into permanent storage, and final media row updates.

Keep future processor registration and image/video-specific implementations in this directory as the media pipeline grows.
