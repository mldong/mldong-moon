# mldong-moon × jeeflow-moon 插件集成 API 镜像。
# ⚠ 形态定 wasm + moonrun，不是 native（2026-10-06 候选镜像实测缺口）：
#   moonbitlang/async native 档的 open 硬走 SYS_statx（fs.c:609，内核 4.11+），
#   160 = CentOS 7 / kernel 3.10 ⇒ readdir/read/write 全 ENOSYS（连基线增量目录都读不了）；
#   jeeflow-moon demo 的 native 镜像能跑是因为宿主是公网新内核机。
#   wasm 档 fs 走 WASI（thread_pool.wasm.mbt），无 statx 依赖 ⇒ 160 可跑。
# 多阶段：builder 装 moonbit 工具链编 wasm；运行层 ubuntu + main.wasm + moonrun 二进制。
# 运行时 env 与本机同口径：MLDONG_DB_HOST/MLDONG_DB_NAME/MLDONG_DB_PWD，
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
# 只编服务端（cmd/main）出 wasm；cmd/gen 是开发工装，不进镜像构建图
RUN moon update && moon build --target wasm cmd/main

# wasm 产物动态定位（moon build 默认落 debug 目录；find 兜底）
RUN WASM=$(find _build -type f -name '*.wasm' -path '*main*' 2>/dev/null | head -1) \
    && [ -n "$WASM" ] \
    && cp "$WASM" /app/main.wasm \
    || (echo "=== wasm not found, target tree:"; find _build -name '*.wasm' 2>/dev/null | head -40; exit 1)

# ---- 运行层 ----
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# moonrun（wasm 运行器）：moonbit 工具链装一次只取二进制
COPY --from=builder /root/.moon/bin/moonrun /usr/local/bin/moonrun
COPY --from=builder /app/main.wasm /app/main.wasm
WORKDIR /app
# 基线增量目录随镜像走（装载器 MLDONG_MIGRATIONS_DIR 默认相对 cwd）
COPY doc/sql/migrations doc/sql/migrations
EXPOSE 18680
# MLDONG_LISTEN_HOST=0.0.0.0 由 docker run -e / compose 传入（本仓默认 127.0.0.1 仅本机 dev）
CMD ["moonrun", "/app/main.wasm"]
