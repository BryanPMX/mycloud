# FamilyCloud

This repository currently contains the design set plus a minimal implementation scaffold for FamilyCloud.

Use the numbered design docs for the full system specification:
- [00-README.md](/Users/bryanpmx/Documents/Projects/mycloud/00-README.md) for the document index
- [09-subsystems-file-architecture.md](/Users/bryanpmx/Documents/Projects/mycloud/09-subsystems-file-architecture.md) for the canonical implementation layout

Implementation work starts in these main subsystems:
- `cmd/` for process entry points
- `internal/` for backend application code
- `pkg/` for reusable helper packages
- `flutter_app/` for the client app
- `migrations/` for schema changes
- `nginx/`, `monitoring/`, and `scripts/` for operations
- `testdata/` for shared fixtures
