# Development Guide

This guide is for developers who want to contribute to overfetch-imap or build from source.

For user-focused documentation, see the main [README.md](README.md).

## Table of Contents

- [Building from Source](#building-from-source)
- [Testing](#testing)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Advanced Usage](#advanced-usage)
- [Technical Details](#technical-details)
- [Contributing](#contributing)

## Building from Source

If you want to build the Docker image yourself or contribute to the project:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ianneub/overfetch-imap.git
   cd overfetch-imap
   ```

2. **Create your configuration:**
   ```bash
   cp .env.example .env
   ```

   Edit `.env` with your actual values (see Configuration section in [README.md](README.md)).

3. **Build and run using Docker Compose:**
   ```bash
   docker compose build
   docker compose up
   ```

4. **Verify it's working:**
   ```bash
   docker compose logs -f overfetch-imap
   ```

### Using Docker Compose with Pre-built Image

If you have the source code but want to use the pre-built GHCR image, the included `docker-compose.yml` builds from source by default. You can override this:

1. **Create a `docker-compose.override.yml` file:**
   ```yaml
   services:
     overfetch-imap:
       image: ghcr.io/ianneub/overfetch-imap:latest
       build: null
   ```

2. **Or use this standalone Docker Compose file:**
   ```yaml
   services:
     overfetch-imap:
       image: ghcr.io/ianneub/overfetch-imap:latest
       container_name: overfetch-imap
       restart: unless-stopped
       env_file: .env
       environment:
         KEEP: keep
       volumes:
         - ./storage:/home/fetchmail/storage
       healthcheck:
         test: ["CMD", "pgrep", "-f", "fetchmail"]
         interval: 30s
         timeout: 10s
         retries: 3
         start_period: 10s
   ```

3. **Run with:**
   ```bash
   docker compose up -d
   ```

### Docker Compose Commands

**Start in foreground:**
```bash
docker compose up
```

**Start in background:**
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

**Rebuild after changes:**
```bash
docker compose build
docker compose up -d
```

**Pull latest image (if using GHCR):**
```bash
docker compose pull
docker compose up -d
```

**Shell access:**
```bash
docker compose exec overfetch-imap bash
```

## Testing

This project includes a comprehensive test suite for the bash entrypoint script using BATS (Bash Automated Testing System).

### Installing BATS

**macOS (Homebrew):**
```bash
brew install bats-core
```

**Ubuntu/Debian:**
```bash
sudo apt-get install bats
```

**Manual installation:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Running Tests

**Run all tests:**
```bash
bats test/entrypoint.bats
```

**Run tests with verbose output:**
```bash
bats test/entrypoint.bats --tap
```

**Run specific test:**
```bash
bats test/entrypoint.bats --filter "generates fetchmailrc"
```

### Test Coverage

The test suite covers:
- ✅ Fetchmailrc generation with valid environment variables
- ✅ Missing required environment variables (fail gracefully)
- ✅ Special character escaping (passwords with quotes, $, backticks)
- ✅ KEEP variable behavior (present vs absent)
- ✅ File permissions (umask 077 enforcement)
- ✅ Jemalloc LD_PRELOAD detection
- ✅ Command dispatch logic (default, fetchmail, flags, custom commands)
- ✅ Idempotency (doesn't regenerate existing .fetchmailrc)
- ✅ Error handling (set -euo pipefail validation)

**Total test cases:** ~40 tests covering all critical paths in [bin/docker-entrypoint](bin/docker-entrypoint)

### Test Structure

```
test/
├── entrypoint.bats          # Main test suite
├── test_helper.bash         # Shared setup/teardown functions
└── fixtures/
    └── .env.test            # Sample test environment variables
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
| [test/](test/) | BATS test suite for entrypoint script |
| [CLAUDE.md](CLAUDE.md) | Developer documentation for AI assistants |
| [README.md](README.md) | User-focused documentation |
| [DEVELOPMENT.md](DEVELOPMENT.md) | This file - developer documentation |

## Advanced Usage

### Custom Fetchmail Arguments

The entrypoint supports passing custom arguments.

**With Docker Compose:**
```bash
docker compose run overfetch-imap fetchmail --help
docker compose run overfetch-imap fetchmail -v  # Verbose mode
```

**With Docker:**
```bash
docker run --rm --env-file .env ghcr.io/ianneub/overfetch-imap:latest fetchmail --help
```

### Viewing Generated Configuration

**With Docker Compose:**
```bash
docker compose exec overfetch-imap cat ~/.fetchmailrc
```

**With Docker:**
```bash
docker exec overfetch-imap cat ~/.fetchmailrc
```

### Debugging

Run a shell inside the container.

**With Docker Compose:**
```bash
docker compose exec overfetch-imap bash
```

**With Docker:**
```bash
docker exec -it overfetch-imap bash
```

Inside the container, useful commands:
```bash
ps aux                    # View running processes
cat ~/.fetchmailrc       # View fetchmail config
ls -la storage/          # Check state files
fetchmail -v --nodetach  # Run fetchmail in verbose mode
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

### Working with AI Assistants

See [CLAUDE.md](CLAUDE.md) for guidance when using Claude Code or other AI assistants to work on this project.

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run the test suite to ensure nothing breaks (`bats test/entrypoint.bats`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Workflow

1. Make changes to the code
2. Build the Docker image: `docker compose build`
3. Run tests: `bats test/entrypoint.bats`
4. Test manually with: `docker compose up`
5. Check logs: `docker compose logs -f`

### Code Style

- Shell scripts should follow Google Shell Style Guide
- Use `shellcheck` for linting bash scripts
- Maintain test coverage for new functionality

### Reporting Issues

Please report issues on the [GitHub issue tracker](https://github.com/ianneub/overfetch-imap/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
