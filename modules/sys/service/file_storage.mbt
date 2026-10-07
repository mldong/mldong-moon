// 文件存储端口 —— boot2 x-file-storage / fastapi `FileStorage(ABC)` 的 moon 同位。
// 分工：**对象怎么放**是存储后端的事，**台账怎么写**是 service 的事，两边只在 StoredObject 上握手。
// 首版只有 LocalStorage（本地盘直写，沿用 upload_file 既有的 `{base}/yyyyMM/{objectId}.ext` 布局）；
// 将来接 MinIO/S3＝再实现一遍本端口（`initiate_multipart` 返回平台真实会话号、
// `merge_parts` 换成 ListParts 拉 etag + CompleteMultipartUpload），service 与控制器零改动。
//
// ⚠ `@fs` 全套（mkdir/write_file/read_file/open/create/File.*/remove/rmdir/exists）抛的是**开放 Error**，
// 在本端口的 `raise @core.MldongError` 签名下必须逐个就地转档（见文末 fs_* 薄封装）；
// `remove`/`rmdir` 走吞错档（清理动作要幂等）。exists 干脆不用——预判一次等于多一次可失败的 IO。

///|
/// 对象位置：磁盘路径与对外 url 一次算全（契约 UC-0604 明写
/// "url 在初始化时即可计算并写入记录"——本地盘有确定性地址，分片还没合并也先落台账）。
pub(all) struct StoredObject {
  /// 文件所属对象 id（boot2 IdWorker objectId 同位）
  object_id : String
  /// 扩展名（无扩展名为空串）
  ext : String
  /// 存储文件名：object_id[.ext]
  filename : String
  /// 磁盘目录（落 sys_file_info.base_path）
  base_path : String
  /// 相对路径 /yyyyMM/filename（落 sys_file_info.path）
  path : String
  /// 对外访问地址 /uploadfiles/yyyyMM/filename（落 sys_file_info.url）
  url : String
}

///|
/// 存储后端端口。`is_support_multipart`/`plan_object` 是纯计算，其余异步（云后端要发网络请求）。
pub(open) trait FileStorage {
  /// 是否支持手动分片（boot2 `isSupportMultipart()` 同位；不支持时 initiate 直接业务失败）
  fn is_support_multipart(Self) -> Bool
  /// 规划对象位置（不碰存储）
  fn plan_object(Self, original_filename : String, ym : String) -> StoredObject
  /// 整对象写入（普通上传）
  async fn put_object(Self, object : StoredObject, content : Bytes) -> Unit raise @core.MldongError
  /// 删对象（清理用；不存在即静默）
  async fn remove_object(Self, object : StoredObject) -> Unit raise @core.MldongError
  /// 开启分片会话并返回 uploadId（本地＝自生成；s3＝CreateMultipartUpload 的会话号）
  async fn initiate_multipart(Self, object : StoredObject) -> String raise @core.MldongError
  /// 落一枚分片（序号从 1 起；同序号重复到达＝覆盖，不追加出两份）
  async fn put_part(
    Self,
    upload_id : String,
    part_number : Int,
    content : Bytes,
  ) -> Unit raise @core.MldongError
  /// 按调用方给的序号顺序把分片拼成最终对象，返回**合并后的真实字节数**。
  /// 序号列表由台账决定（契约 UC-0605"分片按序号规范命名落盘，服务端排序合并"）——
  /// 既不按到达序（fastapi 本地版那样），也不靠文件名猜。
  async fn merge_parts(
    Self,
    upload_id : String,
    object : StoredObject,
    part_numbers : Array[Int],
  ) -> Int64 raise @core.MldongError
  /// 清掉该会话的暂存残留（取消分片、或合并成功后收尾；不存在即静默）
  async fn discard_parts(Self, upload_id : String) -> Unit raise @core.MldongError
}

///|
/// 本地盘实现。root＝`upload_base_path()`（env MLDONG_UPLOAD_PATH 缺省 ./uploadfiles），
/// url 前缀固定 `/uploadfiles`（与既有 upload 出口一致）。
pub(all) struct LocalStorage {
  root : String
  url_prefix : String
}

///|
pub fn LocalStorage::make(root : String) -> LocalStorage {
  { root, url_prefix: "/uploadfiles" }
}

///|
fn multipart_dir(root : String, upload_id : String) -> String {
  // 点开头目录＝不属于任何对外对象，url 打不到（对外只暴露 /uploadfiles/yyyyMM/*）
  root + "/.multipart/" + upload_id
}

///|
/// 分片文件名 part_00001：序号补零到 5 位（与 fastapi/boot2 的本地命名同形，
/// 排障时人眼能直接对上序号；合并顺序仍由台账给的序号列表决定）
fn part_name(part_number : Int) -> String {
  let text = part_number.to_string()
  let pad = 5 - text.length()
  let mut i = 0
  let mut zeros = ""
  while i < pad {
    zeros = zeros + "0"
    i = i + 1
  }
  "part_" + zeros + text
}

///|
pub impl FileStorage for LocalStorage with fn is_support_multipart(self) -> Bool {
  let _ = self
  true
}

///|
pub impl FileStorage for LocalStorage with fn plan_object(self, original_filename, ym) {
  let ext = filename_ext(original_filename)
  let object_id = @core.next_id().to_string()
  let stored = object_id + (if ext.is_empty() { "" } else { "." + ext })
  {
    object_id,
    ext,
    filename: stored,
    base_path: self.root + "/" + ym,
    path: "/" + ym + "/" + stored,
    url: self.url_prefix + "/" + ym + "/" + stored,
  }
}

///|
pub impl FileStorage for LocalStorage with fn put_object(self, object, content) {
  let _ = self
  fs_mkdir(object.base_path)
  fs_write(object.base_path + "/" + object.filename, content, append=false)
}

///|
pub impl FileStorage for LocalStorage with fn remove_object(self, object) {
  let _ = self
  fs_drop_if_exists(object.base_path + "/" + object.filename)
}

///|
/// 本地会话号＝雪花 id（契约 UC-0604：local 自生成）。object 不消费，留着让端口形状
/// 与云后端一致（s3 的 CreateMultipartUpload 要以对象 key 发起）。
pub impl FileStorage for LocalStorage with fn initiate_multipart(self, _object) -> String {
  let upload_id = @core.next_id().to_string()
  fs_mkdir(multipart_dir(self.root, upload_id))
  upload_id
}

///|
pub impl FileStorage for LocalStorage with fn put_part(self, upload_id, part_number, content) {
  let dir = multipart_dir(self.root, upload_id)
  fs_mkdir(dir)
  // append=false ⇒ CreateOrTruncate，同序号重写天然是覆盖；
  // 若走 append 会把后写的短分片接在旧字节后面，拼出脏文件
  fs_write(dir + "/" + part_name(part_number), content, append=false)
}

///|
pub impl FileStorage for LocalStorage with fn merge_parts(self, upload_id, object, part_numbers) {
  let dir = multipart_dir(self.root, upload_id)
  fs_mkdir(object.base_path)
  // 逐片定位写入（create 默认 CreateOrTruncate ⇒ 重复合并同一会话不留半态），
  // 不把整个对象读进内存——分片上传的动机就是大文件
  let out = fs_create(object.base_path + "/" + object.filename)
  let mut total = 0L
  for n in part_numbers {
    let src = fs_open_read(dir + "/" + part_name(n), n)
    let size = src.size() catch {
      e => {
        src.close()
        raise @core.MldongError::InvalidParam("分片 \{n} 不可读: \{e}")
      }
    }
    let data = src.read_exactly_at(size.to_int(), position=0L) catch {
      e => {
        src.close()
        raise @core.MldongError::InvalidParam("分片 \{n} 读取失败: \{e}")
      }
    }
    let _ = src.close()
    let _ = out.write_at(data, position=total) catch {
      e => raise @core.MldongError::Internal("merge write 分片 \{n}: \{e}")
    }
    total = total + size
  }
  let _ = out.sync(only_data=true) catch {
    e => raise @core.MldongError::Internal("merge sync: \{e}")
  }
  let _ = out.close()
  total
}

///|
pub impl FileStorage for LocalStorage with fn discard_parts(self, upload_id) {
  // 幂等清理：目录已被合并清掉/从未建起都算成功
  fs_rmtree_if_exists(multipart_dir(self.root, upload_id))
}

///|
pub extend LocalStorage with FileStorage::{
  is_support_multipart,
  plan_object,
  put_object,
  remove_object,
  initiate_multipart,
  put_part,
  merge_parts,
  discard_parts,
}

///|
/// `@fs.exists` 转档：ENOENT 已由 @fs.exists 自己折成 false，剩下的都是真故障
async fn fs_exists(path : String) -> Bool raise @core.MldongError {
  try {
    @fs.exists(path)
  } catch {
    e => raise @core.MldongError::Internal("exists \{path}: \{e}")
  }
}

///|
/// 先探再删：目录/文件已不在就当成功，真删失败才外抛（端口侧要档位，云后端会真抛）
async fn fs_drop_if_exists(path : String) -> Unit raise @core.MldongError {
  if fs_exists(path) {
    try {
      @fs.remove(path)
    } catch {
      e => raise @core.MldongError::Internal("remove \{path}: \{e}")
    }
  }
}

///|
async fn fs_rmtree_if_exists(path : String) -> Unit raise @core.MldongError {
  if fs_exists(path) {
    try {
      @fs.rmdir(path, recursive=true)
    } catch {
      e => raise @core.MldongError::Internal("rmdir \{path}: \{e}")
    }
  }
}

// ── @fs 薄封装：开放 Error → MldongError 的转档只在这一处发生；清理类走吞错档 ──

///|
async fn fs_mkdir(path : String) -> Unit raise @core.MldongError {
  try {
    @fs.mkdir(path, recursive=true, allow_exist=true)
  } catch {
    e => raise @core.MldongError::Internal("mkdir \{path}: \{e}")
  }
}

///|
async fn fs_write(path : String, content : Bytes, append? : Bool = false) -> Unit raise @core.MldongError {
  try {
    @fs.write_file(path, content, append=append)
  } catch {
    e => raise @core.MldongError::Internal("write \{path}: \{e}")
  }
}

///|
async fn fs_create(path : String) -> @fs.File raise @core.MldongError {
  try {
    @fs.create(path)
  } catch {
    e => raise @core.MldongError::Internal("create \{path}: \{e}")
  }
}

///|
/// 分片读不开＝"该序号没传上来"，属业务失败（boot2/fastapi 同档：合并前置不满足）
async fn fs_open_read(path : String, part_number : Int) -> @fs.File raise @core.MldongError {
  try {
    @fs.open(path, mode=ReadOnly)
  } catch {
    e => raise @core.MldongError::InvalidParam("分片 \{part_number} 缺失或不可读: \{e}")
  }
}
