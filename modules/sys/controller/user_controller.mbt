// sys_user 控制器 —— 手写薄端点（boot2 风格：校验在 dto、业务在 service、响应工具在 core）
// URL /sys/user/{save,remove,update,detail,page} 对齐 mldong 接口契约
// 权限码预留（guard 下一轮挂）：save=sys:user:save remove=sys:user:remove
// update=sys:user:update detail=sys:user:detail page=sys:user:page

///|
/// 权限码片段——与端点同文件声明（对齐 boot2 @SaCheckPermission 注解位置）。
/// 全部显式 rule：URL 与码不一致的场景（boot2 /sys/user/locked 双码 OR 那类）就改这里，
/// 推导只作兜底不依赖。guard 下一轮挂时这些码已是最终形状。
pub fn user_policy() -> @guard.RoutePolicy {
  // locked/unLocked 双码 OR：RouteRule 多码默认 AND（叠加注解语义），OR 显式置 perm_mode
  let locked_rule = @guard.RouteRule::make("/sys/user/locked", ["sys:user:locked", "sys:user:unLocked"])
  locked_rule.perm_mode = @port.Or
  let un_locked_rule = @guard.RouteRule::make("/sys/user/unLocked", ["sys:user:locked", "sys:user:unLocked"])
  un_locked_rule.perm_mode = @port.Or
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/user/save", ["sys:user:save"]))
    .rule(@guard.RouteRule::make("/sys/user/remove", ["sys:user:remove"]))
    .rule(@guard.RouteRule::make("/sys/user/update", ["sys:user:update"]))
    .rule(@guard.RouteRule::make("/sys/user/detail", ["sys:user:detail"]))
    .rule(@guard.RouteRule::make("/sys/user/page", ["sys:user:page"]))
    .rule(@guard.RouteRule::make("/sys/user/grantRole", ["sys:user:grantRole"]))
    .rule(@guard.RouteRule::make("/sys/user/getDeptUserTree", ["sys:user:getDeptUserTree"]))
    // locked/unLocked 双端点共用双码 OR（boot2 SaMode.OR 同构）——URL 与码不一致的样板场景
    .rule(locked_rule)
    .rule(un_locked_rule)
    .rule(@guard.RouteRule::make("/sys/user/resetPassword", ["sys:user:resetPassword"]))
    .rule(@guard.RouteRule::make("/sys/user/select", ["sys:user:select"]))
    .rule(@guard.RouteRule::make("/sys/user/onlineUserList", ["sys:user:onlineUserList"]))
    // 个人中心族（permCode/info/updateInfo/updatePwd/updateAvatar/onlineDevice）不在此列：
    // main 关掉 by_convention 后，未列端点一律只验登录——boot2 同语义（notes 里写 sys:user:xxx 只是文档）
}

///|
pub fn[S : @port.TokenStore, P : @port.PermissionProvider, T : @svc.UserService, R : @svc.RbacService] register(
  ctx : @mb.ModuleContext,
  svc : T,
  rbac : R,
  g : @mbguard.Guard[S, P],
  auth : @app.TokenAuth[S, P],
  /// 部门全量取数闭包（getDeptUserTree 用；module 接线到 dept dao，user 侧零 dept dao 依赖）
  dept_list : async () -> Array[@entity.Dept] raise @core.MldongError,
) -> Unit raise {
  // 添加用户
  let save_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id = svc.save(ctx, @dto.parse_save(@web.json_body(request)))
    @core.ok_data(Json::string(id.to_string()))
  })
  // 删除用户（逻辑删，ids 支持字符串/数字）
  let remove_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.remove_by_ids(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  // 修改用户
  let update_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    svc.update(ctx, @dto.parse_update(@web.json_body(request)))
    @core.ok_empty()
  })
  // 查询单个用户
  let detail_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let id : Int64 = match @core.get_i64(@web.json_body(request), "id") {
      Some(n) => n
      None => 0L
    }
    @core.ok_data(@dto.user_json(svc.find_by_id(ctx, id)))
  })
  // 用户授权角色（user_role 全量替换）
  let grant_role_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let user_id = @core.get_i64(body, "userId").unwrap_or(0L)
    if user_id <= 0L {
      raise @core.MldongError::InvalidInput("用户ID不能为空")
    }
    rbac.grant_user_roles(user_id, @core.get_i64_array(body, "roleIds"))
    @core.ok_empty()
  })
  // ---- 管理-用户状态族（boot2 locked/unLocked/resetPassword/select 同位）----

  // 锁定（is_locked=1）
  let locked_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let _ = svc.set_locked(ctx, @core.get_ids(@web.json_body(request)), 1)
    @core.ok_empty()
  })
  // 解锁（is_locked=0；与 locked 共用双码 OR）
  let un_locked_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let _ = svc.set_locked(ctx, @core.get_ids(@web.json_body(request)), 0)
    @core.ok_empty()
  })
  // 重置为默认密码（超管跳过，boot2 resetPwd 同语义）
  let reset_password_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let _ = svc.reset_password(ctx, @core.get_ids(@web.json_body(request)))
    @core.ok_empty()
  })
  // 用户下拉选项（label=姓名，value=id 串）
  let select_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let users = svc.select_options(ctx, @core.text_or(@web.json_body(request), "keywords", ""))
    let arr : Array[Json] = []
    for u in users {
      arr.push({ "label": u.real_name, "value": u.id.to_string() })
    }
    @core.ok_data(Json::array(arr))
  })

  // ---- 个人中心族（principal_of 取登录主体；main 已关推导，这些端点只验登录）----

  // 当前权限标识（boot2 permCode = StpUtil.getPermissionList()）
  let perm_code_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let codes = match @mbguard.principal_of(request) {
      Some(p) => p.permissions
      None => []
    }
    let arr : Array[Json] = []
    for c in codes {
      arr.push(Json::string(c))
    }
    @core.ok_data(Json::array(arr))
  })
  // 个人信息（用户字段 + roleCodes/roleNames/superAdmin）
  let info_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let p = match @mbguard.principal_of(request) {
      Some(p) => p
      None => raise @core.MldongError::NotFound("会话无主体")
    }
    let uid = match @svc.parse_user_id(p.login_id) {
      Some(id) => id
      None => raise @core.MldongError::NotFound("登录主体非法: \{p.login_id}")
    }
    @core.ok_data(@dto.user_info_json(svc.find_by_id(ctx, uid), p.roles, p.super_admin))
  })
  // 修改个人信息（只动 realName/nickName/sex；id 取自登录主体，body 里的 id 不信任）
  let update_info_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let p = match @mbguard.principal_of(request) {
      Some(p) => p
      None => raise @core.MldongError::NotFound("会话无主体")
    }
    let uid = match @svc.parse_user_id(p.login_id) {
      Some(id) => id
      None => raise @core.MldongError::NotFound("登录主体非法: \{p.login_id}")
    }
    let req = @dto.parse_info(@web.json_body(request))
    req.id = uid
    svc.update_info(ctx, req)
    @core.ok_empty()
  })
  // 修改个人密码（验旧密）
  let update_pwd_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let p = match @mbguard.principal_of(request) {
      Some(p) => p
      None => raise @core.MldongError::NotFound("会话无主体")
    }
    let uid = match @svc.parse_user_id(p.login_id) {
      Some(id) => id
      None => raise @core.MldongError::NotFound("登录主体非法: \{p.login_id}")
    }
    let body = @web.json_body(request)
    svc.update_password(ctx, uid, @core.text_or(body, "oldPassword", ""), @core.text_or(body, "newPassword", ""))
    @core.ok_empty()
  })
  // 修改个人头像（avatar 存 URL 串）
  let update_avatar_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let p = match @mbguard.principal_of(request) {
      Some(p) => p
      None => raise @core.MldongError::NotFound("会话无主体")
    }
    let uid = match @svc.parse_user_id(p.login_id) {
      Some(id) => id
      None => raise @core.MldongError::NotFound("登录主体非法: \{p.login_id}")
    }
        svc.update_avatar(ctx, uid, @core.text_or(@web.json_body(request), "avatar", ""))
    let _ = uid
    @core.ok_empty()
  })

  // ---- 在线用户族（moon-token list_online 枚举 + DB join 名称；boot2 onlineUserList/onlineDevice 同位）----

  // 枚举全部在线行（翻尽游标；moon-token 单页硬上限 100）
  let all_online = async fn() -> Array[@app.OnlineRow] raise @port.TokenError {
    let rows : Array[@app.OnlineRow] = []
    let mut cursor = ""
    let mut guard_count = 0
    while guard_count < 100 {
      let page = auth.list_online(@port.SessionFilter::all(), cursor, 100)
      for row in auth.load_online(page) {
        rows.push(row)
      }
      if page.next_cursor.is_empty() {
        break
      }
      cursor = page.next_cursor
      guard_count = guard_count + 1
    }
    rows
  }
  // 空 User 占位（会话人已删账号时兜底，防在线页 500）
  let ghost_user = fn(id : Int64) -> @entity.User {
    {
      id, user_name: "", real_name: "", nick_name: None, avatar: None,
      password: None, salt: None, mobile_phone: None, tel: None, email: None,
      admin_type: None, sex: None, is_locked: None, dept_id: None, post_id: None,
      remark: None, create_time: None, create_user: None, update_time: None,
      update_user: None, is_deleted: None,
    }
  }
  // token 级行装配（超管的 token 只对本人可见，其余见 "-"；boot2 同规则）
  let token_view = fn(row : @app.OnlineRow, users : Map[String, @entity.User], current_token : String, viewer_id : String) -> @dto.OnlineTokenView {
    let l = row.listing
    let uid_str = l.login_id
    let u = match users.get(uid_str) {
      Some(u) => u
      None => ghost_user(match @svc.parse_user_id(uid_str) {
        Some(n) => n
        None => 0L
      })
    }
    let super_admin = u.admin_type == Some(1)
    let ip = match row.session {
      Some(s) =>
        match s.extra.get("ip") {
          Some(v) => v
          None => ""
        }
      None => ""
    }
    let ua = match row.session {
      Some(s) =>
        match s.extra.get("ua") {
          Some(v) => v
          None => ""
        }
      None => ""
    }
    {
      token_value: if super_admin && uid_str != viewer_id { "-" } else { l.token },
      device: l.device,
      is_current: l.token == current_token,
      login_time: l.login_time,
      expire_at: l.expire_at,
      login_ip: ip,
      login_browser: ua,
      super_admin,
    }
  }
  // 在线用户列表（按登录人分组；keywords 过滤 = 用户名/姓名子串或数字 id 精确，boot2 同口径——
  // 过滤在页内做：moon-token 只开放精确字段过滤，全量模糊扫是鉴权库明确不给的口子）
  let online_user_list_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let keywords = @core.text_or(@web.json_body(request), "keywords", "")
    let viewer = match @mbguard.principal_of(request) {
      Some(p) => p
      None => raise @core.MldongError::NotFound("会话无主体")
    }
    let current_token = @web.token_of(request)
    let rows = all_online() catch {
      e => raise @core.MldongError::Internal(e.message())
    }
    // 登录人集合 → 一次批量取用户
    let ids : Array[Int64] = []
    let seen : Map[String, Bool] = Map([], capacity=0)
    for row in rows {
      let lid = row.listing.login_id
      if seen.get(lid) is None {
        let _ = seen.set(lid, true)
        match @svc.parse_user_id(lid) {
          Some(n) => ids.push(n)
          None => ()
        }
      }
    }
    let users_map : Map[String, @entity.User] = Map([], capacity=0)
    for u in svc.find_by_ids(ctx, ids) {
      let _ = users_map.set(u.id.to_string(), u)
    }
    // 分组（保持最新在前的枚举序）
    let order : Array[String] = []
    let grouped : Map[String, Array[@app.OnlineRow]] = Map([], capacity=0)
    for row in rows {
      let lid = row.listing.login_id
      match grouped.get(lid) {
        Some(arr) => arr.push(row)
        None => {
          let _ = grouped.set(lid, [row])
          order.push(lid)
        }
      }
    }
    let out : Array[Json] = []
    for lid in order {
      let tokens_rows = match grouped.get(lid) {
        Some(arr) => arr
        None => []
      }
      if tokens_rows.is_empty() {
        continue
      }
      let u = match users_map.get(lid) {
        Some(u) => u
        // 账号已删的会话不展示（boot2 取不到 LoginUser 也是 skip 语义）
        None => continue
      }
      if !keywords.is_empty() {
        let numeric_hit = match @svc.parse_user_id(keywords) {
          Some(n) => n == u.id
          None => false
        }
        if !(u.user_name.contains(keywords) || u.real_name.contains(keywords) || numeric_hit) {
          continue
        }
      }
      let tokens : Array[@dto.OnlineTokenView] = []
      for row in tokens_rows {
        tokens.push(token_view(row, users_map, current_token, lid))
      }
      let first = tokens_rows[0]
      let timeout = (first.listing.expire_at - @port.now_ms()) / 1000L
      out.push(@dto.online_user_json({
        id: lid,
        user_name: u.user_name,
        real_name: u.real_name,
        is_current: lid == viewer.login_id,
        super_admin: u.admin_type == Some(1),
        login_time: first.listing.login_time,
        expire_at: first.listing.expire_at,
        timeout: if timeout > 0L { timeout } else { 0L },
        tokens,
      }))
    }
    @core.ok_data(Json::array(out))
  })
  // 当前登录人的在线设备（平铺 token 级行）
  let online_device_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let viewer = match @mbguard.principal_of(request) {
      Some(p) => p
      None => raise @core.MldongError::NotFound("会话无主体")
    }
    let current_token = @web.token_of(request)
    let page = auth.list_online(@port.SessionFilter::make(viewer.login_id, ""), "", 100) catch {
      e => raise @core.MldongError::Internal(e.message())
    }
    let rows = auth.load_online(page) catch {
      e => raise @core.MldongError::Internal(e.message())
    }
    let ids : Array[Int64] = []
    match @svc.parse_user_id(viewer.login_id) {
      Some(n) => ids.push(n)
      None => ()
    }
    let users_map : Map[String, @entity.User] = Map([], capacity=0)
    for u in svc.find_by_ids(ctx, ids) {
      let _ = users_map.set(u.id.to_string(), u)
    }
    let out : Array[Json] = []
    for row in rows {
      out.push(@dto.online_token_json(token_view(row, users_map, current_token, viewer.login_id)))
    }
    @core.ok_data(Json::array(out))
  })

  // 分页查询用户列表（关联 dept/post + m_ 动态条件）
  let page_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let req = @dto.parse_page(@web.json_body(request))
    let (total, rows) = svc.page(ctx, req)
    let arr : Array[Json] = []
    for row in rows {
      arr.push(@dto.page_row_json(row))
    }
    @core.ok_page(req.page_num, req.page_size, total, arr)
  })
  g.post(ctx, "/sys/user/save", save_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/remove", remove_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/update", update_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/detail", detail_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/page", page_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/grantRole", grant_role_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/locked", locked_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/unLocked", un_locked_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/resetPassword", reset_password_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/select", select_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/permCode", perm_code_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/info", info_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/updateInfo", update_info_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/updatePwd", update_pwd_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/updateAvatar", update_avatar_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/onlineUserList", online_user_list_handler) catch {
    e => raise e
  }
  g.post(ctx, "/sys/user/onlineDevice", online_device_handler) catch {
    e => raise e
  }
  // 部门用户树（boot2 /sys/user/getDeptUserTree 同位）：部门节点（nodeType=1，disabled 不可选）
  // 挂用户叶（nodeType=2）；用户按部门分组一次取全量，避免逐部门 N 查
  let dept_user_tree_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let ctx = @web.ctx_of(request)
    let tree = @svc.build_dept_tree(dept_list())
    let users_by_dept : Map[String, Array[Json]] = Map([], capacity=0)
    for u in svc.list_simple(ctx) {
      let key = match u.dept_id {
        Some(d) => d.to_string()
        None => continue
      }
      let node : Json = {
        "label": Json::string(u.real_name),
        "value": Json::string(u.id.to_string()),
        "nodeType": Json::string("2"),
        "disabled": Json::boolean(false),
        "children": Json::array([]),
      }
      match users_by_dept.get(key) {
        Some(arr) => arr.push(node)
        None => {
          let _ = users_by_dept.set(key, [node])
        }
      }
    }
    let arr : Array[Json] = []
    for n in tree {
      arr.push(dept_user_node(n, users_by_dept))
    }
    @core.ok_data(Json::array(arr))
  })
  g.post(ctx, "/sys/user/getDeptUserTree", dept_user_tree_handler) catch {
    e => raise e
  }
}

///|
/// 部门用户树节点（boot2 DeptUserTreeVO：label/value/nodeType/disabled/children）
fn dept_user_node(n : @svc.DeptNode, users_by_dept : Map[String, Array[Json]]) -> Json {
  let children : Array[Json] = []
  match users_by_dept.get(n.dept.id.to_string()) {
    Some(users) =>
      for u in users {
        children.push(u)
      }
    None => ()
  }
  for c in n.children {
    children.push(dept_user_node(c, users_by_dept))
  }
  {
    "label": Json::string(n.dept.name),
    "value": Json::string(n.dept.id.to_string()),
    "nodeType": Json::string("1"),
    "disabled": Json::boolean(true),
    "children": Json::array(children),
  }
}
