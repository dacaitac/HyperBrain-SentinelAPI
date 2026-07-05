# HyperBrain-SentinelAPI

Swift/Vapor service running natively on **Mac Mini M4 Pro** that bridges Apple EventKit
(iCloud Reminders / Calendar) with HyperBrain Core via AWS SQS.

## Role

SentinelAPI is the only component in the HyperBrain ecosystem with access to Apple's native
EventKit APIs. It:

- **Publishes** `AppleEntityChangedEvent` messages to `sync-events.fifo` when Reminders or
  Calendar events change.
- **Consumes** write commands (`WriteReminderCommand`, `WriteCalendarEventCommand`) from SQS
  and applies them via EventKit.
- **Exposes** a REST API (Vapor) for health checks, snapshot inspection, and smoke testing.

Replaces legacy `sentinel-daemon` + `reminder-api` daemons.

## Documentation

- [SentinelAPI Architecture](https://github.com/dacaitac/HyperBrain-docs/blob/main/docs/02-architecture/engines/eventsentinel.md)
- [TD-03 Implementation Issue](https://github.com/dacaitac/HyperBrain-docs/issues/21)
- [HU-09 iOS Sync](https://github.com/dacaitac/HyperBrain-docs/issues/14)

## Requirements

- macOS 14+, Swift 6
- AWS credentials for `event-sentinel-api-sqs` IAM user
- Tailscale for network access from Core

## Development

```bash
swift build
swift test
```

See `CLAUDE.md` for full AI assistant context and coding conventions.
