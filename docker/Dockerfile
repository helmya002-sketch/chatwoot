# Tolzar Chatwoot image.
#
# LICENCE RULE (owner): no GPL / AGPL / SSPL / BSL code inside the product. Stages:
#   vips-builder  libvips built from source with only permissive / LGPL image libraries
#                 (no libimagequant GPL-3.0+, no fftw GPL-2.0+, no ImageMagick, no HEIF/x265, no poppler)
#   pre-builder   the full toolchain: native gems, Vite assets, run-time library list
#   final         clean ruby:alpine with only run-time libraries, the built app and installed gems:
#                 no gcc/g++/binutils/make/patch/git/readline, no ImageMagick (its Alpine package pulls
#                 fftw-double-libs). ActiveStorage uses libvips only (load_defaults 7.0 => :vips).
# The final stage fails the build if a forbidden package is installed or libvips links a GPL library.
#
# SBOM / LICENCE VERIFICATION (Server ops, after every image build). IMAGE=ghcr.io/helmya002-sketch/tolzar-chatwoot:latest
#   1. SBOM:
#        syft "$IMAGE" -o syft-json=tolzar-sbom.json -o table=tolzar-sbom.txt
#   2. OS packages with a GPL-family licence string (read the expected list below):
#        jq -r '.artifacts[] | select(.type=="apk") | [.name, ([.licenses[].value] | join(" "))] | @tsv' tolzar-sbom.json \
#          | grep -E '(^|[^L])GPL|AGPL|SSPL|BUSL|BSL-1' | sort
#      Expected only: OS base programs not linked into Tolzar (alpine-baselayout*, apk-tools, busybox,
#      busybox-binsh, musl-utils, scanelf; ssl_client is removed) and the allowed libraries libgcc / libstdc++
#      (GCC Runtime Library Exception), gmp (LGPL-3.0 OR GPL-2.0), zstd-libs (BSD OR GPL), xz-libs if present
#      (liblzma is 0BSD). Must NOT appear: libimagequant, fftw-*, readline, gcc, g++, binutils, make, patch,
#      git, imagemagick*, libgomp, libheif, x265*, ghostscript, poppler.
#   3. Gems / npm packages with a GPL-family licence (dual "Ruby OR GPL" / "MIT OR GPL" are fine, review the rest):
#        jq -r '.artifacts[] | select(.type!="apk") | [.type, .name, .version, ([.licenses[].value] | join(" "))] | @tsv' \
#          tolzar-sbom.json | grep -Ei 'GPL|SSPL|BUSL|BSL-1|Commons-Clause'
#   4. Acceptance: 0 GPL libraries linked into processes (exit 0 and "LICENCE CHECK PASSED"):
#        docker run --rm -i --entrypoint sh "$IMAGE" -s < docker/tolzar/licence_check.sh
#        # in the running Chatwoot container, after loading libvips once:
#        docker exec CONTAINER bundle exec rails tolzar:verify_image_variants
#        docker exec -i CONTAINER env MODE=maps sh -s < docker/tolzar/licence_check.sh
#   5. libvips itself:
#        docker run --rm --entrypoint sh "$IMAGE" -c 'vips --vips-config; ldd /usr/local/lib/libvips.so.42; apk info -R glib'
#      ldd must list no libimagequant / libfftw3 / libMagick / libheif / libpoppler.
#   6. Browser bundle: lamejs (LGPL-3.0) is gone:
#        docker run --rm --entrypoint sh "$IMAGE" -c 'grep -rlE "lamejs|Mp3Encoder" /app/public/vite || echo "no lamejs"'
#        pnpm licenses list --prod | grep -Ei 'GPL|SSPL|BUSL'   # in a checkout; LGPL hits need a decision
#   7. Thumbnails still work: `rails tolzar:verify_image_variants` (above) prints "OK"; the RSpec version is
#      spec/tolzar/image_variants_spec.rb (Tolzar specs CI). Then open a conversation with an image and a contact
#      with an avatar in the dashboard and check both thumbnails load.

# pre-build stage
FROM node:24-alpine as node

# libvips without GPL libraries. Alpine's `vips` package links libimagequant (GPL-3.0+) and
# fftw-double-libs (GPL-2.0+), so it is built here with every optional dependency off unless named.
# Kept: JPEG, PNG, WebP, TIFF (read + write), GIF (read only, built-in nsgif), EXIF orientation, colour
# profiles. GIF save needs a quantiser (libimagequant), so GIF thumbnails are written as PNG
# (config/initializers/zz_tolzar_image_variants.rb).
FROM alpine:3.21 AS vips-builder

ARG VIPS_VERSION=8.16.1
ARG VIPS_SHA256=d114d7c132ec5b45f116d654e17bb4af84561e3041183cd4bfd79abfb85cf724

RUN apk add --no-cache \
  build-base \
  meson \
  pkgconf \
  curl \
  xz \
  glib-dev \
  expat-dev \
  zlib-dev \
  libjpeg-turbo-dev \
  libpng-dev \
  libwebp-dev \
  tiff-dev \
  lcms2-dev \
  libexif-dev

RUN curl -fsSL -o /tmp/vips.tar.xz \
    "https://github.com/libvips/libvips/releases/download/v${VIPS_VERSION}/vips-${VIPS_VERSION}.tar.xz" \
  && echo "${VIPS_SHA256}  /tmp/vips.tar.xz" | sha256sum -c - \
  && mkdir /tmp/vips \
  && tar -xJf /tmp/vips.tar.xz -C /tmp/vips --strip-components=1 \
  && cd /tmp/vips \
  && meson setup build \
    --prefix=/usr/local \
    --libdir=lib \
    --buildtype=release \
    --auto-features=disabled \
    -Dexamples=false \
    -Dcplusplus=false \
    -Dmodules=disabled \
    -Dintrospection=disabled \
    -Djpeg=enabled \
    -Dpng=enabled \
    -Dspng=disabled \
    -Dwebp=enabled \
    -Dtiff=enabled \
    -Dlcms=enabled \
    -Dexif=enabled \
    -Dzlib=enabled \
    -Dimagequant=disabled \
    -Dquantizr=disabled \
    -Dfftw=disabled \
    -Dcgif=disabled \
    -Dmagick=disabled \
    -Dheif=disabled \
    -Dpoppler=disabled \
    -Dpdfium=disabled \
    -Drsvg=disabled \
    -Dopenexr=disabled \
    -Dopenjpeg=disabled \
    -Djpeg-xl=disabled \
    -Dcfitsio=disabled \
    -Dmatio=disabled \
    -Dopenslide=disabled \
    -Darchive=disabled \
  && meson compile -C build \
  && DESTDIR=/vips-root meson install -C build \
  && rm -rf /vips-root/usr/local/include /vips-root/usr/local/lib/pkgconfig /vips-root/usr/local/share

# Fail here, not in production, if a GPL library slipped into libvips.
RUN LD_LIBRARY_PATH=/vips-root/usr/local/lib /vips-root/usr/local/bin/vips --vips-config \
  && ldd /vips-root/usr/local/lib/libvips.so.42 \
  && if ldd /vips-root/usr/local/lib/libvips.so.42 | grep -Ei 'imagequant|fftw|magick|heif|x265|poppler|readline'; then \
    echo 'libvips links a forbidden library' >&2; exit 1; \
  fi

# The run-time packages libvips needs (owners of its sonames), for the pre-builder's run-deps scan.
RUN set -eu; \
  : > /vips-rundeps; \
  for so in $(scanelf --needed --nobanner --format '%n#p' --recursive /vips-root | tr ',' '\n' | sort -u); do \
    [ -e "/vips-root/usr/local/lib/$so" ] && continue; \
    f=''; \
    for d in /lib /usr/lib; do if [ -e "$d/$so" ]; then f="$d/$so"; break; fi; done; \
    [ -n "$f" ] || { echo "libvips needs $so but no package provides it" >&2; exit 1; }; \
    apk info -W "$f" | sed -n 's/.* is owned by //p' | sed -E 's/-[0-9][^-]*-r[0-9]+$//' >> /vips-rundeps; \
  done; \
  sort -u -o /vips-rundeps /vips-rundeps; \
  echo 'libvips run deps:'; cat /vips-rundeps

FROM ruby:3.4.4-alpine3.21 AS pre-builder

ARG NODE_VERSION="24.13.0"
ARG PNPM_VERSION="10.2.0"
ENV NODE_VERSION=${NODE_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}

# ARG default to production settings
# For development docker-compose file overrides ARGS
ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.5.16

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}

ARG NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider"
ENV NODE_OPTIONS ${NODE_OPTIONS}

ENV BUNDLE_PATH="/gems"

RUN apk update && apk add --no-cache \
  openssl \
  tar \
  build-base \
  tzdata \
  postgresql-dev \
  postgresql-client \
  git \
  curl \
  xz \
  pax-utils \
  && mkdir -p /var/app \
  && gem install bundler -v "$BUNDLER_VERSION"

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN npm install -g pnpm@${PNPM_VERSION}

RUN echo 'export PNPM_HOME="/root/.local/share/pnpm"' >> /root/.shrc \
  && echo 'export PATH="$PNPM_HOME:$PATH"' >> /root/.shrc \
  && export PNPM_HOME="/root/.local/share/pnpm" \
  && export PATH="$PNPM_HOME:$PATH" \
  && pnpm --version

# Persist the environment variables in Docker
ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

COPY --from=vips-builder /vips-root/usr/local/ /usr/local/
COPY --from=vips-builder /vips-rundeps /tmp/vips-rundeps
RUN apk add --no-cache $(cat /tmp/vips-rundeps)

WORKDIR /app

COPY Gemfile Gemfile.lock ./

# natively compile grpc and protobuf to support alpine musl (dialogflow-docker workflow)
# https://github.com/googleapis/google-cloud-ruby/issues/13306
# adding xz as nokogiri was failing to build libxml
# https://github.com/chatwoot/chatwoot/issues/4045
RUN apk update && apk add --no-cache build-base musl ruby-full ruby-dev gcc make musl-dev openssl openssl-dev g++ linux-headers xz
RUN bundle config set --local force_ruby_platform true

# Do not install development or test gems in production
RUN if [ "$RAILS_ENV" = "production" ]; then \
  bundle config set without 'development test'; bundle install -j 4 -r 3; \
  else bundle install -j 4 -r 3; \
  fi

COPY package.json pnpm-lock.yaml ./
RUN pnpm i

COPY . /app

# creating a log directory so that image wont fail when RAILS_LOG_TO_STDOUT is false
# https://github.com/chatwoot/chatwoot/issues/701
RUN mkdir -p /app/log

# generate production assets if production environment
# Tolzar: the browser bundles' open-source notices (in-app "Open-source licences" page), written while
# node_modules still exists.
RUN if [ "$RAILS_ENV" = "production" ]; then \
  node docker/tolzar/js_notices.mjs /app > /app/config/tolzar/js_notices.json \
  && SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache; \
  fi

# Generate .git_sha file with current commit hash
RUN (git rev-parse HEAD 2>/dev/null || echo tolzar-build) > /app/.git_sha

# Remove unnecessary files
RUN rm -rf /gems/ruby/3.4.0/cache/*.gem \
  && find /gems/ruby/3.4.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete \
  && rm -rf .git \
  && rm -f .gitignore

# pg_isready (docker/entrypoints/rails.sh waits for Postgres with it) without the rest of
# postgresql-client: psql links readline (GPL-3.0). pg_isready needs only libpq.
RUN mkdir -p /opt/tolzar/bin \
  && cp "$(readlink -f "$(command -v pg_isready)")" /opt/tolzar/bin/pg_isready \
  && ldd /opt/tolzar/bin/pg_isready \
  && if ldd /opt/tolzar/bin/pg_isready | grep -i readline; then echo 'pg_isready links readline' >&2; exit 1; fi

# Run-time packages: the apk package owning every shared library that the gems' native extensions,
# node, libvips and pg_isready need (the way the official ruby image computes its run deps). Libraries
# built in this file (/usr/local/lib) are skipped; sonames no installed package provides (prebuilt
# binaries for other platforms inside gems) are reported and skipped.
RUN set -eu; \
  scanelf --needed --nobanner --format '%n#p' --recursive /gems /usr/local/lib /usr/local/bin /opt/tolzar/bin \
    | tr ',' '\n' | sort -u > /tmp/needed-sonames; \
  : > /tmp/rundeps; \
  while read -r so; do \
    [ -n "$so" ] || continue; \
    [ -e "/usr/local/lib/$so" ] && continue; \
    f=''; \
    for d in /lib /usr/lib; do if [ -e "$d/$so" ]; then f="$d/$so"; break; fi; done; \
    if [ -z "$f" ]; then echo "tolzar run deps: no installed provider for $so (skipped)"; continue; fi; \
    apk info -W "$f" | sed -n 's/.* is owned by //p' | sed -E 's/-[0-9][^-]*-r[0-9]+$//' >> /tmp/rundeps; \
  done < /tmp/needed-sonames; \
  sort -u -o /tmp/rundeps /tmp/rundeps; \
  echo 'tolzar run deps:'; cat /tmp/rundeps

# final build stage
FROM ruby:3.4.4-alpine3.21

ARG NODE_VERSION="24.13.0"
ARG PNPM_VERSION="10.2.0"
ENV NODE_VERSION=${NODE_VERSION}
ENV PNPM_VERSION=${PNPM_VERSION}

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.5.16

ARG EXECJS_RUNTIME="Disabled"
ENV EXECJS_RUNTIME ${EXECJS_RUNTIME}

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLE_FORCE_RUBY_PLATFORM ${BUNDLE_FORCE_RUBY_PLATFORM}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}
ENV BUNDLE_PATH="/gems"

COPY --from=pre-builder /tmp/rundeps /tmp/rundeps

# Run-time libraries only. No build-base / git / imagemagick / postgresql-client (see the header).
RUN apk update && apk add --no-cache \
  openssl \
  tzdata \
  libpq \
  $(cat /tmp/rundeps) \
  && rm /tmp/rundeps \
  && gem install bundler -v "$BUNDLER_VERSION" \
  && if [ "$RAILS_ENV" = "production" ]; then apk del --no-cache ssl_client; fi

# Restrict libvips to its trusted image loaders when generating variants
ENV VIPS_BLOCK_UNTRUSTED=1

COPY --from=vips-builder /vips-root/usr/local/ /usr/local/
COPY --from=pre-builder /opt/tolzar/bin/pg_isready /usr/local/bin/pg_isready

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN if [ "$RAILS_ENV" != "production" ]; then \
  apk add --no-cache curl build-base git \
  && ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g pnpm@${PNPM_VERSION} \
  && pnpm --version; \
  fi

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app

# Copy .git_sha file from pre-builder stage
COPY --from=pre-builder /app/.git_sha /app/.git_sha

# Licence guard: the build fails if a forbidden package is installed, libvips links a GPL library, any binary
# under /usr/local or /gems links a GPL library, or any installed package is GPL-licensed other than the
# Alpine base programs (docker/tolzar/licence_check.sh). ssl_client (GPL-2.0, busybox wget's TLS helper) is
# removed above: nothing in the app runs it.
# Development images (RAILS_ENV != production) keep build-base + git above for the `bundle install`
# in docker/entrypoints/rails.sh and are not checked; they are never shipped.
RUN set -eu; \
  [ "$RAILS_ENV" = "production" ] || exit 0; \
  for p in gcc g++ binutils make patch git build-base readline imagemagick imagemagick-libs \
    libimagequant fftw-double-libs libheif x265-libs ghostscript poppler; do \
    if apk info -e "$p" > /dev/null 2>&1; then echo "licence guard: $p must not be in the runtime image" >&2; exit 1; fi; \
  done; \
  if ldd /usr/local/lib/libvips.so.42 | grep -Ei 'imagequant|fftw|magick|heif|x265|poppler|readline'; then \
    echo 'licence guard: libvips links a forbidden library' >&2; exit 1; \
  fi; \
  vips --version; \
  pg_isready --version; \
  node --version; \
  sh /app/docker/tolzar/licence_check.sh

WORKDIR /app

# ruby-vips (FFI) must find this libvips and glib at run time.
RUN bundle exec ruby -e 'require "vips"; puts "ruby-vips sees libvips #{Vips.version_string}"'

EXPOSE 3000
