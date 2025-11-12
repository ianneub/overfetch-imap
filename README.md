# overfetch-imap

[![Tests](https://github.com/ianneub/overfetch-imap/actions/workflows/test.yml/badge.svg)](https://github.com/ianneub/overfetch-imap/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight, containerized IMAP email polling bridge that forwards emails to Rails Action Mailbox. This service continuously monitors an IMAP mailbox and forwards incoming emails to your Rails application's Action Mailbox ingress endpoint.

**For Developers:** See [DEVELOPMENT.md](DEVELOPMENT.md) for build instructions, testing, architecture details, and contributing guidelines.

## What is this?

**overfetch-imap** is a specialized daemon that bridges IMAP email servers with Rails applications. It's NOT a full Rails application—it uses Rails Action Mailbox as a library to enable real-time email ingestion via HTTP.

This project is based on the excellent guide: [Action Mailbox + IMAP/POP3: The Guide I Wish Already Existed](https://medium.com/code-and-coffee/action-mailbox-imap-pop3-the-guide-i-wish-already-existed-cfc641fd4ba4) by Dieter S.

**Key Features:**
- Real-time email forwarding using IMAP IDLE
- Secure SSL/TLS with certificate verification (can be disabled for testing)
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

- Docker
- An IMAP-compatible email server
- A Rails application with Action Mailbox configured
- Network access to both the IMAP server and Rails application

## Quick Start

1. **Create your configuration:**
   ```bash
   mkdir overfetch-imap && cd overfetch-imap
   cat > .env << 'EOF'
   RAILS_MAIL_INBOUND_URL=https://your-rails-app.com/rails/action_mailbox/postfix/inbound_emails
   INGRESS_PASSWORD=your-secret-password
   MAIL_SERVER=imap.example.com
   MAIL_PORT=993
   USERNAME=user@example.com
   PASSWORD=your-imap-password
   KEEP=keep
   EOF
   ```

   Edit `.env` with your actual values (see Configuration section below).

2. **Run the container:**
   ```bash
   docker run -d \
     --name overfetch-imap \
     --env-file .env \
     --restart unless-stopped \
     -v ./storage:/home/fetchmail/storage \
     ghcr.io/ianneub/overfetch-imap:latest
   ```

   The volume mount (`-v ./storage:/home/fetchmail/storage`) ensures email tracking persists between container restarts.

3. **Verify it's working:**
   ```bash
   docker logs -f overfetch-imap
   ```

**Want to build from source?** See [DEVELOPMENT.md](DEVELOPMENT.md) for build instructions.

## Configuration

All configuration is handled via environment variables. Copy [.env.example](.env.example) to `.env` and configure:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `RAILS_MAIL_INBOUND_URL` | Yes | Rails Action Mailbox ingress endpoint URL | `https://example.com/rails/action_mailbox/postfix/inbound_emails` |
| `INGRESS_PASSWORD` | Yes | Authentication password for the ingress endpoint | `your-secret-password` |
| `MAIL_SERVER` | Yes | IMAP server hostname | `imap.example.com` |
| `MAIL_PORT` | Yes | IMAP server port (typically 993 for SSL, 143 for plain) | `993` |
| `USERNAME` | Yes | IMAP account username | `user@example.com` |
| `PASSWORD` | Yes | IMAP account password | `your-password` |
| `KEEP` | No | Set to `keep` to retain emails on server; leave empty to delete after processing | `keep` or empty |
| `DISABLE_SSL` | No | Set to `true` to disable SSL/TLS (**NOT RECOMMENDED for production**) | `true` or empty |

## Using Pre-built Docker Images

Pre-built multi-architecture images are available from GitHub Container Registry (GHCR). These images support both `linux/amd64` and `linux/arm64` platforms.

### Image Location

```
ghcr.io/ianneub/overfetch-imap
```

### Available Tags

| Tag Pattern | Description | Example | When to Use |
|-------------|-------------|---------|-------------|
| `latest` | Latest build from master branch | `ghcr.io/ianneub/overfetch-imap:latest` | Production deployments that want automatic updates |
| `master` | Master branch reference | `ghcr.io/ianneub/overfetch-imap:master` | Testing latest changes |
| `v*.*.*` | Semantic version tags | `ghcr.io/ianneub/overfetch-imap:v1.0.0` | Production deployments requiring version pinning |
| `v*.*` | Major.minor version | `ghcr.io/ianneub/overfetch-imap:v1.0` | Automatic patch updates only |
| `v*` | Major version | `ghcr.io/ianneub/overfetch-imap:v1` | Automatic minor and patch updates |
| `sha-*` | Specific commit SHA | `ghcr.io/ianneub/overfetch-imap:sha-abc1234` | Reproducible builds, debugging |

### Docker Run Example

```bash
docker run -d \
  --name overfetch-imap \
  --restart unless-stopped \
  -v ./storage:/home/fetchmail/storage \
  -e RAILS_MAIL_INBOUND_URL=https://your-rails-app.com/rails/action_mailbox/postfix/inbound_emails \
  -e INGRESS_PASSWORD=your-secret-password \
  -e MAIL_SERVER=imap.example.com \
  -e MAIL_PORT=993 \
  -e USERNAME=user@example.com \
  -e PASSWORD=your-imap-password \
  -e KEEP=keep \
  ghcr.io/ianneub/overfetch-imap:latest
```

### Pulling Updates

To update to the latest image:

```bash
docker pull ghcr.io/ianneub/overfetch-imap:latest
docker stop overfetch-imap
docker rm overfetch-imap
# Re-run your docker run command
```

## Usage

### Managing the Service

**View logs:**
```bash
docker logs -f overfetch-imap
```

**Stop the service:**
```bash
docker stop overfetch-imap
```

**Start the service:**
```bash
docker start overfetch-imap
```

**Restart the service:**
```bash
docker restart overfetch-imap
```

**Remove the container:**
```bash
docker stop overfetch-imap
docker rm overfetch-imap
```

**Shell access for debugging:**
```bash
docker exec -it overfetch-imap bash
```

### Testing Email Ingestion

You can test the Rails ingress endpoint manually:

1. Create a test email file (`test_email.eml`):

   ```text
   From: sender@example.com
   To: recipient@example.com
   Subject: Test Email

   This is a test email body.
   ```

2. Send it to your Rails endpoint:

   ```bash
   docker exec overfetch-imap bash -c \
     "bundle exec rake action_mailbox:ingress:postfix \
     URL=\$RAILS_MAIL_INBOUND_URL \
     INGRESS_PASSWORD=\$INGRESS_PASSWORD < test_email.eml"
   ```

### Health Check

Check if the container is healthy:

```bash
docker ps  # Check the STATUS column for "healthy"
```

Or inspect the health check status:

```bash
docker inspect --format='{{.State.Health.Status}}' overfetch-imap
```

## Troubleshooting

### Service Won't Start

**Check container logs:**
```bash
docker logs overfetch-imap
```

Common issues:

- Missing required environment variables
- Incorrect `RAILS_MAIL_INBOUND_URL` format
- `MAIL_SERVER` hostname not resolvable

### Emails Not Being Received

1. **Check container logs:**

   ```bash
   docker logs -f overfetch-imap
   ```

2. **Verify IMAP credentials:**

   ```bash
   # Test IMAP connection manually
   docker exec -it overfetch-imap bash
   fetchmail -v --nodetach
   ```

3. **Check common issues:**

   - Wrong `USERNAME` or `PASSWORD`
   - Incorrect `MAIL_PORT` (should be 993 for SSL/TLS)
   - IMAP server doesn't support SSL/TLS
   - Firewall blocking outbound connection to IMAP server

4. **Verify Rails endpoint:**

   - Check Rails application logs
   - Confirm ingress endpoint is accessible
   - Verify `INGRESS_PASSWORD` matches Rails configuration

### Emails Being Duplicated

If emails are processed multiple times, the stateful tracking may not be working:

1. **Check for fetchmail.id file:**

   ```bash
   docker exec overfetch-imap ls -la storage/
   # Should see fetchmail.id file
   ```

2. **Verify volume persistence:**

   The container needs a volume mounted for the `storage/` directory to persist the `fetchmail.id` file between restarts. Add `-v ./storage:/home/fetchmail/storage` to your `docker run` command.

### Health Check Failing

```bash
# Check container health status
docker ps

# View detailed logs
docker logs overfetch-imap

# Manually check if fetchmail is running
docker exec overfetch-imap pgrep -f "fetchmail -d"
```

### SSL/TLS Certificate Errors

The service enforces certificate verification by default:

- Verify your IMAP server has a valid SSL certificate
- Check that `ca-certificates` are up-to-date in the container
- Review fetchmail logs for specific SSL errors: `docker logs overfetch-imap`

**For testing with self-signed certificates or insecure connections:**

You can disable SSL by setting `DISABLE_SSL=true` in your environment:

```bash
docker run -d \
  --name overfetch-imap \
  --env-file .env \
  -e DISABLE_SSL=true \
  --restart unless-stopped \
  -v ./storage:/home/fetchmail/storage \
  ghcr.io/ianneub/overfetch-imap:latest
```

⚠️ **WARNING**: Disabling SSL transmits credentials and email content in plain text. Only use this for local development or testing with trusted networks. Never disable SSL in production environments.

### Performance Issues

- Jemalloc is pre-loaded for memory optimization
- Check Docker resource limits if container is slow
- Review Rails application ingress endpoint performance
- Monitor container resource usage: `docker stats overfetch-imap`

**For advanced debugging and technical details, see [DEVELOPMENT.md](DEVELOPMENT.md).**

## Resources

- **Original Guide**: [Action Mailbox + IMAP/POP3: The Guide I Wish Already Existed](https://medium.com/code-and-coffee/action-mailbox-imap-pop3-the-guide-i-wish-already-existed-cfc641fd4ba4) - This project implements the approach described in this excellent guide, providing a production-ready, containerized solution
- [Rails Action Mailbox Documentation](https://guides.rubyonrails.org/action_mailbox_basics.html)
- [Fetchmail Documentation](http://www.fetchmail.info/)
- [Docker Documentation](https://docs.docker.com/)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please see [DEVELOPMENT.md](DEVELOPMENT.md) for development setup, testing, and contribution guidelines.
