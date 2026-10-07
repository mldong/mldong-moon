// RBAC 授权关系控制器 —— boot2 RbacController 同位（角色-菜单 / 用户-角色 / 角色下用户）。
// 载荷形状按 vben5 实测：saveRoleMenu = [{roleId,menuId}]（空数组补 {roleId} 即清空该角色全部菜单，
// 删旧插新全量覆盖）；saveUserRole/removeUserRole = [{userId,roleId}] 逐对。

///|
pub fn rbac_policy() -> @guard.RoutePolicy {
  let role_menu_ids_rule = @guard.RouteRule::make(
    "/sys/rbac/roleMenuIds",
    ["sys:rbac:roleMenuIds", "sys:rbac:saveRoleMenu"],
  )
  role_menu_ids_rule.perm_mode = @port.Or
  @guard.RoutePolicy::new()
    .rule(@guard.RouteRule::make("/sys/rbac/saveRoleMenu", ["sys:rbac:saveRoleMenu"]))
    .rule(role_menu_ids_rule)
    .rule(@guard.RouteRule::make("/sys/rbac/saveUserRole", ["sys:rbac:saveUserRole"]))
    .rule(@guard.RouteRule::make("/sys/rbac/removeUserRole", ["sys:rbac:removeUserRole"]))
    .rule(
      @guard.RouteRule::make("/sys/rbac/userListByRoleId", ["sys:rbac:userListByRoleId"]),
    )
    .rule(
      @guard.RouteRule::make(
        "/sys/rbac/userListExcludeRoleId",
        ["sys:rbac:userListExcludeRoleId"],
      ),
    )
    // 数据范围授权在 boot2 RoleController（sys:role:grantDataScope），moon 归拢在 rbac 面
    .rule(@guard.RouteRule::make("/sys/role/grantDataScope", ["sys:role:grantDataScope"]))
}

///|
/// body.id（数字/字符串二态取 Int64）
fn rbac_id_of(body : Json, key : String) -> Int64 {
  @core.get_i64(body, key).unwrap_or(0L)
}

///|
/// [{userId,roleId}] / [{roleId,menuId}] 数组对提取
fn rbac_pairs_of(body : Json, a_key : String, b_key : String) -> Array[(Int64, Int64)] {
  let pairs : Array[(Int64, Int64)] = []
  match body {
    // 形状1：顶层数组 [{roleId,menuId}]（saveRoleMenu 前端实传顶层数组）
    Array(items) =>
      for it in items {
        let a = @core.get_i64(it, a_key).unwrap_or(0L)
        let b = @core.get_i64(it, b_key).unwrap_or(0L)
        if a != 0L {
          pairs.push((a, b))
        }
      }
    // 形状2：{list: [...]} / 对象（saveUserRole 视图层传数组；兼容包一层）
    Object(_) => {
      let list = match body {
        Object(m) => match m.get("list") {
          Some(Array(items)) => items
          _ => []
        }
        _ => []
      }
      for it in list {
        let a = @core.get_i64(it, a_key).unwrap_or(0L)
        let b = @core.get_i64(it, b_key).unwrap_or(0L)
        if a != 0L {
          pairs.push((a, b))
        }
      }
    }
    _ => ()
  }
  pairs
}

///|
pub fn[
  S : @port.TokenStore,
  P : @port.PermissionProvider,
  R : @dao.RbacDao,
] register_rbac(
  ctx : @mb.ModuleContext,
  dao : R,
  g : @mbguard.Guard[S, P],
) -> Unit raise {
  // 角色-菜单授权（删旧插新全量覆盖；[{roleId}] 空补语义=清空）
  let save_role_menu_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let pairs = rbac_pairs_of(body, "roleId", "menuId")
    if pairs.is_empty() {
      raise @core.MldongError::InvalidInput("roleId 不能为空")
    }
    let role_id = pairs[0].0
    let menu_ids : Array[Int64] = []
    for pair in pairs {
      if pair.1 != 0L {
        menu_ids.push(pair.1)
      }
    }
    dao.grant_menus(role_id, menu_ids)
    @core.ok_empty()
  })
  // 角色的菜单 id 清单（授权页回显）
  let role_menu_ids_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let role_id = rbac_id_of(@web.json_body(request), "roleId")
    if role_id == 0L {
      raise @core.MldongError::InvalidInput("roleId 不能为空")
    }
    let ids = dao.find_menu_ids_by_role(role_id)
    let arr : Array[Json] = []
    for id in ids {
      arr.push(Json::string(id.to_string()))
    }
    @core.ok_data(Json::array(arr))
  })
  // 用户-角色增量授权
  let save_user_role_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let pairs = rbac_pairs_of(@web.json_body(request), "userId", "roleId")
    if pairs.is_empty() {
      raise @core.MldongError::InvalidInput("userId 不能为空")
    }
    dao.grant_user_role_pairs(pairs)
    @core.ok_empty()
  })
  // 用户-角色移除
  let remove_user_role_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let pairs = rbac_pairs_of(@web.json_body(request), "userId", "roleId")
    if pairs.is_empty() {
      raise @core.MldongError::InvalidInput("userId 不能为空")
    }
    dao.remove_user_role_pairs(pairs)
    @core.ok_empty()
  })
  // 角色下用户分页 / 排除该角色用户分页（m_ keywords 通用条件叠加）
  let user_page_fn = async fn(request : @mb.Request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let role_id = rbac_id_of(body, "roleId")
    if role_id == 0L {
      raise @core.MldongError::InvalidInput("roleId 不能为空")
    }
    let page_num = @core.get_int(body, "pageNum").unwrap_or(1)
    let page_size = @core.get_int(body, "pageSize").unwrap_or(10)
    if page_num <= 0 || page_size <= 0 {
      raise @core.MldongError::InvalidInput("分页参数非法")
    }
    let keywords = @core.text_or(body, "keywords", "")
    let w = @core.where_()
    if !keywords.is_empty() {
      let like = "%\{keywords}%"
      let _ = w.raw(
        "(user_name LIKE ? OR real_name LIKE ?)",
        [@core.S(like), @core.S(like)],
      )
    }
    let _ = w.append(@core.parse_m_params(body, exclude=["pageNum", "pageSize", "keywords", "searchKeys", "orderBy", "roleId"]))
    let in_role = path_of_url(request) == "/sys/rbac/userListByRoleId"
    let (total, rows) = dao.page_users_by_role(role_id, in_role, w, page_num, page_size)
    let arr : Array[Json] = []
    for u in rows {
      arr.push(@dto.user_json(u))
    }
    @core.ok_page(page_num, page_size, total, arr)
  }
  let user_by_role_handler : @mb.Handler = @web.wrap(user_page_fn)
  let user_exclude_handler : @mb.Handler = @web.wrap(user_page_fn)
  g.post(ctx, "/sys/rbac/saveRoleMenu", save_role_menu_handler)
  g.post(ctx, "/sys/rbac/roleMenuIds", role_menu_ids_handler)
  g.post(ctx, "/sys/rbac/saveUserRole", save_user_role_handler)
  g.post(ctx, "/sys/rbac/removeUserRole", remove_user_role_handler)
  g.post(ctx, "/sys/rbac/userListByRoleId", user_by_role_handler)
  g.post(ctx, "/sys/rbac/userListExcludeRoleId", user_exclude_handler)
  // 数据范围授权（boot2 RoleController.grantDataScope：{id,dataScope,deptIdList} →
  // sys_role.data_scope 直更 + sys_role_dept 全量替换；dataScope 缺省=仅本人）
  let grant_data_scope_handler : @mb.Handler = @web.wrap(async fn(request) -> Json raise @core.MldongError {
    let body = @web.json_body(request)
    let role_id = rbac_id_of(body, "id")
    if role_id == 0L {
      @core.fail(99999999, "id不能为空")
    } else {
      dao.grant_data_scope(
        role_id,
        @core.get_int(body, "dataScope"),
        @core.get_i64_array(body, "deptIdList"),
      )
      @core.ok_empty()
    }
  })
  g.post(ctx, "/sys/role/grantDataScope", grant_data_scope_handler)
}

///|
/// 当前请求路径（同一 handler 双路由分流用）
fn path_of_url(request : @mb.Request) -> String {
  request.path.to_owned()
}
