use std::sync::OnceLock;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use chrono::Utc;
use uuid::Uuid;

use super::{ParseResult, Parser};

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn gen_result(
    parser_name: &'static str,
    original: &str,
    generated: &str,
    details: String,
) -> Vec<ParseResult> {
    vec![
        ParseResult::new(parser_name, original, generated).with_details(details),
    ]
}

// ── UUID v7 生成器 ────────────────────────────────────────────────────────────

pub struct UuidGenerator;

impl UuidGenerator {
    pub fn new() -> Self { Self }
}
impl Default for UuidGenerator { fn default() -> Self { Self::new() } }

impl Parser for UuidGenerator {
    fn name(&self) -> &'static str { "UUID生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        if content.trim().to_lowercase() != "uuid" {
            return vec![];
        }
        let generated = Uuid::now_v7().to_string();
        gen_result("UUID生成", content, &generated, format!("UUID v7：{}", generated))
    }
}

// ── 秒时间戳生成器 ────────────────────────────────────────────────────────────

pub struct TimestampGenerator;

impl TimestampGenerator {
    pub fn new() -> Self { Self }
}
impl Default for TimestampGenerator { fn default() -> Self { Self::new() } }

impl Parser for TimestampGenerator {
    fn name(&self) -> &'static str { "时间戳生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let kw = content.trim().to_lowercase();
        if kw != "ts" && kw != "timestamp" {
            return vec![];
        }
        let ts = now_secs().to_string();
        let dt = chrono::DateTime::from_timestamp(ts.parse::<i64>().unwrap_or(0), 0)
            .unwrap_or_default()
            .with_timezone(&Utc);
        gen_result(
            "时间戳生成",
            content,
            &ts,
            format!(
                "Unix 时间戳（秒）：{}\n对应时间：{}",
                ts,
                dt.format("%Y-%m-%d %H:%M:%S UTC")
            ),
        )
    }
}

// ── RFC 3339 时间字符串生成器 ─────────────────────────────────────────────────

pub struct TimeGenerator;

impl TimeGenerator {
    pub fn new() -> Self { Self }
}
impl Default for TimeGenerator { fn default() -> Self { Self::new() } }

impl Parser for TimeGenerator {
    fn name(&self) -> &'static str { "时间生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        if content.trim().to_lowercase() != "time" {
            return vec![];
        }
        let rfc = Utc::now().to_rfc3339();
        gen_result("时间生成", content, &rfc, format!("RFC 3339：{}", rfc))
    }
}

// ── MongoDB ObjectId 生成器 ───────────────────────────────────────────────────

static OID_MACHINE_PROC: OnceLock<[u8; 5]> = OnceLock::new();
static OID_COUNTER: AtomicU32 = AtomicU32::new(0);

fn machine_proc_bytes() -> [u8; 5] {
    *OID_MACHINE_PROC.get_or_init(|| {
        let pid = std::process::id() as u64;
        let ns = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .subsec_nanos() as u64;
        // FNV-1a 混合 pid 和纳秒
        let mut h: u64 = 0xcbf29ce484222325;
        for b in pid.to_le_bytes().iter().chain(ns.to_le_bytes().iter()) {
            h ^= *b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        let b = h.to_be_bytes();
        [b[3], b[4], b[5], b[6], b[7]]
    })
}

fn generate_object_id() -> String {
    let ts = now_secs() as u32;
    let mp = machine_proc_bytes();
    let cnt = OID_COUNTER.fetch_add(1, Ordering::Relaxed);

    let mut bytes = [0u8; 12];
    bytes[..4].copy_from_slice(&ts.to_be_bytes());
    bytes[4..9].copy_from_slice(&mp);
    bytes[9] = (cnt >> 16) as u8;
    bytes[10] = (cnt >> 8) as u8;
    bytes[11] = cnt as u8;
    hex::encode(bytes)
}

pub struct ObjectIdGenerator;

impl ObjectIdGenerator {
    pub fn new() -> Self { Self }
}
impl Default for ObjectIdGenerator { fn default() -> Self { Self::new() } }

impl Parser for ObjectIdGenerator {
    fn name(&self) -> &'static str { "ObjectId生成" }

    fn parse(&self, content: &str) -> Vec<ParseResult> {
        let kw = content.trim().to_lowercase();
        if kw != "objectid" && kw != "oid" {
            return vec![];
        }
        let oid = generate_object_id();
        let ts = u32::from_be_bytes(hex::decode(&oid[..8]).unwrap().try_into().unwrap());
        let dt = chrono::DateTime::from_timestamp(ts as i64, 0)
            .unwrap_or_default()
            .with_timezone(&Utc);
        gen_result(
            "ObjectId生成",
            content,
            &oid,
            format!(
                "MongoDB ObjectId：{}\n嵌入时间：{}",
                oid,
                dt.format("%Y-%m-%d %H:%M:%S UTC")
            ),
        )
    }
}
