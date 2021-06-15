# syntax=docker/dockerfile:1
FROM alpine:latest AS base

WORKDIR /app

FROM base AS builder

RUN apk add --no-cache --virtual .build-deps \
        make wget gcc musl-dev perl-dev \
        perl-app-cpanminus \
    && apk add perl \
    && cpanm URI YAML::XS Path::Tiny Try::Tiny \
    && apk del .build-deps

FROM base AS run
COPY --from=builder /usr/bin/perl /usr/bin
COPY --from=builder /usr/lib /usr/lib
COPY --from=builder /usr/share /usr/share
COPY --from=builder /usr/local /usr/local

COPY md2tweets.pl .
WORKDIR /data
ENTRYPOINT ["perl", "/app/md2tweets.pl"]

