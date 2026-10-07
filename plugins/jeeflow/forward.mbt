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
  // ① 引擎装配：三个供数 SPI 闭包 = **live 调框架查询端口**（issues/146 引擎轮之后才成立——
  //    供数 SPI 是 async 形状 ⇒ 闭包里可以 await 查库；v1 的启动期全量快照已整段删除，
  //    运行期新增用户/调岗/换领导免重启即被解析，规模上限也随之消亡）。
  let sys = ctx.sys_query
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
  // IUserProvider：引擎给的 uid 就是 sys_user.id 的字符串形态（v1 快照的键同一口径）
  let live_user : (async (String) -> @model.UserInfo? raise @jerr.JeeflowError) = async fn(
    uid : String
  ) raise @jerr.JeeflowError {
    match @core.parse_i64_lenient(uid) {
      None => None
      Some(id) =>
        try {
          match sys.user_by_id(id) {
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
        } catch {
          // 框架查询端口报错不外泄成"发起炸掉"，也不静默当"没这个人"——
          // 引擎侧 add_user_info/dept_id_of 各自吞异常成空值，这里保留一次显式失败点
          _ => raise @jerr.Internal("sys_query.user_by_id 供数失败")
        }
    }
  }
  let ectx3 = ectx2.with_user_provider(live_user)
  // IOrgUserProvider：部门领导 / 主职领导 / 角色找人，逐次现查（dept_list 是小表，
  // 角色面 role_user_pairs 全量在册对——两者都按调用点过滤，不再常驻内存）
  let org_fns : @spi.OrgUserProviderFns = {
    find_dept_leaders: async fn(dept_id : String) raise @jerr.JeeflowError {
      match @core.parse_i64_lenient(dept_id) {
        None => []
        Some(id) =>
          try {
            match sys.dept_by_id(id) {
              Some(d) => d.leader_ids
              None => []
            }
          } catch {
            _ => raise @jerr.Internal("sys_query.dept_by_id 供数失败")
          }
      }
    },
    find_dept_main_leaders: async fn(dept_id : String) raise @jerr.JeeflowError {
      match @core.parse_i64_lenient(dept_id) {
        None => []
        Some(id) =>
          try {
            match sys.dept_by_id(id) {
              Some(d) =>
                match d.main_leader_id {
                  Some(ml) => [ml.to_string()]
                  None => []
                }
              None => []
            }
          } catch {
            _ => raise @jerr.Internal("sys_query.dept_by_id 供数失败")
          }
      }
    },
    find_by_role: async fn(role_code : String) raise @jerr.JeeflowError {
      try {
        let out : Array[String] = []
        for p in sys.role_user_pairs() {
          if p.role_code == role_code {
            out.push(p.user_id)
          }
        }
        out
      } catch {
        _ => raise @jerr.Internal("sys_query.role_user_pairs 供数失败")
      }
    },
  }
  let ectx4 = ectx3.with_org_user_provider(org_fns)
  // IUserSearchProvider：候选人搜索走 user_page 真分页（关键字模糊 + 服务端分页），
  // 不再是内存全表过滤
  let ectx5 = ectx4.with_user_search_provider({
    page: async fn(query : @model.PageQuery) raise @jerr.JeeflowError {
      let kw = s_or(query.operator(), "")
      try {
        let p = sys.user_page({
          page: query.page_num().to_int(),
          size: query.page_size().to_int(),
          keywords: kw,
        })
        let rows : Array[Map[String, Json]] = []
        for u in p.rows {
          rows.push(user_row(u))
        }
        @model.PageResult::new(
          query.page_num(),
          query.page_size(),
          p.record_count.to_int64(),
          rows,
        )
      } catch {
        _ => raise @jerr.Internal("sys_query.user_page 供数失败")
      }
    },
    find_by_id: async fn(uid : String) raise @jerr.JeeflowError {
      match @core.parse_i64_lenient(uid) {
        None => None
        Some(id) =>
          try {
            match sys.user_by_id(id) {
              Some(u) => Some(user_row(u))
              None => None
            }
          } catch {
            _ => raise @jerr.Internal("sys_query.user_by_id 供数失败")
          }
      }
    },
  })
  println("[jeeflow] 供数＝live 调框架查询端口（v1 启动期快照已删，运行期数据变更免重启生效）")
  // ④ 内置取人 handler 注册（boot4 WfHandlerRegistryConfig 同位；键＝spec/07 的 FQCN 原样串）
  //    没有这一步，流程 JSON 里的 "assignmentHandler" 在 moon 上无人解析（引擎按"未注册⇒记日志
  //    并照常落历史行续流"处理，静默不炸但零参与者）。注册后部门领导/分管/角色三族都经 org 闭包，
  //    而 org 闭包是 live 的 ⇒ 运行期改部门领导、改角色成员，下一张单即时生效（免重启）。
  let base : @itl.OrgAssignBase = { user: Some(live_user), org: Some(org_fns) }
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.OperatorAssignmentHandler",
    @itl.operator_assignment_handler(),
  )
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.OrgUserAssignmentHandlers$ApplicantDeptLeaderAssignmentHandler",
    @itl.applicant_dept_leader_handler(base, main=false),
  )
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.OrgUserAssignmentHandlers$ApplicantDeptMainLeaderAssignmentHandler",
    @itl.applicant_dept_leader_handler(base, main=true),
  )
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.OrgUserAssignmentHandlers$DeptLeaderAssignmentHandler",
    @itl.dept_leader_handler(base, main=false),
  )
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.OrgUserAssignmentHandlers$DeptMainLeaderAssignmentHandler",
    @itl.dept_leader_handler(base, main=true),
  )
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.FormFieldAssigneeHandler",
    @itl.form_field_assignee_handler(),
  )
  ectx5.register_assignment_handler(
    "com.mldong.jeeflow.interceptor.impl.OrgUserAssignmentHandlers$TaskRoleAssigneeHandler",
    @itl.task_role_assignee_handler(Some(org_fns)),
  )
  println("[jeeflow] 内置取人 handler 注册：7 支（operator/申请部门领导×2/当前部门领导×2/formField/taskRole）")
  // ⑥ wf 字典供数（boot4 WfProcessDictService / CustomDictService 的 moon 同位；契约＝UC-0432）
  //    条目逐字取自引擎注册表（零硬码）。两档分家：
  //      expose → 引擎 7 支枚举字典：进 customDictList（声明即曝光）且 getByDictType 应答；
  //      answer → 4 类运行时调度键（value=类全名）：只应答不曝光（owner 2026-09-26 拍板，断言③）。
  let jenums = @jmeta.EnumDictRegistry::new()
  let exposed = jenums.list_dict_keys()
  for key in exposed {
    let items = match jenums.get_dict(key) {
      Some(v) => v
      None => []
    }
    let pairs : Array[(String, String)] = []
    for it in items {
      pairs.push((it.value(), it.label()))
    }
    ctx.dicts.expose(wf_build_dict(wf_dict_label(key), key, pairs))
  }
  let jhandlers = @jmeta.HandlerRegistry::new()
  let spec : Array[(String, String, String)] = [
    ("wf_assignment_handler", "AssignmentHandler", "流程办理人处理器"),
    ("wf_candidate_handler", "CandidateHandler", "候选人处理器"),
    ("wf_flow_interceptor_pre_process", "FlowInterceptorPreProcess", "流程前置拦截器"),
    ("wf_flow_interceptor_post_process", "FlowInterceptorPostProcess", "流程后置拦截器"),
  ]
  for s in spec {
    let ms = jhandlers.list_handlers(s.1)
    let pairs : Array[(String, String)] = []
    for m in ms {
      pairs.push((m.class_name(), m.display_name()))
    }
    ctx.dicts.answer(wf_str_dict(s.2, s.0, pairs))
  }
  println("[jeeflow] wf 字典供数：引擎枚举 \{exposed.length()} 支曝光 + 4 类调度键只应答")
  let facade = @facade.Facade::make(ectx5)
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

///|
/// 引擎枚举字典的中文名（只影响 customDictList 的 name 列；key 与条目一律取自引擎注册表）
fn wf_dict_label(key : String) -> String {
  match key {
    "wf_process_define_state" => "流程定义状态"
    "wf_process_instance_state" => "流程实例状态"
    "wf_process_submit_type" => "流程提交类型"
    "wf_process_task_state" => "流程任务状态"
    "wf_process_task_type" => "流程任务类型"
    "wf_process_task_perform_type" => "流程任务办理类型"
    "wf_countersign_type" => "会签类型"
    _ => key
  }
}

///|
/// 引擎字典 → 框架 DictModel：码值全为整数就按数值码（data_type=2，boot2 int_dict 同位），
/// 否则退回字符串码档（data_type=1）。判定用现读的码表本身，不额外维护枚举清单。
fn wf_build_dict(name : String, key : String, pairs : Array[(String, String)]) -> @core.DictModel {
  let vals : Array[@core.IntVal] = []
  let mut numeric = pairs.length() > 0
  for kv in pairs {
    match @core.parse_i64_lenient(kv.0) {
      Some(n) => vals.push({ code: n.to_int(), label: kv.1 })
      None => numeric = false
    }
  }
  if numeric {
    @core.int_dict(name, key, vals)
  } else {
    wf_str_dict(name, key, pairs)
  }
}

///|
/// 字符串码档：dict_item_value 出字符串（UC-0426/框架 ext 同语义，None 不出键）
fn wf_str_dict(name : String, key : String, pairs : Array[(String, String)]) -> @core.DictModel {
  let items : Array[@core.DictItemModel] = []
  for kv in pairs {
    let it : @core.DictItemModel = {
      name: kv.1,
      dict_item_value: @jf.string_of(kv.0),
      dict_item_key: kv.0,
      ext: None,
    }
    items.push(it)
  }
  let m : @core.DictModel = { name, dict_key: key, data_type: Some(1), items }
  m
}

///|
/// 候选人行投影（IUserSearchProvider 的两个方法共用；键名＝前端候选人表口径）
fn user_row(u : @api.SysUserDetail) -> Map[String, Json] {
  let row : Map[String, Json] = Map([])
  row["id"] = @jf.string_of(u.id.to_string())
  row["userId"] = @jf.string_of(u.user_name)
  row["realName"] = @jf.string_of(u.real_name)
  row["deptName"] = @jf.string_of(s_or(u.dept_name, ""))
  row
}
