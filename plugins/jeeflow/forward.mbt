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
/// 引擎墙钟基准（issues/120「宿主必须注入」在 moon 栈的落点）。
/// MoonBit core 无时区出口 ⇒ 引擎默认臂恒 UTC；而委托时间窗、任务到期时刻这些**按墙钟串存库、
/// 按墙钟串比对**的值，是调用方按部署环境墙钟提交/回读的（其余 13 栈 host==容器==库会话钟，天然对齐）。
/// 不注入的后果不是"显示差 8 小时"而是功能失能：now±1h 的窗永不覆盖引擎眼中的 now ⇒
/// 委托代理人并进不去（工作流门禁 L2-17/L2-18/L2-29 三格同时红，10-08 实测）。
/// 基准取「数据所在库的会话墙钟 − UTC」的秒差：库在 +08 的部署里引擎随宿主，库配 UTC 的部署里
/// 引擎仍 UTC——不写死时区，也不需要一键包新增 env（compose 结构不动）。
/// `initialize` 是同步签名（装载器在装载事务里跑它）⇒ 取数落在首条 /wf 请求上，探测一次后缓存。
let clock_probed : Ref[Bool] = Ref(false)

async fn ensure_engine_clock(repo : @jrepo.MysqlRepository) -> Unit {
  if clock_probed.val {
    return ()
  }
  clock_probed.val = true
  let mut offset = 0L
  try {
    let conn = repo.open_raw()
    let rows = @jrepo.q(
      conn,
      "SELECT TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), NOW()) AS tz_off",
      [],
    )
    if rows.length() > 0 {
      match rows[0].by_name("tz_off") {
        Some(v) =>
          offset = match v {
            @moondb.Int64(n) => n
            @moondb.Int(n) => n.to_int64()
            @moondb.Double(d) => d.to_int64()
            @moondb.Text(s) => @core.parse_i64_lenient(s).unwrap_or(0L)
            _ => 0L
          }
        None => ()
      }
    }
    @client.MysqlConn::close(conn)
  } catch {
    // 探不到库钟就维持引擎默认（UTC）。静默回落是这台机器上最贵的一种错：
    // 基准错了不报红、只让整条委托链静默失能，所以必须留一行。
    e => println("[jeeflow] 库钟基准探测失败，引擎墙钟回落 UTC: " + e.message())
  }
  let base = offset
  @model.set_clock(Some(fn() { @model.format_unix_utc(@model.epoch_secs() + base) }))
  println("[jeeflow] 引擎墙钟基准＝库会话墙钟（UTC 偏移 \{offset / 3600L}h）")
}

///|
fn wf_handler(
  facade : @facade.Facade[@jrepo.MysqlRepository, @jrepo.MysqlRepository],
  repo : @jrepo.MysqlRepository,
  action : String,
) -> @mb.Handler {
  @web.wrap(async fn(request) -> Json raise @core.MldongError {
    // 引擎墙钟基准：首条请求探一次（旁路失能不拦请求，探测失败有留痕行）
    ensure_engine_clock(repo) catch {
      e => println("[jeeflow] 引擎墙钟基准注入异常: \{e}")
    }
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
  // ⑦ 站内信监听器（boot4 WfMessageProcessEventListener 那 383 行的 moon 同位；issues/146 缺口三）
  //    订阅引擎已发的三支：任务开始→提醒每位参与者、实例结束→提醒发起人、抄送创建→提醒抄送对象。
  //    这件事在 0.1.28 之前做不了：监听器是同步闭包，闭包里 await 不了写库。
  let notifier : (async (@event.ProcessEvent) -> Unit raise @jerr.JeeflowError) = async fn(
    ev : @event.ProcessEvent
  ) raise @jerr.JeeflowError {
    match ev.event_type() {
      @event.ProcessTaskStart => {
        // biz_id 记**实例 id** 不记 taskId（码 3 载荷带 instanceId 是 §11.3 的硬要求）：
        // 消费面（消息分页按实例归堆、移动端角标、门禁 L2-11）一律按实例查，记 taskId 查不到
        let inst_id = ev.data.get_i64_or("instanceId", 0L)
        for actor in ev.data.get_string_array("actors") {
          notify_wf(ctx, msg_todo, "您有新的待办事项", actor, inst_id, "/wf/task")
        }
      }
      @event.ProcessInstanceEnd => {
        // 码 2 的载荷只有 instanceId+state ⇒ 发起人从实例行现读（同一份引擎仓储）
        match @spi.ProcessRepository::find_instance_by_id(repo, ev.source_id()) {
          Some(inst) => notify_wf(
            ctx, msg_notice, "您的流程已办结", inst.operator, inst.instance_id, "/wf/instance"
          )
          None => ()
        }
      }
      @event.CcCreate => match ev.cc_actor_id() {
        Some(actor) => notify_wf(
          ctx, msg_notice, "流程抄送给您", actor, ev.source_id(), "/wf/instance"
        )
        None => ()
      }
      _ => ()
    }
  }
  let _ = ectx5.register_event_listener(notifier)
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
  // ⑦ persist 装配（写侧＝引擎 0.1.31 的 MysqlTableWriter，读侧＝框架 dev_query）：
  //   元数据来自框架 dev 查询面（information_schema 真列），表侧权限一律"可编辑"——字段权限
  //   落在**节点** properties.field 的 PERMISSION_* 上，引擎 intercept_sync 已按节点过滤，
  //   而本栈没有 dev_schema 台账可读（java 的 IDynamicMetaProvider 在那边读的就是台账）。
  //   写侧握**同一个 repo 实例** ⇒ 与 wf_* 共用事务槽（issues/149 的能力面）。
  //   未配置 persistMode 的定义在 intercept 首行就 return ⇒ 这一步对既有流程零行为增量。
  let dev = ctx.dev_query
  let meta_provider : @persist.DynamicMetaProviderFns = {
    load_table_meta: async fn(table : String) raise @jerr.JeeflowError {
      let cols = try {
        dev.table_columns(table)
      } catch {
        _ => raise @jerr.Internal("dev_query.table_columns 取元数据失败: \{table}")
      }
      if cols.is_empty() {
        // 表不存在 ⇒ None（引擎按"表元数据不存在"报错），与 java provider 返回 null 同语义
        None
      } else {
        let meta = @persist.TableMeta::make(table, table)
        for c in cols {
          meta.add_field(@persist.FieldMeta::make(c.name, c.data_type, c.name))
        }
        Some(meta)
      }
    },
  }
  let table_writer = @jrepo.MysqlTableWriter::from_repo(repo)
  let persist_itc = @persist.PersistPostInterceptor::make_from_provider(
    meta_provider,
    table_writer,
  )
  let _ = ectx5.register_interceptor(persist_itc.as_interceptor())
  println("[jeeflow] persist 装配：后置拦截器 1 支（元数据＝dev_query 内省）+ bizData 读侧已注册")
  // bizData 回显：java MetaTableReader#readByProcessInstance 同形——按 process_instance_id 取单行
  //（引擎传进来的 tableName 请求参数不参与选路，表名取自流程定义 relTableName）
  let ectx6 = ectx5.with_biz_data_reader(async fn(
    table : String,
    instance_id : Int64
  ) raise @jerr.JeeflowError {
    try {
      dev.row_by_column(table, "process_instance_id", instance_id)
    } catch {
      // 不外泄框架原文（引擎侧统一收口成「业务数据读取失败」+ 日志），这里只留一次显式失败点
      _ => raise @jerr.Internal("dev_query.row_by_column 业务数据读取失败")
    }
  })
  let facade = @facade.Facade::make(ectx6)
  // ⑤ 注册 /wf/{action} 路由（guard 链鉴权，权限码已在 policy 片段合入）
  for a in jeeflow_actions {
    ctx.routes.route("POST", "/wf/\{a}", wf_handler(facade, repo, a))
  }
  // 未知 action 兜底位：必须排在 47 条静态位**之后**注册（moonback Trie 先静态前缀后通配，
  // 顺序反了通配位会抢走真实 action 的命中）
  ctx.routes.route("POST", "/wf/*rest", wf_unknown_handler())
  println(
    "[jeeflow] 路由注册完成：\{jeeflow_actions.length()} 条 POST /wf/{action} + 1 条未知 action 兜底",
  )
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
/// sys_message.msg_type 两档（框架枚举 sys_message_msg_type：10＝待办消息 / 20＝通知消息；
/// 插件不依赖 moon-sys，码值在此对齐并注明出处——1＝系统通知那一档不承载 wf 流程消息）
let msg_todo : Int = 10
let msg_notice : Int = 20

///|
/// sys_message.biz_type 的**子分类段**，跨栈一律 "WORKFLOW"（Java 基座落 {appCode}_WORKFLOW、
/// goframe/salvo 落裸 WORKFLOW；moon 的投递面按 ctx.app_code 自动补前缀 ⇒ 这里只交子分类，
/// 消费侧 listByType/未读计数与门禁 L2-11 都只比子分类）
let wf_biz_type : String = "WORKFLOW"

///|
/// 未注册 action 的统一信封兜底（gate L1-05，以及 L2-13 的 `processDefine/save|update` 两腿）。
/// 其余 13 栈由控制器动态转发、引擎 dispatch 答「未知」；moon 是显式 47 位面，未声明即无此能力，
/// 所以兜底位**不进引擎**——否则等于给清单外的 action 开一条"仅登录"的可达面。
/// 文案取引擎 `UnknownAction` 原话（`未知 action: X`，码 ERR_BUSINESS=99999999），跨栈信封同形。
fn wf_unknown_handler() -> @mb.Handler {
  @web.wrap(fn(request) -> Json {
    let action = match request.params.get("rest") {
      Some(v) => v.to_owned()
      None => ""
    }
    @core.fail(99999999, @jerr.UnknownAction(action).message())
  })
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

///|
/// 发一条 wf 站内信（接收人是字符串 id：非数字直接跳过——流程参与者可以是 applicant/角色码等占位）
async fn notify_wf(
  ctx : @api.PluginContext,
  msg_type : Int,
  title : String,
  receiver : String,
  biz_id : Int64,
  url : String,
) -> Unit raise @jerr.JeeflowError {
  let uid_opt = @core.parse_i64_lenient(receiver)
  match uid_opt {
    None => ()
    Some(uid) =>
      try {
        ctx.messages.send({
          title,
          content: None,
          msg_type,
          biz_type: wf_biz_type,
          biz_id: Some(biz_id),
          receiver_user_id: uid,
          url: Some(url),
        })
      } catch {
        // 站内信是通知旁路：失败不外抛成流程错误（引擎侧逐监听器兜底已隔离）。
        // ⚠ 兜底会把这里的 raise 咽掉，所以先 println 留痕——否则"没发消息"查不到原因。
        e => {
          println("[jeeflow] 站内信投递失败 msg_type=\{msg_type} 收件人=\{receiver} 原因=\{@core.MldongError::message(e)}")
          raise @jerr.Internal("站内信投递失败")
        }
      }
  }
}
