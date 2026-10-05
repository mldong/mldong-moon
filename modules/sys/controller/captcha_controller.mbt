// 图形验证码 + SM2 公钥端点 —— boot2 AuthController /sys/captcha + /sys/getSm2PublicKey 同位
// SVG 手绘（moonback 无图像库，salvo/gin 家族同口径）：120x40、4 字符
// （去易混淆 0O1lI）、干扰线/噪点/随机旋转；内存存储 TTL 10 分钟、
// 一次性消费（校验即删）、忽略大小写比对。
// SM2 未启用恒返空公钥（moon 无 sm2 依赖；空串 = 前端不加密分支，契约形状不变）。

///|
priv struct CaptchaItem {
  code : String
  expire_at : Int64
}

///|
/// 验证码存储（单线程事件循环，裸 Map 即线程安全；生成时顺手清过期）
let captcha_store : Map[String, CaptchaItem] = Map([], capacity=0)

///|
/// 验证码字符集（去除易混淆的 0O1lI，salvo/gin 同表）
const CAPTCHA_CHARS : String = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz"

///|
const BASE64_TABLE : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// 字节 → base64（标准字母表 + '=' 补齐；SVG 内联图用）
fn base64_of(data : Bytes) -> String {
  let buf = StringBuilder()
  let n = data.length()
  let mut i = 0
  while i + 2 < n {
    let v = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8) | data[i + 2].to_int()
    for k in 0..<4 {
      match BASE64_TABLE.get_char((v >> (18 - k * 6)) & 63) {
        Some(c) => buf.write_char(c)
        None => ()
      }
    }
    i = i + 3
  }
  let rest = n - i
  if rest == 1 {
    let v = data[i].to_int() << 16
    for k in 0..<2 {
      match BASE64_TABLE.get_char((v >> (18 - k * 6)) & 63) {
        Some(c) => buf.write_char(c)
        None => ()
      }
    }
    buf.write_string("==")
  } else if rest == 2 {
    let v = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    for k in 0..<3 {
      match BASE64_TABLE.get_char((v >> (18 - k * 6)) & 63) {
        Some(c) => buf.write_char(c)
        None => ()
      }
    }
    buf.write_char('=')
  }
  buf.to_string()
}

///|
/// 带噪点与干扰线的 SVG 验证码（salvo build_captcha_svg 同款）
fn captcha_svg(code : String, rand : @random.Rand) -> String {
  let width = 120
  let height = 40
  let buf = StringBuilder()
  buf.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{width}\" height=\"\{height}\" viewBox=\"0 0 \{width} \{height}\">",
  )
  buf.write_string("<rect width=\"\{width}\" height=\"\{height}\" fill=\"#f2f4f7\"/>")
  // 干扰线
  for _ in 0..<4 {
    let x1 = rand.int(limit=width)
    let y1 = rand.int(limit=height)
    let x2 = rand.int(limit=width)
    let y2 = rand.int(limit=height)
    let color = rand.int(limit=0x1000000)
    buf.write_string(
      "<line x1=\"\{x1}\" y1=\"\{y1}\" x2=\"\{x2}\" y2=\"\{y2}\" stroke=\"#\{padded_hex(color, 6)}\" stroke-width=\"1\"/>",
    )
  }
  // 噪点
  for _ in 0..<30 {
    let cx = rand.int(limit=width)
    let cy = rand.int(limit=height)
    let color = rand.int(limit=0x1000000)
    buf.write_string("<circle cx=\"\{cx}\" cy=\"\{cy}\" r=\"1\" fill=\"#\{padded_hex(color, 6)}\"/>")
  }
  // 字符（随机偏移与旋转）
  let char_w = width / code.length()
  for i in 0..<code.length() {
    let x = i * char_w + char_w / 2 + rand.int(limit=6) - 3
    let y = height / 2 + 6 + rand.int(limit=6) - 3
    let rotate = rand.int(limit=30) - 15
    let color = rand.int(limit=0x1000000)
    match code.get_char(i) {
      Some(ch) =>
        buf.write_string(
          "<text x=\"\{x}\" y=\"\{y}\" font-size=\"26\" font-family=\"Arial\" fill=\"#\{padded_hex(color, 6)}\" transform=\"rotate(\{rotate} \{x} \{y})\" text-anchor=\"middle\">\{ch}</text>",
        )
      None => ()
    }
  }
  buf.write_string("</svg>")
  buf.to_string()
}

///|
/// int → 固定位数小写 hex（SVG 颜色 #rrggbb）
fn padded_hex(v : Int, width : Int) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for shift in 0..<width {
    let idx = (v >> ((width - shift - 1) * 4)) & 15
    match digits.get_char(idx) {
      Some(c) => buf.write_char(c)
      None => ()
    }
  }
  buf.to_string()
}

///|
/// 生成验证码：随机 4 字符 + uuid 键入存（TTL 10 分钟）→ {uuid, base64}
fn create_captcha() -> (String, String) {
  let rand = @random.Rand::new()
  let now = @core.epoch_millis()
  // 顺手清过期（量小，全量扫足够）
  let expired : Array[String] = []
  for kv in captcha_store {
    if kv.1.expire_at <= now {
      expired.push(kv.0)
    }
  }
  for k in expired {
    captcha_store.remove(k)
  }
  let code = StringBuilder()
  for _ in 0..<4 {
    match CAPTCHA_CHARS.get_char(rand.int(limit=CAPTCHA_CHARS.length())) {
      Some(c) => code.write_char(c)
      None => ()
    }
  }
  let code = code.to_string()
  let uuid = new_guid(rand)
  captcha_store.set(uuid, CaptchaItem::{ code, expire_at: now + 600_000L })
  let svg = captcha_svg(code, rand)
  let b64 = base64_of(@utf8.encode(svg))
  (uuid, "data:image/svg+xml;base64,\{b64}")
}

///|
/// uuid 形随机串（8-4-4-4-12 hex；仅做验证码键，非安全边界）
fn new_guid(rand : @random.Rand) -> String {
  let hex = "0123456789abcdef"
  let groups = [8, 4, 4, 4, 12]
  let buf = StringBuilder()
  for gi, g in groups {
    if gi > 0 {
      buf.write_char('-')
    }
    for _ in 0..<g {
      match hex.get_char(rand.int(limit=16)) {
        Some(c) => buf.write_char(c)
        None => ()
      }
    }
  }
  buf.to_string()
}

///|
/// 校验验证码：一次性消费（校验即删）、忽略大小写、缺失/过期/不存在均拒绝
pub fn verify_captcha(uuid : String, code : String) -> Bool {
  if uuid.is_empty() || code.is_empty() {
    return false
  }
  match captcha_store.get(uuid) {
    None => false
    Some(item) => {
      captcha_store.remove(uuid)
      if item.expire_at <= @core.epoch_millis() {
        false
      } else {
        item.code.to_lower() == code.to_lower()
      }
    }
  }
}

///|
/// 验证码 + SM2 公钥端点（公开面，main 免名单同挂；ctx 直挂不过 guard）
pub fn register_captcha(ctx : @mb.ModuleContext) -> Unit {
  let captcha_handler : @mb.Handler = async fn(_request, responder) {
    let (uuid, b64) = create_captcha()
    responder.send_json(
      @core.ok_data({ "uuid": uuid, "base64": b64 }),
      headers=[("Content-Type", "application/json; charset=utf-8")],
    ) catch {
      _ => ()
    }
  }
  let sm2_handler : @mb.Handler = async fn(_request, responder) {
    // moon 无 SM2 依赖：恒返空公钥 = 前端不加密分支（boot2 开关关同形状）
    responder.send_json(
      @core.ok_data({ "publicKey": "" }),
      headers=[("Content-Type", "application/json; charset=utf-8")],
    ) catch {
      _ => ()
    }
  }
  ctx.post("/sys/captcha", captcha_handler) catch {
    _ => abort("验证码路由注册失败（路由冲突?）")
  }
  ctx.post("/sys/getSm2PublicKey", sm2_handler) catch {
    _ => abort("SM2 公钥路由注册失败（路由冲突?）")
  }
}
