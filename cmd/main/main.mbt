// mldong-moon 装配入口 —— MysqlConfig(env) → dao → service → 路由注册 → listen
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）

///|
async fn main raise {
  let config = @mysql.MysqlConfig::from_env()
  let dao = @mysql.UserMysqlDao::{ config }
  let svc = @svc.UserServiceImpl::{ dao }
  let root = @mb.Module(ctx => {
    @ctrl.register(ctx, svc) catch {
      e => println("路由注册失败: \{e}")
    }
  })
  let app = @mb.App(root)
  defer app.close()
  let server = @mb.listen(host="127.0.0.1", port=18680)
  println("mldong-moon listening on http://127.0.0.1:18680")
  println("端点：POST /sys/user/{save,remove,update,detail,page}")
  app.serve(server)
}
