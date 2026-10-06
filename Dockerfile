# mldong-moon × jeeflow-moon 插件集成 API 镜像（native 形态）
# 多阶段构建，形状对齐 jeeflow-moon/Dockerfile.demo（builder 装工具链编译，运行层只带
# ubuntu 底 + 产物二进制 + 基线增量目录）。构建通道：
#   scripts/build-moon-jeeflow-image.sh（160 docker build → ACR 候选 tag → 回拉验证）
# ⚠ native 构建只能在 Linux 容器内做：moonbitlang/async 的 C 层在 Windows 仅支持 MSVC
#   （moonback 复测报告 10-02 记录），本机 Windows 无法本地 native 预构建验证。
# 服务端口 18680；运行时 env 与本机同口径：MLDONG_DB_HOST/MLDONG_DB_NAME/MLDONG_DB_PWD，
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

# ---- 运行层 ----
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/bin/mldong-moon-bin /usr/local/bin/mldong-moon-bin
WORKDIR /app
# 基线增量目录随镜像走（装载器 MLDONG_MIGRATIONS_DIR 默认相对 cwd）
COPY doc/sql/migrations doc/sql/migrations
EXPOSE 18680
CMD ["/usr/local/bin/mldong-moon-bin"]
