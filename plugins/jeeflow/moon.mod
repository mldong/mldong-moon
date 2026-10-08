name = "mldong/moon-plugin-jeeflow"

version = "0.1.0"

repository = "https://github.com/mldong/mldong-moon"

license = "Apache-2.0"

keywords = ["moonbit", "mldong", "jeeflow", "plugin"]

preferred_target = "wasm"

description = "mldong-moon 第一官方插件：jeeflow-moon 工作流引擎（POST /wf/{action} 单 handler 全转发 Facade::flow）"

import {
  "mldong/moon-core@0.1.0",
  "mldong/moon-core-web@0.1.0",
  "mldong/moon-plugin-api@0.1.0",
  "mldong/jeeflow-core@0.1.33",
  "mldong/jeeflow-facade@0.1.33",
  "mldong/jeeflow-repository-mysql@0.1.33",
  "mldong/jeeflow-persist@0.1.33",
  "moonbitlang/moonback@0.8.6",
  "moonbitstack/moondb@0.2.0",
  "moonbitstack/moonmysql@0.7.3",
}
