name = "mldong/moon-core-web"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/mldong/mldong-moon"

license = "Apache-2.0"

keywords = ["moonbit", "mldong", "web"]

preferred_target = "wasm"

description = "mldong-moon 控制层通用工具的 moonback 适配（错误统一转换/请求体解析/鉴权集成）；web 依赖唯一收口层，core 保持零 web"

import {
  "mldong/moon-core@0.1.0",
  "mldong/moon-token@0.1.11",
  "mldong/moon-token-moonback@0.1.11",
  "moonbitlang/moonback@0.8.6",
  "mldong/moon-token-store@0.1.11",
}
