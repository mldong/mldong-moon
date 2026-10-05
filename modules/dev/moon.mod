name = "mldong/moon-dev"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/mldong/mldong-moon"

license = "Apache-2.0"

keywords = ["moonbit", "mldong", "dev"]

preferred_target = "wasm"

description = "mldong-moon 开发工具模块（dev）：库元数据（gen 代码生成器与 dev_schema 导入共用的底座）"

import {
  "mldong/moon-core@0.1.0",
  "mldong/moon-core-web@0.1.0",
  "mldong/moon-token@0.1.10",
  "mldong/moon-token-moonback@0.1.10",
  "mldong/moon-token-store@0.1.10",
  "moonbitstack/moondb@0.2.0",
  "moonbitstack/moonmysql@0.7.3",
  "moonbitlang/moonback@0.8.6",
  "Betterlol/moon_zod@0.8.2",
  "moonbitlang/async@0.22.4",
}
