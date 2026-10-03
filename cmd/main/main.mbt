// mldong-moon 装配入口 —— MysqlConfig(env) → dao → service → 路由注册 → listen
// 起法：export MLDONG_DB_PWD=... && moon run --target wasm cmd/main   （默认 127.0.0.1:18680）

///|
async fn main raise {
  let config = @mysql.MysqlConfig::from_env()
  // user
  let user_dao = @mysql.UserMysqlDao::make(config)
  let user_svc = @svc.UserServiceImpl::{ dao: user_dao }
  // role
  let role_dao = @mysql.RoleMysqlDao::make(config)
  let role_svc = @svc.RoleServiceImpl::{ dao: role_dao }
  let root = @mb.Module(ctx => {
    @ctrl.register(ctx, user_svc) catch {
      e => println("user 路由注册失败: \{e}")
    }
    @ctrl.register_role(ctx, role_svc) catch {
      e => println("role 路由注册失败: \{e}")
    }
  })
  let app = @mb.App(root)
  defer app.close()
  let server = @mb.listen(host="127.0.0.1", port=18680)
  println("mldong-moon listening on http://127.0.0.1:18680")
  println("端点：POST /sys/user/* /sys/role/*（save/remove/update/detail/page）")
  app.serve(server)
}
