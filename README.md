# golang-app-build-image

一个生产可用的 Go 应用容器镜像构建模板：多阶段构建、静态二进制、非 root 运行、信号优雅停机。

## 仓库结构

```
.
├── Dockerfile              # 多阶段构建
├── .dockerignore           # 构建上下文过滤
├── .gitignore
├── .gitattributes          # 强制 LF 行尾
├── app/                    # Go 应用源码
│   ├── go.mod
│   └── main.go             # HTTP server (PID 1 + graceful shutdown)
└── bin/
    └── entrypoint.sh       # 容器入口脚本（透传参数与信号）
```

## 构建产物

- 基础镜像：`golang:1.25.1-alpine3.22`（builder）/ `alpine:3.22`（runtime）
- 运行时镜像体积：约 15 MB
- 容器内运行用户：`app`（非 root，uid 100）
- 监听端口：`8000`（HTTP）
- 健康检查端点：`/healthz`

## 构建

```bash
docker build -t golang-app-build-image:dev .
```

# 构建多平台镜像并推送到镜像仓库

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t yongyuanfan/golang-app:1.25.1.beta1 \
  --push .
```

构建参数：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `GO_VERSION` | `1.25.1` | Go 编译器版本 |
| `ALPINE_VERSION` | `3.22` | 运行时 Alpine 版本 |

```bash
docker build --build-arg GO_VERSION=1.25.1 --build-arg ALPINE_VERSION=3.22 -t app:dev .
```

## 运行

```bash
# 默认：监听 :8000
docker run --rm -p 8000:8000 golang-app-build-image:dev

# 自定义监听地址
docker run --rm -p 9000:9000 golang-app-build-image:dev -addr=:9000

# 追加参数（透传到 Go 进程）
docker run --rm -p 8000:8000 golang-app-build-image:dev -addr=:8000 -some-flag value

# 通过环境变量切换入口二进制
docker run --rm -e APP_BIN=/app/main golang-app-build-image:dev
```

### 路由

| 路径 | 行为 |
|---|---|
| `GET /` | 返回 `Hello, World!` 与进程 PID、参数 |
| `GET /healthz` | 返回 `ok`（200），用于就绪/存活探针 |

## 优雅停机

容器进程（PID 1）接收 `SIGTERM` / `SIGINT` 时：

1. 停止接受新连接
2. 等待进行中的请求完成（最长 10s）
3. 退出并打印 `bye`

```bash
docker stop <container>   # 默认发送 SIGTERM，超时 10s 后 SIGKILL
```

如果直接 `exec` 进入容器发送 `Ctrl+C`（SIGINT），进程同样会优雅退出。

## 镜像入口原理

`ENTRYPOINT ["/entrypoint.sh"]` + `CMD ["/app/main"]`：

- `docker run image` → 实际命令为 `entrypoint.sh /app/main`，启动默认监听 `:8000`。
- `docker run image -addr=:9000 foo` → 实际命令为 `entrypoint.sh -addr=:9000 foo`，**CMD 被覆盖**，参数透传到 Go 进程。
- `entrypoint.sh` 通过 `exec "$APP_BIN" "$@"` 把自身替换为 Go 进程，使 Go 进程成为 PID 1，信号可直接转发（无 sh 包装损耗）。
- `APP_BIN` 缺失或不可执行时，entrypoint 以 `127` 退出并打印明确错误。

### `APP_BIN` 环境变量

- 默认值：`/app/main`
- 可用于：在镜像不变的情况下切换到不同二进制（如 sidecar、init 容器、调试模式）。

## 常见操作

### 本地直接运行（不开容器）

```bash
go run ./app           # 监听 :8000
go run ./app -addr=:9000
```

### 修改监听端口

Dockerfile 中 `EXPOSE 8000` 是声明性的，实际监听端口由 `-addr` 参数控制：

```bash
docker run --rm -p 9000:9000 golang-app-build-image:dev -addr=:9000
```

### 使用不同的 Go 版本

```bash
docker build --build-arg GO_VERSION=1.25.1 -t app:dev .
```

> 注意：需与 `app/go.mod` 中的 `go` 指令保持兼容（go 1.21+ 的 GOTOOLCHAIN 机制可以自动下载匹配的工具链）。

## 安全说明

- 容器以非 root 用户 `app` 运行。
- 二进制使用 `CGO_ENABLED=0` 静态编译、`-trimpath` 去除构建路径、`-ldflags="-s -w"` 去除调试符号，减小体积并避免泄露构建环境信息。
- 镜像安装 `ca-certificates` 与 `tzdata`，便于对外发起 TLS 请求与设置时区（默认 `Asia/Shanghai`）。

## 限制

- 当前样例程序仅打印 `Hello, World!` 并暴露 `/healthz`，实际项目请把 `app/main.go` 替换为业务代码。
- 未配置 `HEALTHCHECK` 指令；如需 Docker 原生健康检查，可在 Dockerfile 中追加：
  ```Dockerfile
  HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
      CMD wget -qO- http://127.0.0.1:8000/healthz || exit 1
  ```
  （需在 `apk add` 时加入 `wget`，或改用 `nc`/`curl`。）

## 许可

按需自取。
