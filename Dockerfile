FROM golang:1.25.11-alpine3.24 AS builder

ENV GOPROXY=https://goproxy.cn/

COPY app /app

WORKDIR /app

RUN go mod download

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/main ./main.go

FROM alpine:3.24.0

WORKDIR /app

COPY --from=builder /out/main /app/main

COPY ./bin/entrypoint.sh /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]