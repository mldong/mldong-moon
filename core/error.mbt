// mldong-moon 错误定义 —— 业务失败走 9999xxxx 码表（对齐 mldong 接口契约契约，骨架先取子集）

///|
/// 统一业务错误：raise 上抛，cmd/main 全局转换成 {code, msg, data} 信封
pub(all) suberror MldongError {
  /// 通用业务失败（msg 直出）
  Business(String)
  /// 入参形态错误（99990001，手写判空/坏 JSON 这类；契约钦定的「参数校验失败」是
  /// 99999999，见下面的 InvalidParam）
  InvalidInput(String)
  /// 数据不存在（99990002）
  NotFound(String)
  /// 资源状态冲突（99990003，现仅装配期「插件路由与既有路由撞型」一处）：
  /// **唯一键冲突不在此档**——boot2 checkUnique 走 99999999，见 InvalidParam
  Conflict(String)
  /// 权限码不足（99990406，boot2 AuthErrEnum.NO_RESOURCE_AUTH /
  /// StpUtil.checkPermissionOr 抛出的同位；供 lowCode 这类**码由路径参数决定**、
  /// Guard 静态策略表达不了的端点在处理器内自查）
  NoPermission(String)
  /// 基础设施/内部错误（99990000，对外只说"系统繁忙"档的占位，骨架先透出原因便于调试）
  Internal(String)
  /// 参数校验失败（99999999，boot2 @Validated MethodArgumentNotValidException
  /// 由 GlobalExceptionHandler 统一映射 99999999 的同位——契约 00-全局约定 §1 把
  /// 「参数校验失败」钦定为此码；moon_zod 拒绝必填/类型不合、checkUnique 撞唯一键都走这档
  /// （UC-0610 精确断此码，L3 B14/B03/B06 实测量出旧映射））
  InvalidParam(String)
}

///|
pub fn MldongError::code(self : MldongError) -> Int {
  match self {
    Internal(_) => 99990000
    InvalidInput(_) => 99990001
    NotFound(_) => 99990002
    Business(_) => 99990004
    Conflict(_) => 99990003
    InvalidParam(_) => 99999999
    NoPermission(_) => 99990406
  }
}

///|
pub fn MldongError::message(self : MldongError) -> String {
  match self {
    Business(msg) => msg
    Conflict(msg) => msg
    NoPermission(msg) => msg
    InvalidInput(msg) => msg
    NotFound(msg) => msg
    Internal(msg) => msg
    InvalidParam(msg) => msg
  }
}
