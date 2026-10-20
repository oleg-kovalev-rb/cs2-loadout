# syntax = docker/dockerfile:1

# Production image for app_core, built by Kamal. Local development and CI
# use Dockerfile.dev through docker-compose.yml — see
# agent/styleguides/deployment.md.

ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here.
WORKDIR /rails

# Base packages: curl (Kamal healthchecks), jemalloc, libvips (Active
# Storage variants), postgresql-client (kamal dbc).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce the size of the final image.
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node is only needed to build the Vite islands; it is not copied into the
# final image.
ARG NODE_VERSION=20.19.0
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build-master

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

RUN bundle exec bootsnap precompile app/ lib/

# Build the Vite islands and the Propshaft assets, then drop node_modules
# so it never reaches the final image. The dummy DB values only satisfy
# config/database.yml evaluation; precompilation never connects.
RUN bin/vite build
RUN SECRET_KEY_BASE_DUMMY=1 DB_HOST=localhost DB_PASSWORD=precompile ./bin/rails assets:precompile
RUN rm -rf node_modules

FROM base

# Copy built artifacts: gems, application (incl. public/vite and
# public/assets generated in the build stage).
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database on the web role.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
