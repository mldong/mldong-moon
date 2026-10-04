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
}

///|
pub(all) struct MenuServiceImpl[R] {
  dao : R
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
pub extend MenuServiceImpl with MenuService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
  tree,
  list,
}
