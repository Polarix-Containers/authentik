ARG VERSION=2025.8.3
ARG NODE=24
ARG GO=1.25
ARG PYTHON=3.13
ARG UV=0.8
ARG UID=200001
ARG GID=200001

# Stage 1: Build webui
FROM node:${NODE}-alpine AS node-builder

ARG VERSION

ENV NODE_ENV=production

WORKDIR /work/web

ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/web/package.json /work
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:web /work/web/
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:website /work/website/

RUN apk -U upgrade \
    && apk add libstdc++ \
    && rm -rf /var/cache/apk/* \
    && mkdir -p /work/web/node_modules/@goauthentik/api

COPY --from=ghcr.io/polarix-containers/hardened_malloc:latest /install /usr/local/lib/
ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"
    
RUN npm ci \
    && npm run build \
    && npm run build:sfe


# ======================================= #

# Stage 2: Build go proxy
FROM golang:${GO}-alpine AS go-builder

ARG VERSION

ENV CGO_ENABLED=1

WORKDIR /go/src/goauthentik.io

COPY --from=node-builder /work/web/robots.txt /go/src/goauthentik.io/web/robots.txt
COPY --from=node-builder /work/web/security.txt /go/src/goauthentik.io/web/security.txt

ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:cmd /go/src/goauthentik.io/cmd
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:authentik/lib /go/src/goauthentik.io/authentik/lib
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/web/static.go /go/src/goauthentik.io/web/static.go
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:internal /go/src/goauthentik.io/internal
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/go.mod /go/src/goauthentik.io/go.mod
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/go.sum /go/src/goauthentik.io/go.sum

RUN apk -U upgrade \
    && apk add build-base libstdc++ \
    && rm -rf /var/cache/apk/*

COPY --from=ghcr.io/polarix-containers/hardened_malloc:latest /install /usr/local/lib/
ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"
    
RUN go mod download \
    && go build -o /go/authentik ./cmd/server

# ======================================= #

# Stage 3: MaxMind GeoIP
FROM  ghcr.io/goauthentik/server:${VERSION} AS geoip

# ======================================= #

# Stage 4: Download uv

FROM ghcr.io/astral-sh/uv:${UV}-python${PYTHON}-alpine AS uv

# ======================================= #

# Stage 5: Base python image
FROM python:${PYTHON}-alpine AS python-base

ARG VERSION

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

ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:packages/ /ak-root/packages

RUN apk -U upgrade \
    && apk add libstdc++

COPY --from=ghcr.io/polarix-containers/hardened_malloc:latest /install /usr/local/lib/
ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

# ======================================= #

# Stage 6: Python dependencies
FROM python-base AS python-deps

ARG VERSION

ENV PATH="/root/.cargo/bin:$PATH" \
    UV_NO_BINARY_PACKAGE="cryptography lxml python-kadmin-rs xmlsec"

ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/pyproject.toml .
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/uv.lock .

RUN apk add build-base pkgconf libffi-dev git \
        # dependencies not explicitly mentioned in upstream's container
        clang17-libclang xmlsec-dev \
        # cryptography
        curl \
        # libxml
        libxslt-dev zlib-dev \
        # postgresql
        libpq-dev \
        # python-kadmin-rs
        clang krb5-dev sccache \
        # xmlsec
        libltdl \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && uv sync --frozen --no-install-project --no-dev

# ======================================= #

# Stage 7: Run
FROM python-base AS final-image

ARG VERSION
ARG UID
ARG GID

ENV TMPDIR=/dev/shm/ \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

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
    && mkdir -p /certs /media /blueprints \
    && mkdir -p /authentik/.ssh \
    && mkdir -p /ak-root \
    && chown authentik:authentik /certs /media /authentik/.ssh /ak-root

COPY --from=go-builder /go/authentik /bin/authentik
COPY --from=python-deps /ak-root/.venv /ak-root/.venv
COPY --from=node-builder /work/web/dist/ /web/dist/
COPY --from=node-builder /work/web/authentik/ /web/authentik/
COPY --from=geoip /geoip /geoip

ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:authentik /authentik
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/pyproject.toml /
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/uv.lock /
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:schemas /schemas
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:locale /locale
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:tests /tests
ADD --chmod=755 https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/manage.py /
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:blueprints /blueprints
ADD https://github.com/goauthentik/authentik.git#version/${VERSION}:lifecycle/ /lifecycle
ADD https://raw.githubusercontent.com/goauthentik/authentik/refs/tags/version/${VERSION}/authentik/sources/kerberos/krb5.conf /etc/krb5.conf

RUN  ln -s /ak-root/packages /packages

USER authentik

HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 CMD [ "ak", "healthcheck" ]

ENTRYPOINT [ "dumb-init", "--", "ak" ]
