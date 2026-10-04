// mldong-moon 错误定义 —— 业务失败走 9999xxxx 码表（对齐 mldong 接口契约契约，骨架先取子集）

///|
/// 统一业务错误：raise 上抛，cmd/main 全局转换成 {code, msg, data} 信封
pub(all) suberror MldongError {
  /// 通用业务失败（msg 直出）
  Business(String)
  /// 参数校验失败（99990001）
  InvalidInput(String)
  /// 数据不存在（99990002）
  NotFound(String)
  /// 业务冲突，如用户名已存在（99990003）
  Conflict(String)
  /// 基础设施/内部错误（99990000，对外只说"系统繁忙"档的占位，骨架先透出原因便于调试）
  Internal(String)
  /// bean 校验失败（99999999，boot2 @Validated MethodArgumentNotValidException
  /// 由 GlobalExceptionHandler 统一映射 99999999 的同位——UC-0610 精确断此码）
  InvalidParam(String)
}

///|
pub fn MldongError::code(self : MldongError) -> Int {
  match self {
    Internal(_) => 99990000
    InvalidInput(_) => 99990001
    NotFound(_) => 99990002
    Conflict(_) => 99990003
    Business(_) => 99990004
    InvalidParam(_) => 99999999
  }
}

///|
pub fn MldongError::message(self : MldongError) -> String {
  match self {
    Business(msg) => msg
    InvalidInput(msg) => msg
    NotFound(msg) => msg
    Conflict(msg) => msg
    Internal(msg) => msg
    InvalidParam(msg) => msg
  }
}
