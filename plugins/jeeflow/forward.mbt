// Plugin 实现 —— descriptor 趟一（纯数据）+ initialize 趟二（供数预载 + 引擎装配 + 注册路由）。
// initialize 时序：经 SysQueryApi 预载 user/dept/role 快照 → 组引擎 Ctx（三个同步 SPI 闭包
// 读快照）→ Facade::make → 逐条注册 /wf/{action} 路由（handler 捕获各自 action，全转发
// Facade::flow；operator=登录主体 login_id 注入 args）。

///|
fn i64s(v : Int64?) -> String {
  match v {
    Some(n) => n.to_string()
    None => ""
  }
}

///|
fn s_or(v : String?, fallback : String) -> String {
  match v {
    Some(s) => s
    None => fallback
  }
}

///|
fn wf_handler(
  facade : @facade.Facade[@jrepo.MysqlRepository, @jrepo.MysqlRepository],
  action : String,
) -> @mb.Handler {
  @web.wrap(async fn(request) -> Json raise @core.MldongError {
    // body 容错：空 body 当空对象（与 jeeflow demo 同口径），坏 JSON 交 wrap 统一转 99990001
    let body = @web.json_body(request) catch { _ => @jf.empty_object() }
    let args : Map[String, Json] = match body {
      Json::Object(m) => m
      _ => raise @core.MldongError::InvalidInput("body 必须是 JSON 对象")
    }
    let principal = @web.ctx_of(request)
    args["operator"] = @jf.string_of(principal.login_id)
    facade.flow(action, args) catch {
      // flow 出口已转 {code,msg,data} 信封；残余 raise 属未预期形状（async 隐含 Error）
      e => raise @core.MldongError::Internal("jeeflow flow 未预期异常: \{e}")
    }
  })
}

///|
/// 包内 upcast 消费 Plugin impl（装载器经此取 trait object）
pub fn JeeflowPlugin::as_plugin(self : JeeflowPlugin) -> &@api.Plugin {
  self
}

///|
pub extend JeeflowPlugin with @api.Plugin::{descriptor, on_enable, initialize, on_disable}

///|
pub impl @api.Plugin for JeeflowPlugin with fn descriptor(
  self : JeeflowPlugin,
) -> @api.PluginDescriptor {
  let _ = self
  jeeflow_descriptor()
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn initialize(
  self : JeeflowPlugin,
  ctx : @api.PluginContext,
) -> Unit raise {
  // ① 供数预载：用户分页拉全量（keyword 空 = 全量，含部门/岗位名）
  let user_map : Map[String, @api.SysUserDetail] = Map([])
  let mut loaded = 0
  let mut page = 1
  while true {
    // user_page 分页拉全量（含部门/岗位关联名）；快照供数见文件头
    let p = ctx.sys_query.user_page({ page, size: 200, keywords: "" })
    loaded += p.rows.length()
    for r in p.rows {
      user_map[r.id.to_string()] = r
    }
    if p.rows.is_empty() || loaded >= p.record_count {
      break
    }
    page += 1
  }
  println("[jeeflow] 供数预载：用户 \{loaded} 人")
  // ② 部门（领导/分管字段随行）
  let dept_map : Map[String, @api.SysDeptDetail] = Map([])
  for d in ctx.sys_query.dept_list() {
    dept_map[d.id.to_string()] = d
  }
  println("[jeeflow] 供数预载：部门 \{dept_map.length()} 个")
  // ③ 角色-用户对（按角色找人节点用）
  let role_map : Map[String, Array[String]] = Map([])
  for pair in ctx.sys_query.role_user_pairs() {
    match role_map.get(pair.role_code) {
      Some(arr) => arr.push(pair.user_id)
      None => role_map[pair.role_code] = [pair.user_id]
    }
  }
  println("[jeeflow] 供数预载：角色编码 \{role_map.length()} 个")
  // ④ 引擎装配：三个同步 SPI 闭包读快照（v1 妥协，见文件头）
  let repo = @jrepo.MysqlRepository::make(@jrepo.MysqlConfig::{
    host: self.config.host,
    port: self.config.port,
    user: self.config.user,
    password: self.config.password,
    database: self.config.database,
  })
  // ext 仓储 = 同一 MysqlRepository（wf_process_design 等外置表；boot4 JdbcProcessExtRepository 同位）
  let ectx = @spi.Ctx::new(repo, repo)
  let gen = @id_gen.DefaultIdGenerator::new(2L)
  let ectx2 = ectx.with_id_generator(fn() { gen.next_id() })
  let ectx3 = ectx2.with_user_provider(fn(uid : String) -> @model.UserInfo? {
    match user_map.get(uid) {
      Some(r) =>
        Some(
          @model.UserInfo::make(
            user_id=uid,
            real_name=r.real_name,
            dept_id=i64s(r.dept_id),
            dept_name=s_or(r.dept_name, ""),
            post_id=i64s(r.post_id),
            post_name=s_or(r.post_name, ""),
          ),
        )
      None => None
    }
  })
  let ectx4 = ectx3.with_org_user_provider({
    find_dept_leaders: fn(dept_id) {
      match dept_map.get(dept_id) {
        Some(d) => d.leader_ids
        None => []
      }
    },
    find_dept_main_leaders: fn(dept_id) {
      match dept_map.get(dept_id) {
        Some(d) =>
          match d.main_leader_id {
            Some(id) => [id.to_string()]
            None => []
          }
        None => []
      }
    },
    find_by_role: fn(role_code) {
      match role_map.get(role_code) {
        Some(arr) => arr
        None => []
      }
    },
  })
  let _ = ectx4.with_user_search_provider({
    page: fn(query) {
      let kw = s_or(query.operator(), "")
      let matched : Array[@api.SysUserDetail] = []
      for u in user_map.values() {
        if kw.is_empty() || u.real_name.contains(kw) || u.user_name.contains(kw) {
          matched.push(u)
        }
      }
      matched.sort_by(fn(a, b) { a.id.compare(b.id) })
      let total = matched.length()
      let start = ((query.page_num() - 1L) * query.page_size()).to_int()
      let rows : Array[Map[String, Json]] = []
      let mut i = start
      while i < total && i < start + query.page_size().to_int() {
        let u = matched[i]
        let row : Map[String, Json] = Map([])
        row["id"] = @jf.string_of(u.id.to_string())
        row["userId"] = @jf.string_of(u.user_name)
        row["realName"] = @jf.string_of(u.real_name)
        row["deptName"] = @jf.string_of(s_or(u.dept_name, ""))
        rows.push(row)
        i += 1
      }
      @model.PageResult::new(query.page_num(), query.page_size(), total.to_int64(), rows)
    },
    find_by_id: fn(uid) {
      let row : Map[String, Json] = Map([])
      match user_map.get(uid) {
        Some(u) => {
          row["id"] = @jf.string_of(u.id.to_string())
          row["userId"] = @jf.string_of(u.user_name)
          row["realName"] = @jf.string_of(u.real_name)
          row["deptName"] = @jf.string_of(s_or(u.dept_name, ""))
          Some(row)
        }
        None => None
      }
    },
  })
  let facade = @facade.Facade::make(ectx4)
  // ⑤ 注册 /wf/{action} 路由（guard 链鉴权，权限码已在 policy 片段合入）
  for a in jeeflow_actions {
    ctx.routes.route("POST", "/wf/\{a}", wf_handler(facade, a))
  }
  println("[jeeflow] 路由注册完成：\{jeeflow_actions.length()} 条 POST /wf/{action}")
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn on_enable(
  self : JeeflowPlugin,
  ctx : @api.PluginContext,
) -> Unit {
  let _ = self
  let _ = ctx
}

///|
pub impl @api.Plugin for JeeflowPlugin with fn on_disable(
  self : JeeflowPlugin,
  ctx : @api.PluginContext,
) -> Unit raise {
  let _ = self
  let _ = ctx
}
