ARG VERSION=2026.5.3

ARG NODE=24
ARG GO=1.26
ARG PYTHON=3.14
ARG UV=0.11

# clang version is not officially documented, but 19 what upstream uses on Debian Trixie. 
# We chose 20 because it is the closest available on Alpine 3.24
ARG CLANG=20

ARG UID=200001
ARG GID=200001

# Stage: Repo clone
FROM scratch AS extract

ARG VERSION

ADD --keep-git-dir=false https://github.com/goauthentik/authentik.git#version/${VERSION} /extract

# Stage: Build webui
FROM node:${NODE}-alpine AS node-builder

ENV NODE_ENV=production

WORKDIR /work/web

COPY --from=extract /extract/web/package.json /work
COPY --from=extract /extract/packages /work/packages/
COPY --from=extract /extract/web /work/web/
COPY --from=extract /extract/website /work/website/

RUN apk -U upgrade \
    && apk add libstdc++ \
    && npm update -g npm \
    && rm -rf /var/cache/apk/* \
    && mkdir -p /work/web/node_modules/@goauthentik/api

COPY --from=ghcr.io/polarix-containers/hardened_malloc:latest /install /usr/local/lib/
ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"
    
RUN npm i \
    && npm run build \
    && npm run build:sfe


# ======================================= #

# Stage: Build go proxy
FROM golang:${GO}-alpine AS go-builder

ENV CGO_ENABLED=1

WORKDIR /go/src/goauthentik.io

COPY --from=node-builder /work/web/robots.txt /go/src/goauthentik.io/web/robots.txt
COPY --from=node-builder /work/web/security.txt /go/src/goauthentik.io/web/security.txt

COPY --from=extract /extract/cmd /go/src/goauthentik.io/cmd
COPY --from=extract /extract/authentik/lib /go/src/goauthentik.io/authentik/lib
COPY --from=extract /extract/web/static.go /go/src/goauthentik.io/web/static.go
COPY --from=extract /extract/internal /go/src/goauthentik.io/internal
COPY --from=extract /extract/go.mod /go/src/goauthentik.io/go.mod
COPY --from=extract /extract/go.sum /go/src/goauthentik.io/go.sum
COPY --from=extract /extract/packages/client-go /go/src/goauthentik.io/packages/client-go

RUN apk -U upgrade \
    && apk add build-base libstdc++ \
    && rm -rf /var/cache/apk/*

COPY --from=ghcr.io/polarix-containers/hardened_malloc:latest /install /usr/local/lib/
ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"
    
RUN go mod download \
    && go build -o /go/authentik-server ./cmd/server

# ======================================= #

# Stage: MaxMind GeoIP
FROM  ghcr.io/goauthentik/server:${VERSION} AS geoip

# ======================================= #

# Stage: download Rust toolchain

FROM alpine:latest AS rust-toolchain

ENV PATH="/root/.cargo/bin:$PATH"

COPY --from=extract /extract/rust-toolchain.toml .

RUN apk -U upgrade \
    && apk add build-base curl \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain none \
    && rustup install \
    && rustup default "$(sed -n 's/channel = "\(.*\)"/\1/p' rust-toolchain.toml)"

# ======================================= #

# Stage: Download uv

FROM ghcr.io/astral-sh/uv:${UV}-python${PYTHON}-alpine AS uv

# ======================================= #

# Stage: Base python image
FROM ghcr.io/polarix-containers/authentik:python-${VERSION} AS python-base

ENV VENV_PATH="/ak-root/.venv" \
    PATH="/lifecycle:/ak-root/.venv/bin:$PATH" \
    UV_COMPILE_BYTECODE=true \
    UV_LINK_MODE=copy \
    UV_NATIVE_TLS=true \
    UV_NO_CACHE=true \
    UV_NO_DEV=true \
    UV_NO_MANAGED_PYTHON=true \
    UV_PYTHON_DOWNLOADS=false

WORKDIR /ak-root/

COPY --from=uv /usr/local/bin/uv /usr/local/bin/uvx /bin/

COPY --from=extract /extract/packages/ /ak-root/packages

# ======================================= #

# Stage: build rust binary

FROM python-base AS rust-builder

ARG CLANG

ENV LD_PRELOAD=""
ENV PATH="/root/.cargo/bin:$PATH"
ENV AWS_LC_FIPS_SYS_CC=clang

# Merging content from go container
ENV GOTOOLCHAIN=local
ENV GOPATH=/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
COPY --from=go-builder /usr/local/go /usr/local/go

WORKDIR /build

COPY --from=rust-toolchain /root/.rustup /root/.rustup
COPY --from=rust-toolchain /root/.cargo /root/.cargo

COPY --from=extract /extract/rust-toolchain.toml .
COPY --from=extract /extract/Cargo.toml .
COPY --from=extract /extract/Cargo.lock .
COPY --from=extract /extract/.cargo .cargo
COPY --from=extract /extract/build.rs .
COPY --from=extract /extract/src src
COPY --from=extract /extract/packages/ak-axum packages/ak-axum
COPY --from=extract /extract/packages/ak-common packages/ak-common
COPY --from=extract /extract/packages/client-rust packages/client-rust
COPY --from=extract /extract/authentik/lib/default.yml authentik/lib/default.yml
COPY --from=extract /extract/website/scripts/docsmg/ website/scripts/docsmg/

RUN apk add build-base cmake clang${CLANG} linux-headers perl \
    && ln -s /usr/bin/clang-${CLANG} /usr/bin/clang \
#    && sed -i 's/, features = ["fips"]//g' Cargo.toml \
    && cargo build --package authentik --no-default-features --features core --locked --release \
    && cp ./target/release/authentik /bin/authentik


# ======================================= #

# Stage: Python dependencies
FROM python-base AS python-deps

ARG CLANG

# Installing python-kadmin-rs from Pypi instead of building it because fails to build on Python 3.23

ENV PATH="/root/.cargo/bin:$PATH" \
    UV_NO_BINARY_PACKAGE="cryptography lxml xmlsec"

COPY --from=rust-toolchain /root/.rustup /root/.rustup
COPY --from=rust-toolchain /root/.cargo /root/.cargo

COPY --from=extract /extract/pyproject.toml .
COPY --from=extract /extract/uv.lock .
COPY --from=extract /extract/packages/ak-guardian packages/ak-guardian
COPY --from=extract /extract/packages/django-channels-postgres packages/django-channels-postgres
COPY --from=extract /extract/packages/django-dramatiq-postgres packages/django-dramatiq-postgres
COPY --from=extract /extract/packages/django-postgres-cache packages/django-postgres-cache
COPY --from=extract /extract/rust-toolchain.toml .

RUN apk add build-base pkgconf libffi-dev git \
        # dependencies not explicitly mentioned in upstream's container
        krb5-server xmlsec-dev \
        # cryptography
        curl \
        # libxml
        libxslt-dev zlib-dev \
        # postgresql
        libpq-dev \
        # python-kadmin-rs
        krb5-dev clang${CLANG}-libclang \
        # xmlsec
        libltdl \
    && uv sync --locked --no-install-project --no-dev

# ======================================= #

# Stage: Run
FROM python-base AS final-image

ARG UID
ARG GID

ENV TMPDIR=/dev/shm/
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

LABEL maintainer="Thien Tran contact@tommytran.io" \
    org.opencontainers.image.version=${VERSION}

WORKDIR /

RUN --network=none \
    addgroup -g ${GID} authentik \
    && adduser -u ${UID} --ingroup authentik --disabled-password --system authentik --home /authentik

RUN apk add libpq libmaxminddb ca-certificates krb5-libs libltdl libxslt \
        # dependencies not explicitly mentioned in upstream's container
        bash coreutils-env xmlsec \
    && rm -rf /var/cache/apk/* \
    && pip3 install --no-cache-dir --upgrade pip \
    && mkdir -p /certs /data /media /blueprints \
    && ln -s /media /data/media \
    && mkdir -p /authentik/.ssh \
    && mkdir -p /ak-root \
    && chown authentik:authentik /certs /media /authentik/.ssh /ak-root

COPY --from=rust-builder /bin/authentik /bin/authentik
COPY --from=go-builder /go/authentik-server /bin/authentik-server
COPY --from=python-deps /ak-root/.venv /ak-root/.venv
COPY --from=node-builder /work/web/dist/ /web/dist/
COPY --from=node-builder /work/web/authentik/ /web/authentik/
COPY --from=geoip /geoip /geoip

COPY --from=extract /extract/authentik /authentik
COPY --from=extract /extract/pyproject.toml /
COPY --from=extract /extract/uv.lock /
COPY --from=extract /extract/schemas /schemas
COPY --from=extract /extract/locale /locale
COPY --from=extract /extract/tests /tests
COPY --from=extract --chmod=755 /extract/manage.py /
COPY --from=extract /extract/blueprints /blueprints
COPY --from=extract /extract/lifecycle/ /lifecycle
COPY --from=extract /extract/authentik/sources/kerberos/krb5.conf /etc/krb5.conf

RUN  ln -s /ak-root/packages /packages

USER authentik

HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 CMD [ "ak", "healthcheck" ]

ENTRYPOINT [ "dumb-init", "--", "ak" ]
