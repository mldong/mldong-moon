// sys_menu 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait MenuService {
  /// ctx = 请求上下文（审计操作人/后续业务身份传播；controller @web.ctx_of 装配）
  async fn save(Self, @core.Ctx, @dto.MenuSaveReq) -> Int64 raise @core.MldongError
  async fn update(Self, @core.Ctx, @dto.MenuSaveReq) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, @core.Ctx, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, @core.Ctx, Int64) -> @entity.Menu raise @core.MldongError
  async fn page(Self, @core.Ctx, @dto.MenuPageReq) -> (Int, Array[@entity.Menu]) raise @core.MldongError
  /// 菜单树（boot2 /sys/menu/tree 同位：appCode 缺省取登录上下文，sort 升序建树，
  /// 孤儿挂回根；节点 = menu 全字段 + children + ext 空不出键）
  async fn tree(Self, @core.Ctx, @dto.MenuPageReq) -> Array[MenuNode] raise @core.MldongError
  /// 菜单平铺列表（boot2 /sys/menu/list 同位：orderBy 缺省 sort asc）
  async fn list(Self, @core.Ctx, @dto.MenuPageReq) -> Array[@entity.Menu] raise @core.MldongError
  /// 应用列表（boot2 /sys/menu/appList 同位：字典 app_list 域 → 静态回退）
  async fn app_list(Self) -> Array[Json] raise @core.MldongError
  /// 用户路由菜单（boot2 GET /menu/all|/getMenuList|/getArtDesignMenu 同位；
  /// version: v5 / v2 / art-design-pro——v2 用 hideMenu，art 多 authList/link 细节）
  async fn user_route_menu(Self, @core.Ctx, super_admin : Bool, version : String) -> Array[@dto.RouteNode] raise @core.MldongError
  /// 路由同步（boot2 /sys/menu/syncRoute 同位）：递归 upsert（appCode+code 键、
  /// isSync=1 才管）→ 域内删未同步集（is_sync=1 且不在集合）+ role_menu 级联；
  /// ⚠️ 空数组短路不删任何行；platform 域有种子，误调会清种子（e2e 只在隔离域测）
  async fn sync_route(Self, @core.Ctx, Array[@dto.SyncRouteReq]) -> Unit raise @core.MldongError
}

///|
pub(all) struct MenuServiceImpl[R] {
  dao : R
  /// 字典 app_list 域（模块装配闭包注入 dict 服务；空回退静态枚举）
  app_list_of : async () -> Array[Json] raise @core.MldongError
  /// 用户可见菜单 id 链（RBAC 供数闭包；非超管路由菜单过滤用）
  menu_ids_of : async (Int64, String) -> Array[Int64] raise @core.MldongError
  /// 用户权限码链（art-design-pro authList 非超管分支用）
  perms_of : async (Int64, String) -> Array[String] raise @core.MldongError
  /// role_menu 按菜单 id 清理（syncRoute 级联；RBAC 供数闭包）
  purge_role_menus : async (Array[Int64]) -> Unit raise @core.MldongError
}

///|
/// 请求域 appCode（ctx_of 已按头缺省 platform；豁免面 system ctx 补齐）
fn menu_app_code_of(ctx : @core.Ctx) -> String {
  match ctx.app_code {
    Some(a) => if !a.is_empty() { a } else { "platform" }
    None => "platform"
  }
}

///|
/// 平表 → 树（parent_id 内存建树，root=0；sort 已由取数层排好；孤儿挂回根，boot2 TreeTool 同语义）
pub(all) struct MenuNode {
  menu : @entity.Menu
  children : Array[MenuNode]
}

///|
pub fn build_menu_tree(items : Array[@entity.Menu]) -> Array[MenuNode] {
  let by_parent : Map[String, Array[@entity.Menu]] = Map([], capacity=0)
  let ids : Map[String, Bool] = Map([], capacity=0)
  for m in items {
    let _ = ids.set(m.id.to_string(), true)
  }
  for m in items {
    let key = match m.parent_id {
      Some(p) =>
        if p == 0L || ids.get(p.to_string()) is None {
          "0"
        } else {
          p.to_string()
        }
      None => "0"
    }
    match by_parent.get(key) {
      Some(arr) => arr.push(m)
      None => {
        let _ = by_parent.set(key, [m])
      }
    }
  }
  fn attach(m : @entity.Menu) -> MenuNode {
    let children = match by_parent.get(m.id.to_string()) {
      Some(arr) => arr.map(attach)
      None => []
    }
    { menu: m, children }
  }

  match by_parent.get("0") {
    Some(roots) => roots.map(attach)
    None => []
  }
}

///|
/// appCode 缺省过滤（boot2 tree/list/page 同语义：m_EQ_appCode 未显式给时取登录上下文）。
/// 豁免面登录不带头时 ctx.app_code 缺省 platform——种子菜单全在 platform 域
fn apply_app_code_default(ctx : @core.Ctx, w : @core.Wrapper) -> Unit {
  for c in w.conds {
    match c {
      @core.Eq(col, _) => if col == "app_code" {
        return
      }
      _ => ()
    }
  }
  let app = match ctx.app_code {
    Some(a) => if !a.is_empty() { a } else { "platform" }
    None => "platform"
  }
  let _ = w.eq("app_code", @core.S(app))
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn save(self, ctx, req) {
  // 唯一编码校验（boot2 checkUnique 同位一行调）
  self.dao.check_unique(req.code, None, "唯一编码已存在: " + req.code)
  let d : @entity.Menu = {
    id: @core.next_id(),
    app_code: req.app_code,
    parent_id: req.parent_id,
    name: req.name,
    code: req.code,
    menu_type: req.menu_type,
    sort: req.sort,
    path: req.path,
    component: req.component,
    icon: req.icon,
    is_show: req.is_show,
    is_link: req.is_link,
    url: req.url,
    enabled: req.enabled,
    open_type: req.open_type,
    is_cache: req.is_cache,
    is_sync: req.is_sync,
    variable: req.variable,
    pids: None,
    create_time: Some(@core.now_str()),
    create_user: ctx.user_id,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: Some(0),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn update(self, ctx, req) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 编码查重（排除自身）
  self.dao.check_unique(req.code, Some(req.id), "唯一编码已存在: " + req.code)
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Menu = {
    id: req.id,
    app_code: req.app_code,
    parent_id: req.parent_id,
    name: req.name,
    code: req.code,
    menu_type: req.menu_type,
    sort: req.sort,
    path: req.path,
    component: req.component,
    icon: req.icon,
    is_show: req.is_show,
    is_link: req.is_link,
    url: req.url,
    enabled: req.enabled,
    open_type: req.open_type,
    is_cache: req.is_cache,
    is_sync: req.is_sync,
    variable: req.variable,
    pids: None,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: ctx.user_id,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn remove_by_ids(self, _ctx, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn find_by_id(
  self,
  _ctx,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn page(self, _ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn tree(self, ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  apply_app_code_default(ctx, w)
  let items = self.dao.list_flat(w)
  build_menu_tree(items)
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn list(self, ctx, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  apply_app_code_default(ctx, w)
  self.dao.list_flat(w)
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn app_list(self) {
  let from_dict = ((self.app_list_of))() catch {
    _ => []
  }
  if from_dict.is_empty() {
    // boot2 MenuAppCodeEnum 静态回退（现役仅 PLATFORM）
    [{ "label": Json::string("平台"), "value": Json::string("platform") }]
  } else {
    from_dict
  }
}

///|
/// meta.variable 合并（ext_json_opt 非空对象才并——空不出键语义同源）
fn route_meta_merge(meta : Map[String, Json], variable : String?) -> Unit {
  match @core.ext_json_opt(variable) {
    Some(Object(map)) =>
      for k, v in map {
        let _ = meta.set(k, v)
      }
    _ => ()
  }
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn user_route_menu(
  self,
  ctx,
  super_admin,
  version,
) {
  let app = menu_app_code_of(ctx)
  let w = @core.where_().eq("enabled", @core.I(1)).eq("app_code", @core.S(app))
  // 只出目录(1)/菜单(2)——按钮(3)/接口(4)不进路由
  let _ = w.in_("type", [@core.I(@enums.menu_dir.code), @core.I(@enums.menu_item.code)])  // DB 列名 type（实体字段 menu_type 是保留字改名）
  let items = self.dao.list_flat(w)
  // 非超管按 RBAC 菜单 id 链过滤（boot2 rbacService.getMenuIdsByUserId 同位）
  let items = if super_admin {
    items
  } else {
    let uid = match ctx.user_id {
      Some(uid) => uid
      None => 0L
    }
    let ids = ((self.menu_ids_of)(uid, app)) catch {
      _ => []
    }
    let set : Map[String, Bool] = Map([], capacity=0)
    for i in ids {
      let _ = set.set(i.to_string(), true)
    }
    items.filter(fn(m) { set.get(m.id.to_string()) is Some(_) })
  }
  // 非超管权限码链（art authList 过滤用）
  let perms : Array[String] = if super_admin {
    []
  } else {
    let uid = match ctx.user_id {
      Some(uid) => uid
      None => 0L
    }
    ((self.perms_of)(uid, app)) catch {
      _ => []
    }
  }
  let nodes : Array[@dto.RouteNode] = []
  for m in items {
    let node = @dto.RouteNode::make(m.id, m.parent_id.unwrap_or(0L), m)
    let _ = node.meta.set(
      "order",
      match m.sort {
        Some(s) => Json::number(s.to_double())
        None => Json::null()
      },
    )
    let _ = node.meta.set("title", Json::string(m.name))
    route_meta_merge(node.meta, m.variable)
    match m.icon {
      Some(i) => if !i.is_empty() {
        let _ = node.meta.set("icon", Json::string(i))
      }
      None => ()
    }
    // 打开方式：LINK→link、IFRAME→iframeSrc（boot2 MenuOpenTypeEnum 同码表）
    // match 模式里不能放表达式路径（Some(@enums.open_link.code) 非法），用比较链
    if m.open_type == Some(@enums.open_link.code) {
      match m.url {
        Some(u) => { let _ = node.meta.set("link", Json::string(u)) }
        None => ()
      }
    } else if m.open_type == Some(@enums.open_iframe.code) {
      match m.url {
        Some(u) => { let _ = node.meta.set("iframeSrc", Json::string(u)) }
        None => ()
      }
    }
    // 隐藏菜单：isShow=NO → v2 用 hideMenu、其余 hideInMenu
    if m.is_show == Some(@enums.no.code) {
      let flag = if version == "v2" { "hideMenu" } else { "hideInMenu" }
      let _ = node.meta.set(flag, Json::boolean(true))
    }
    if m.is_cache == Some(@enums.yes.code) {
      let _ = node.meta.set("keepAlive", Json::boolean(true))
    }
    // meta.redirect 非空串时上提为节点 redirect（boot2 同语义）
    match node.meta.get("redirect") {
      Some(String(r)) => if !r.is_empty() {
        node.redirect = Some(r)
      }
      _ => ()
    }
    // art-design-pro 专属：link 带 isIframe 标记 + 菜单节点 authList
    if version == "art-design-pro" {
      let _ = node.meta.remove("link")
      match m.open_type {
        Some(3) =>
          match m.url {
            Some(u) => {
              let _ = node.meta.set("link", Json::string(u))
              let _ = node.meta.set("isIframe", Json::boolean(false))
            }
            None => ()
          }
        Some(2) =>
          match m.url {
            Some(u) => {
              let _ = node.meta.set("link", Json::string(u))
              let _ = node.meta.set("isIframe", Json::boolean(true))
            }
            None => ()
          }
        _ => ()
      }
      if m.menu_type == Some(@enums.menu_item.code) {
        if super_admin {
          let auth : Map[String, Json] = {
            "title": Json::string("超级管理员"),
            "authMark": Json::string("admin"),
          }
          let _ = node.meta.set("authList", Json::array([Json::object(auth)]))
        } else {
          // 子孙按钮/接口中权限码命中的项（boot2 findChildren 同语义）
          let own : Map[String, Bool] = Map([], capacity=0)
          for p in perms {
            let _ = own.set(p, true)
          }
          let auths : Array[Json] = []
          fn collect(pid : Int64) -> Unit {
            for c in items {
              if c.parent_id == Some(pid) {
                match own.get(c.code) {
                  Some(_) => {
                    let entry : Map[String, Json] = {
                      "title": Json::string(c.name),
                      "authMark": Json::string(c.code),
                    }
                    auths.push(Json::object(entry))
                  }
                  None => ()
                }
                collect(c.id)
              }
            }
          }
          collect(m.id)
          let _ = node.meta.set("authList", Json::array(auths))
        }
      }
    }
    nodes.push(node)
  }
  build_route_tree(nodes)
}

///|
/// 路由节点建树（parent_id 内存建树，root=0；孤儿挂回根）
pub fn build_route_tree(nodes : Array[@dto.RouteNode]) -> Array[@dto.RouteNode] {
  let by_parent : Map[String, Array[@dto.RouteNode]] = Map([], capacity=0)
  let ids : Map[String, Bool] = Map([], capacity=0)
  for n in nodes {
    let _ = ids.set(n.id.to_string(), true)
  }
  for n in nodes {
    let key = if n.parent_id == 0L || ids.get(n.parent_id.to_string()) is None {
      "0"
    } else {
      n.parent_id.to_string()
    }
    match by_parent.get(key) {
      Some(arr) => arr.push(n)
      None => {
        let _ = by_parent.set(key, [n])
      }
    }
  }
  fn attach(n : @dto.RouteNode) -> @dto.RouteNode {
    let children = match by_parent.get(n.id.to_string()) {
      Some(arr) => arr.map(attach)
      None => []
    }
    n.children = children
    n
  }

  match by_parent.get("0") {
    Some(roots) => roots.map(attach)
    None => []
  }
}

///|
/// 递归 upsert（boot2 saveMenu 同语义）：appCode+code 定位；新增全字段 +
/// is_sync=1；已存在且 is_sync=1 才更新（id/parent_id 不动）；深度上限 8；
/// isSync!=1 或 code=ADMIN 的项整枝跳过（不建不更不收 id）
async fn[T : @dao.MenuDao] sync_walk(
  svc : MenuServiceImpl[T],
  app : String,
  parent_id : Int64,
  pid_list : Array[String],
  items : Array[@dto.SyncRouteReq],
  level : Int,
  ids : Array[Int64],
) -> Unit raise @core.MldongError {
  if items.is_empty() || level > 8 {
    return
  }
  for item in items {
    if !(item.is_sync == Some(@enums.yes.code)) || item.code == "ADMIN" {
      continue
    }
    let existing = svc.dao.find_by_app_and_code(app, item.code)
    let menu_id = match existing {
      None => {
        let m : @entity.Menu = {
          id: @core.next_id(),
          app_code: Some(app),
          parent_id: Some(parent_id),
          name: item.name,
          code: item.code,
          pids: Some(pid_list.join(",")),
          menu_type: item.menu_type,
          sort: item.sort,
          path: item.path,
          component: item.component,
          icon: item.icon,
          is_show: item.is_show,
          is_link: item.is_link,
          url: item.url,
          enabled: item.enabled,
          open_type: item.open_type,
          is_cache: item.is_cache,
          is_sync: Some(1),
          variable: item.variable,
          create_time: Some(@core.now_str()),
          create_user: None,
          update_time: Some(@core.now_str()),
          update_user: None,
          is_deleted: Some(0),
        }
        let _ = svc.dao.insert(m)
        m.id
      }
      Some(existing) => {
        if existing.is_sync == Some(@enums.yes.code) {
          let u : @entity.Menu = {
            id: existing.id,
            app_code: existing.app_code,
            parent_id: existing.parent_id,
            name: item.name,
            code: item.code,
            pids: Some(pid_list.join(",")),
            menu_type: item.menu_type,
            sort: item.sort,
            path: item.path,
            component: item.component,
            icon: item.icon,
            is_show: item.is_show,
            is_link: item.is_link,
            url: item.url,
            enabled: item.enabled,
            open_type: item.open_type,
            is_cache: item.is_cache,
            is_sync: Some(1),
            variable: item.variable,
            create_time: None,
            create_user: None,
            update_time: Some(@core.now_str()),
            update_user: None,
            is_deleted: None,
          }
          svc.dao.update(u)
        }
        existing.id
      }
    }
    ids.push(menu_id)
    let new_pids = pid_list.copy()
    new_pids.push(menu_id.to_string())
    sync_walk(svc, app, menu_id, new_pids, item.children, level + 1, ids)
  }
}

///|
pub impl[R : @dao.MenuDao] MenuService for MenuServiceImpl[R] with fn sync_route(self, ctx, list) {
  // 空数组短路：boot2 同语义，不删任何行（前端清空路由列表误传空不至清库）
  if list.is_empty() {
    return
  }
  let app = menu_app_code_of(ctx)
  let ids : Array[Int64] = []
  sync_walk(self, app, 0L, ["0"], list, 1, ids)
  // 域内清理：app_code 命中 + is_sync=1 + 不在本次集合 → 逻辑删 + role_menu 级联
  let orphans = self.dao.list_unsynced_except(app, ids)
  let orphan_ids = orphans.map(fn(m) { m.id })
  if !orphan_ids.is_empty() {
    self.dao.remove_by_ids(orphan_ids)
    ((self.purge_role_menus)(orphan_ids))
  }
}

///|
pub extend MenuServiceImpl with MenuService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  tree,
  list,
  app_list,
  user_route_menu,
  sync_route,
}
