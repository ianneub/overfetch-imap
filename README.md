# overfetch-imap

A lightweight, containerized IMAP email polling bridge that forwards emails to Rails Action Mailbox. This service continuously monitors an IMAP mailbox and forwards incoming emails to your Rails application's Action Mailbox ingress endpoint.

## What is this?

**overfetch-imap** is a specialized daemon that bridges IMAP email servers with Rails applications. It's NOT a full Rails application—it uses Rails Action Mailbox as a library to enable real-time email ingestion via HTTP.

**Key Features:**
- Real-time email forwarding using IMAP IDLE
- Secure SSL/TLS with certificate verification
- Stateful processing to prevent duplicate emails
- Docker-based deployment with health checks
- Configurable email retention (keep or delete after processing)
- Runs as unprivileged user with security hardening

## How It Works

```
IMAP Server → Fetchmail (IDLE) → Rake Task → Rails Action Mailbox HTTP Endpoint
```

1. Fetchmail connects to your IMAP server using IDLE protocol for real-time delivery
2. When an email arrives, fetchmail pipes it to a rake task (MDA)
3. The rake task POSTs the email to your Rails Action Mailbox ingress endpoint
4. Emails are kept or deleted based on the `KEEP` configuration

## Prerequisites

- Docker and Docker Compose
- An IMAP-compatible email server
- A Rails application with Action Mailbox configured
- Network access to both the IMAP server and Rails application

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd overfetch-imap
   ```

2. **Create your configuration:**
   ```bash
   cp .env.example .env
   ```

   Edit `.env` with your actual values (see Configuration section below).

3. **Build and run:**
   ```bash
   docker compose build
   docker compose up
   ```

4. **Verify it's working:**
   ```bash
   docker compose logs -f overfetch-imap
   ```

## Configuration

All configuration is handled via environment variables. Copy [.env.example](.env.example) to `.env` and configure:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `URL` or `RAILS_MAIL_INBOUND_URL` | Yes | Rails Action Mailbox ingress endpoint URL | `https://example.com/rails/action_mailbox/postfix/inbound_emails` |
| `INGRESS_PASSWORD` | Yes | Authentication password for the ingress endpoint | `your-secret-password` |
| `MAIL_SERVER` | Yes | IMAP server hostname | `imap.example.com` |
| `MAIL_PORT` | Yes | IMAP server port (typically 993 for SSL) | `993` |
| `USERNAME` | Yes | IMAP account username | `user@example.com` |
| `PASSWORD` | Yes | IMAP account password | `your-password` |
| `KEEP` | No | Set to `keep` to retain emails on server; leave empty to delete after processing | `keep` or empty |

**Note:** Both `URL` and `RAILS_MAIL_INBOUND_URL` work interchangeably.

## Usage

### Running the Service

**Start in foreground:**
```bash
docker compose up
```

**Start in background (detached mode):**
```bash
docker compose up -d
```

**View logs:**
```bash
docker compose logs -f overfetch-imap
```

**Stop the service:**
```bash
docker compose down
```

**Shell access for debugging:**
```bash
docker compose exec overfetch-imap bash
```

### Testing Email Ingestion

Test the Rails ingress endpoint without running the full fetchmail daemon:

```bash
docker compose exec overfetch-imap bash -c \
  "bundle exec rake action_mailbox:ingress:postfix \
  URL=\$RAILS_MAIL_INBOUND_URL \
  INGRESS_PASSWORD=\$INGRESS_PASSWORD < test_email.eml"
```

Create a test email file (`test_email.eml`):
```
From: sender@example.com
To: recipient@example.com
Subject: Test Email

This is a test email body.
```

### Health Check

The service includes a built-in health check that verifies fetchmail is running:

```bash
docker compose ps  # Should show "healthy" status
```

## Architecture

### Email Flow Details

1. **Container Startup**: [bin/docker-entrypoint](bin/docker-entrypoint) runs with security hardening
2. **Configuration Generation**: Dynamically creates `~/.fetchmailrc` from environment variables
3. **Fetchmail Daemon**: Launches in daemon mode with IDLE support
4. **Email Reception**: IDLE protocol detects emails immediately (no polling delay)
5. **Rails Ingestion**: Pipes email to `bundle exec rake action_mailbox:ingress:postfix`
6. **HTTP Forward**: Rake task POSTs email to your Rails ingress endpoint
7. **Message Handling**: Keeps or deletes email based on `KEEP` variable

### Stateful Operation

The service uses `storage/fetchmail.id` to track processed emails and prevent duplicates. This file persists between container restarts via Docker volumes.

### Security Features

- Runs as unprivileged user (UID/GID 1500)
- SSL/TLS enforced with certificate verification
- Restrictive file permissions (umask 077)
- Jemalloc preloaded for memory safety
- No root access inside container

## Project Structure

| File/Directory | Purpose |
|----------------|---------|
| [bin/docker-entrypoint](bin/docker-entrypoint) | Container startup script; generates fetchmail config at runtime |
| [Dockerfile](Dockerfile) | Multi-stage build with security hardening and health checks |
| [docker-compose.yml](docker-compose.yml) | Service definition with environment and volume configuration |
| [Rakefile](Rakefile) | Loads Action Mailbox rake tasks (no custom Ruby code) |
| [Gemfile](Gemfile) / [Gemfile.lock](Gemfile.lock) | Ruby dependencies (Action Mailbox, Rake, Base64) |
| [.env.example](.env.example) | Template for environment variables |
| [storage/](storage/) | Persistent directory for fetchmail state (`fetchmail.id`) |
| [CLAUDE.md](CLAUDE.md) | Developer documentation for AI assistants |

## Troubleshooting

### Service Won't Start

**Check environment variables:**
```bash
docker compose config  # Validates and shows merged configuration
```

Common issues:
- Missing required environment variables in `.env`
- Incorrect `RAILS_MAIL_INBOUND_URL` format
- `MAIL_SERVER` hostname not resolvable

### Emails Not Being Received

1. **Verify IMAP credentials:**
   ```bash
   # Test IMAP connection manually
   docker compose exec overfetch-imap bash
   fetchmail -v --nodetach
   ```

2. **Check common issues:**
   - Wrong `USERNAME` or `PASSWORD`
   - Incorrect `MAIL_PORT` (should be 993 for SSL/TLS)
   - IMAP server doesn't support SSL/TLS
   - Firewall blocking outbound connection to IMAP server

3. **Verify Rails endpoint:**
   - Check Rails application logs
   - Confirm ingress endpoint is accessible
   - Verify `INGRESS_PASSWORD` matches Rails configuration

### Emails Being Duplicated

If emails are processed multiple times:

1. **Check persistent storage:**
   ```bash
   docker compose exec overfetch-imap ls -la storage/
   # Should see fetchmail.id file
   ```

2. **Verify volume persistence:**
   - Ensure `storage/` volume is properly mounted
   - Check `docker-compose.yml` volume configuration

### Health Check Failing

```bash
# Check container status
docker compose ps

# View detailed logs
docker compose logs overfetch-imap

# Manually check if fetchmail is running
docker compose exec overfetch-imap pgrep -f "fetchmail -d"
```

### SSL/TLS Certificate Errors

The service enforces certificate verification by default:

- Verify your IMAP server has a valid SSL certificate
- Check that `ca-certificates` are up-to-date in the container
- Review fetchmail logs for specific SSL errors

### Performance Issues

- Jemalloc is pre-loaded for memory optimization
- Check Docker resource limits if container is slow
- Review Rails application ingress endpoint performance
- Monitor container resource usage: `docker stats overfetch-imap`

## Advanced Usage

### Custom Fetchmail Arguments

The entrypoint supports passing custom arguments:

```bash
docker compose run overfetch-imap fetchmail --help
docker compose run overfetch-imap fetchmail -v  # Verbose mode
```

### Viewing Generated Configuration

```bash
docker compose exec overfetch-imap cat ~/.fetchmailrc
```

### Debugging

Run a shell inside the container:

```bash
docker compose exec overfetch-imap bash

# Inside container:
ps aux                    # View running processes
cat ~/.fetchmailrc       # View fetchmail config
ls -la storage/          # Check state files
```

## Technical Details

### Key Implementation Notes

1. **No Custom Ruby Code**: This repository contains no custom Ruby implementation. All functionality comes from:
   - Fetchmail configuration (dynamically generated)
   - Action Mailbox's built-in Postfix ingress format
   - Docker entrypoint orchestration

2. **IDLE Protocol**: Uses IMAP IDLE for real-time email delivery instead of polling intervals, enabling immediate forwarding.

3. **Stateful Tracking**: The `storage/fetchmail.id` file maintains server state to prevent duplicate ingestion.

### Technology Stack

- **Ruby**: 3.4.4
- **Rails Action Mailbox**: ~8.1
- **Fetchmail**: System-installed via apt
- **Base Image**: ruby:3.4.4-slim

## Resources

- **Inspiration**: Based on [Action Mailbox + IMAP/POP3: The Guide I Wish Already Existed](https://medium.com/code-and-coffee/action-mailbox-imap-pop3-the-guide-i-wish-already-existed-cfc641fd4ba4)
- [Rails Action Mailbox Documentation](https://guides.rubyonrails.org/action_mailbox_basics.html)
- [Fetchmail Documentation](http://www.fetchmail.info/)
- [Docker Documentation](https://docs.docker.com/)

## License

[Add your license information here]

## Contributing

[Add contribution guidelines here]
