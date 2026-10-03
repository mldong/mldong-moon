name = "mldong/moon-core-web"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/mldong/mldong-moon"

license = "Apache-2.0"

keywords = ["moonbit", "mldong", "web"]

preferred_target = "wasm"

description = "mldong-moon 控制层通用工具的 moonback 适配（错误统一转换/请求体解析）；web 依赖唯一收口层，core 保持零 web"

import {
  "mldong/moon-core@0.1.0",
  "moonbitlang/moonback@0.8.6",
}
