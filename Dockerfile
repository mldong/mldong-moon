# mldong-moon × jeeflow-moon 插件集成 API 镜像（native 形态，10-07 定稿）
# 多阶段形状学 jeeflow-moon/Dockerfile.demo：builder 层装工具链编译，运行层只带
# ubuntu 底 + 产物二进制 + 基线增量目录——工具链/_build 全留在 builder 不进运行层。
# 形态沿革：2026-10-06 首轮 native 在 160（kernel 3.10）跑不了（async C 层硬走 statx）
# 曾改 wasm+moonrun；同日 160 升 UEK6 5.4 后 statx 可用 => 定稿 native 直跑（无运行器
# 间接层，与 jeeflow-moon demo 生产形态同构）。wasm 仍为本仓 dev/test 主档口径。
# 注意：native 只能在 Linux 容器内编译（moonbitlang/async 的 C 层在 Windows 仅支持 MSVC）。
# 服务端口 18680；运行 env：MLDONG_DB_* 与 MLDONG_LISTEN_HOST=0.0.0.0（compose/run 传），
#   MLDONG_MIGRATIONS_DIR 默认 doc/sql/migrations（相对 WORKDIR，镜像内自带）。
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates git gcc libc-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH=/root/.moon/bin:$PATH

WORKDIR /app
COPY moon.work moon.work
COPY core core
COPY core-web core-web
COPY plugins plugins
COPY modules modules
COPY cmd cmd
# 只编服务端（cmd/main）；cmd/gen 是开发工装，不进镜像构建图
RUN moon update && moon build --target native cmd/main

# 产物动态定位（moon build 默认落 debug 目录；find 兜底），拷为固定路径
RUN BIN=$(find _build -type f -name 'main*' -perm -u+x 2>/dev/null | head -1) \
    && [ -n "$BIN" ] \
    && cp "$BIN" /usr/local/bin/mldong-moon-bin \
    || (echo "=== binary not found, target tree:"; find _build -type f -perm -u+x 2>/dev/null | head -40; exit 1)

# ---- 运行层（瘦身：只带二进制 + 增量目录，ubuntu 底保 glibc 一致性）----
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/bin/mldong-moon-bin /usr/local/bin/mldong-moon-bin
WORKDIR /app
COPY doc/sql/migrations doc/sql/migrations
EXPOSE 18680
CMD ["/usr/local/bin/mldong-moon-bin"]
