ARG GO_VERSION=1.25.1
ARG ALPINE_VERSION=3.22

FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

ENV GOPROXY=https://goproxy.cn,direct \
    GOSUMDB=sum.golang.org \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

WORKDIR /src

# 1) 仅拷贝模块清单，单独一层缓存依赖下载
COPY app/go.mod app/go.sum* ./
RUN go mod download

# 2) 再拷贝源码并编译
COPY app/ ./
RUN go build -trimpath -ldflags="-s -w" -o /out/main ./main.go

FROM alpine:${ALPINE_VERSION} AS runtime

# 证书 + 时区 + 非 root 用户
RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S app \
    && adduser -S -G app -h /app -s /sbin/nologin app

ENV TZ=Asia/Shanghai \
    APP_BIN=/app/main

WORKDIR /app
COPY --from=builder --chmod=0755 /out/main /app/main
COPY --chmod=0755 ./bin/entrypoint.sh /entrypoint.sh

USER app

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]