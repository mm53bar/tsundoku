# Production image for Tsundoku.
#
# Built and published by .github/workflows/build.yml on every push to main:
#   ghcr.io/mm53bar/tsundoku:latest         (moves with main)
#   ghcr.io/mm53bar/tsundoku:<short-sha>    (immutable per commit)
#
# The image is host-agnostic — the runtime UID/GID comes from the
# `user:` directive in compose.yaml so the same image can run on any
# host whose bind-mounted dirs are owned by that UID/GID.

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.7

FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# kepubify — converts EPUB → KEPUB for higher-fidelity reading-progress on
# Kobo devices. Single static Go binary, ~6MB. amd64-only for now since
# that's the only architecture the build workflow targets.
ARG KEPUBIFY_VERSION=4.0.4
RUN curl -fsSL -o /usr/local/bin/kepubify \
      "https://github.com/pgaskin/kepubify/releases/download/v${KEPUBIFY_VERSION}/kepubify-linux-64bit" && \
    chmod +x /usr/local/bin/kepubify && \
    /usr/local/bin/kepubify --version

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    HTTP_PORT="8080" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Capture the git commit SHA so the running app can show which build it's
# serving. .git is removed afterwards so it doesn't ride along into the
# final image (which only does COPY --from=build).
RUN if [ -d .git ]; then \
      git rev-parse HEAD > REVISION && \
      git rev-parse --short HEAD > REVISION_SHORT; \
    else \
      echo "unknown" > REVISION && echo "unknown" > REVISION_SHORT; \
    fi && \
    rm -rf .git

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Make tmp/log world-writable so whichever UID the compose `user:` directive
# selects can write pidfiles, sockets, and logs. Persistent data (the SQLite
# DBs) lives in /rails/storage which is a bind mount owned by the host UID.
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
    chmod -R 0777 tmp log

# Non-root runtime users have no writable HOME (it defaults to /), so Bundler
# falls back to a temp dir and logs a warning on every command. Point HOME at
# the world-writable tmp dir to keep that noise out of the logs.
ENV HOME="/rails/tmp"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime.
# Thruster listens on HTTP_PORT (default 8080, set above); EXPOSE is documentation.
EXPOSE 8080
CMD ["./bin/thrust", "./bin/rails", "server"]
