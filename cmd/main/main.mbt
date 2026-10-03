// mldong-moon 装配入口 —— 每模块一行（模块自注册：dao/service 构造与路由注册收进模块内）
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）

///|
async fn main raise {
  let config = @core.MysqlConfig::from_env()
  let root = @mb.Module(ctx => {
    ctx.use_(@sys.module(config)) catch {
      e => abort("sys 模块挂载失败: \{e}")
    }
    // 将来新模块各一行：
    // ctx.use_(@dev.module(config)) catch { e => abort("dev 模块挂载失败: \{e}") }
    // ctx.use_(@biz.module(config)) catch { e => abort("biz 模块挂载失败: \{e}") }
  })
  let app = @mb.App(root)
  defer app.close()
  let server = @mb.listen(host="127.0.0.1", port=18680)
  println("mldong-moon listening on http://127.0.0.1:18680")
  println("端点：POST /sys/user/* /sys/role/*（save/remove/update/detail/page）")
  app.serve(server)
}
