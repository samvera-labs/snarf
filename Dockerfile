# syntax=docker/dockerfile:1
# renovate: datasource=ruby-version depName=ruby
ARG RUBY_VERSION=4.0.10

FROM ruby:${RUBY_VERSION}-alpine AS base
ARG UID=1000
ARG GID=1000
RUN apk add --no-cache libpq tzdata \
 && addgroup -g "$GID" snarf \
 && adduser -D -u "$UID" -G snarf snarf \
 && chmod 755 /usr/local/bundle
ENV BUNDLE_FROZEN=true \
    RUBY_YJIT_ENABLE=1
WORKDIR /app

FROM base AS build
RUN apk add --no-cache build-base postgresql-dev \
 && chown snarf:snarf /usr/local/bundle
USER snarf
COPY --chown=snarf:snarf Gemfile Gemfile.lock ./
RUN gem install bundler --no-document \
      -v "$(awk '/BUNDLED WITH/ { getline; print $1 }' Gemfile.lock)"

FROM build AS gems-prod
ENV BUNDLE_WITHOUT=development:test
RUN --mount=type=cache,target=/usr/local/bundle/cache,uid=${UID},gid=${GID},sharing=locked \
    bundle install \
 && find /usr/local/bundle/gems \( -name '*.o' -o -name '*.c' \) -delete

FROM gems-prod AS gems-dev
ENV BUNDLE_WITHOUT=
RUN --mount=type=cache,target=/usr/local/bundle/cache,uid=${UID},gid=${GID},sharing=locked \
    bundle install

FROM base AS dev
RUN apk add --no-cache git \
 && chown snarf:snarf /app
ENV APP_ENV=development
COPY --from=gems-dev --chown=snarf:snarf /usr/local/bundle /usr/local/bundle
COPY --chown=snarf:snarf . .
USER snarf

FROM base AS app
ENV APP_ENV=production \
    BUNDLE_WITHOUT=development:test
COPY --from=gems-prod --chown=root:root /usr/local/bundle /usr/local/bundle
COPY . .
USER snarf

FROM app AS worker
CMD ["bin/worker"]

FROM app AS web
EXPOSE 3000
CMD ["bin/web"]
