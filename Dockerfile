# Dockerfile
# credit: https://medium.com/code-and-coffee/action-mailbox-imap-pop3-the-guide-i-wish-already-existed-cfc641fd4ba4
ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:${RUBY_VERSION}-slim

ENV BUNDLE_DEPLOYMENT=1 \
  BUNDLE_PATH=/usr/local/bundle \
  BUNDLE_WITHOUT=development:test \
  LC_ALL=C.UTF-8

RUN set -eux; \
  apt-get update -qq; \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  ca-certificates \
  curl \
  fetchmail \
  libjemalloc2 \
  build-essential \
  git procps \
  libyaml-dev \
  pkg-config; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; mkdir -p /rails/tmp/pids /rails/log /rails/storage
WORKDIR /rails

# Install gems first for better layer caching
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
  rm -rf ~/.bundle "$BUNDLE_PATH"/ruby/*/cache "$BUNDLE_PATH"/ruby/*/bundler/gems/*/.git

# Create unprivileged user
RUN groupadd --system --gid 1500 rails && \
  useradd rails --uid 1500 --gid 1500 --create-home --shell /bin/bash && \
  chown -R rails:rails /rails
USER 1500:1500

# App files (Rakefile, config, scripts)
COPY . .

# Healthcheck: ensure fetchmail is alive in daemon mode
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD pgrep -f "fetchmail -d" || exit 1

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
