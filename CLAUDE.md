# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**overfetch-imap** is an IMAP email polling bridge service that forwards emails to Rails Action Mailbox. This is NOT a full Rails application - it's a containerized fetchmail daemon that uses Action Mailbox as a library to forward emails via HTTP to a Rails application's ingress endpoint.

**Tech Stack:**
- Ruby 3.4.4
- Rails Action Mailbox 8.1.1 (library only)
- Fetchmail (IMAP polling daemon)
- Docker & Docker Compose

## Development Commands

### Docker Operations
```bash
# Build the Docker image
docker compose build

# Run the service
docker compose up

# View logs
docker compose logs -f

# Shell access
docker compose exec overfetch-imap bash

# Stop service
docker compose down
```

### Manual Testing
Test email ingress without running the full fetchmail daemon:
```bash
bundle exec rake action_mailbox:ingress:postfix URL=$URL INGRESS_PASSWORD=$INGRESS_PASSWORD < email.eml
```

This simulates what fetchmail does when it receives an email.

## Architecture

### Email Flow
```
IMAP Server → Fetchmail (IDLE polling) → Rake Task (MDA) → Rails Action Mailbox HTTP Endpoint
```

### How It Works
1. Container starts via [bin/docker-entrypoint](bin/docker-entrypoint)
2. Entrypoint generates `~/.fetchmailrc` from environment variables
3. Fetchmail runs in daemon mode (`--nodetach`) with IDLE support for real-time delivery
4. When email arrives, fetchmail pipes it to the MDA command: `action_mailbox:ingress:postfix`
5. The rake task POSTs the email to the configured Rails Action Mailbox ingress URL
6. Emails are kept or deleted based on `KEEP` environment variable

### Key Implementation Details

**This repository contains NO custom Ruby code.** The [Rakefile](Rakefile) only loads Action Mailbox's rake tasks. All functionality comes from:
- Fetchmail configuration (generated at runtime)
- Action Mailbox's built-in Postfix ingress format
- Docker entrypoint orchestration

**Stateful Service:** Uses `storage/fetchmail.id` to track processed emails and prevent duplicates.

**Security Hardening:**
- Runs as unprivileged user (UID/GID 1500)
- SSL/TLS enforced with certificate verification
- Restrictive file permissions (umask 077)
- Jemalloc preloaded for memory safety

## Configuration

All behavior is controlled via environment variables. See [.env.example](.env.example) for the full list.

**Critical Variables:**
- `URL` or `RAILS_MAIL_INBOUND_URL` - Rails Action Mailbox ingress endpoint
- `INGRESS_PASSWORD` - Authentication password for the ingress endpoint
- `MAIL_SERVER`, `MAIL_PORT` - IMAP server connection details
- `USERNAME`, `PASSWORD` - IMAP credentials
- `KEEP` - Set to "keep" to retain emails on server, empty/unset to delete after processing

## Important Files

- [bin/docker-entrypoint](bin/docker-entrypoint) - Container startup script; generates fetchmail config from env vars
- [Dockerfile](Dockerfile) - Multi-stage build with security hardening and health checks
- [docker-compose.yml](docker-compose.yml) - Service definition with volume mounts for testing
- [Rakefile](Rakefile) - Loads Action Mailbox rake tasks (no custom code)
- [storage/](storage/) - Persistent directory for fetchmail state

## Testing Without Live IMAP

Uncomment the volume mount in [docker-compose.yml](docker-compose.yml) to inject a test email:
```yaml
volumes:
  - ./custom.eml:/home/fetchmail/custom.eml
```

Then manually invoke the rake task as shown in Development Commands above.
