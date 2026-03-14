# `internal/delivery/ws`

WebSocket delivery code lives here.

The current slice owns the authenticated `/ws/progress` hub, message serialization, the RFC 6455 upgrade path, and per-user fanout of worker progress events delivered through Redis pub/sub.
