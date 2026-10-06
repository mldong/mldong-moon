// 时钟 + 雪花 ID —— clock 算法抄 jeeflow-moon（civil_from_days, Howard Hinnant）；
// 雪花 ID（EPOCH=1288834974657，与 boot2 同 ID 空间——两栈同库共存 ID 不相撞），worker 骨架期固定 1

///|
pub fn epoch_millis() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
pub fn epoch_secs() -> Int64 {
  epoch_millis() / 1000L
}

///|
/// 当前时间 "yyyy-MM-dd HH:mm:ss"（UTC）
pub fn now_str() -> String {
  format_unix_utc(epoch_secs())
}

///|
pub fn format_unix_utc(secs : Int64) -> String {
  let z = secs / 86400L + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = (z - era * 146097L).to_int()
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + (era * 400L).to_int()
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = if m <= 2 { y + 1 } else { y }
  let tod = (secs % 86400L).to_int()
  let hh = tod / 3600
  let mm = (tod % 3600) / 60
  let ss = tod % 60
  let pad = (n : Int, w : Int) => {
    let s = n.to_string()
    let b = StringBuilder()
    for _ in 0..<(w - s.length()) {
      b.write_char('0')
    }
    b.write_string(s)
    b.to_string()
  }
  "\{pad(y, 4)}-\{pad(m, 2)}-\{pad(d, 2)} \{pad(hh, 2)}:\{pad(mm, 2)}:\{pad(ss, 2)}"
}

///|
const EPOCH : Int64 = 1288834974657L

///|
const TIMESTAMP_SHIFT : Int = 22

///|
const WORKER_ID_SHIFT : Int = 12

///|
const MAX_SEQUENCE : Int64 = 4095L

///|
priv struct Snowflake {
  worker_id : Int64
  mut last_timestamp : Int64
  mut sequence : Int64
}

///|
let snowflake : Snowflake = Snowflake::{ worker_id: 1L, last_timestamp: -1L, sequence: 0L }

///|
/// 进程内雪花 ID（单线程事件循环无锁；时钟回拨前进一毫秒，demo 场景可接受）
pub fn next_id() -> Int64 {
  let mut timestamp = epoch_millis()
  if timestamp < snowflake.last_timestamp {
    timestamp = snowflake.last_timestamp + 1L
  }
  if timestamp == snowflake.last_timestamp {
    snowflake.sequence = (snowflake.sequence + 1L) & MAX_SEQUENCE
    if snowflake.sequence == 0L {
      timestamp = timestamp + 1L
    }
  } else {
    snowflake.sequence = 0L
  }
  snowflake.last_timestamp = timestamp
  ((timestamp - EPOCH) << TIMESTAMP_SHIFT) | (snowflake.worker_id << WORKER_ID_SHIFT) | snowflake.sequence
}
