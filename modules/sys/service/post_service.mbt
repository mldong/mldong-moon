// sys_post 服务 —— 业务逻辑唯一收口；零 web/ORM 类型〔cmd/gen 生成，可手改〕

///|
pub(open) trait PostService {
  /// op_user = 操作人 id（审计 create_user/update_user；controller 从登录主体取）
  async fn save(Self, @dto.PostSaveReq, Int64?) -> Int64 raise @core.MldongError
  async fn update(Self, @dto.PostSaveReq, Int64?) -> Unit raise @core.MldongError
  async fn remove_by_ids(Self, Array[Int64]) -> Unit raise @core.MldongError
  async fn find_by_id(Self, Int64) -> @entity.Post raise @core.MldongError
  async fn page(Self, @dto.PostPageReq) -> (Int, Array[@entity.Post]) raise @core.MldongError
}

///|
pub(all) struct PostServiceImpl[R] {
  dao : R
}

///|
pub impl[R : @dao.PostDao] PostService for PostServiceImpl[R] with fn save(self, req, op_user) {
  // 唯一编码校验（boot2 checkUnique 同位一行调）
  self.dao.check_unique(req.code, None, "唯一编码已存在: " + req.code)
  let d : @entity.Post = {
    id: @core.next_id(),
    name: req.name,
    code: req.code,
    sort: req.sort,
    enabled: req.enabled,
    remark: req.remark,
    variable: None,
    create_time: Some(@core.now_str()),
    create_user: op_user,
    update_time: None,
    update_user: op_user,
    is_deleted: Some(0),
  }
  self.dao.insert(d)
}

///|
pub impl[R : @dao.PostDao] PostService for PostServiceImpl[R] with fn update(self, req, op_user) {
  match self.dao.find_by_id(req.id) {
    None => raise @core.MldongError::NotFound("数据不存在: " + req.id.to_string())
    Some(_) => ()
  }
  // 编码查重（排除自身）
  self.dao.check_unique(req.code, Some(req.id), "唯一编码已存在: " + req.code)
  // 未传的可选字段落 N，BaseDao 构建 SET 时跳过（null 不覆盖语义在 builder 层统一）
  let d : @entity.Post = {
    id: req.id,
    name: req.name,
    code: req.code,
    sort: req.sort,
    enabled: req.enabled,
    remark: req.remark,
    variable: None,
    create_time: None,
    create_user: None,
    update_time: Some(@core.now_str()),
    update_user: op_user,
    is_deleted: None,
  }
  self.dao.update(d)
}

///|
pub impl[R : @dao.PostDao] PostService for PostServiceImpl[R] with fn remove_by_ids(self, ids) {
  if ids.is_empty() {
    raise @core.MldongError::InvalidInput("ids 不能为空")
  }
  self.dao.remove_by_ids(ids)
}

///|
pub impl[R : @dao.PostDao] PostService for PostServiceImpl[R] with fn find_by_id(
  self,
  id,
) {
  match self.dao.find_by_id(id) {
    Some(d) => d
    None => raise @core.MldongError::NotFound("数据不存在: " + id.to_string())
  }
}

///|
pub impl[R : @dao.PostDao] PostService for PostServiceImpl[R] with fn page(self, req) {
  let w = @core.where_()
  let _ = w.append(req.m)
  self.dao.page(w, req.page_num, req.page_size)
}

///|
pub extend PostServiceImpl with PostService::{
  page,
  remove_by_ids,
  save,
  find_by_id,
  update,
}
