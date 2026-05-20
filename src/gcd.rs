//! 对 macOS Grand Central Dispatch C API 的最小封装
//! dispatch_get_main_queue() 是 inline 函数，不可链接；直接使用 _dispatch_main_q 全局变量。

#![cfg(target_os = "macos")]

use std::os::raw::c_void;
use std::time::Duration;

// dispatch_queue_t 在 ABI 层面是指向 dispatch_queue_s 结构体的指针
// 用 *mut c_void 代替，足够用于 dispatch_after_f / dispatch_async_f 的调用
type DispatchQueue = *mut c_void;

extern "C" {
    // 主队列全局变量（dispatch_get_main_queue() 宏展开后返回 &_dispatch_main_q）
    static _dispatch_main_q: c_void;

    fn dispatch_time(when: u64, delta: i64) -> u64;

    fn dispatch_after_f(
        when: u64,
        queue: DispatchQueue,
        context: *mut c_void,
        work: unsafe extern "C" fn(*mut c_void),
    );

    fn dispatch_async_f(
        queue: DispatchQueue,
        context: *mut c_void,
        work: unsafe extern "C" fn(*mut c_void),
    );
}

const DISPATCH_TIME_NOW: u64 = 0;

unsafe extern "C" fn trampoline(ctx: *mut c_void) {
    let f = unsafe { Box::from_raw(ctx as *mut Box<dyn FnOnce() + Send>) };
    f();
}

fn into_ctx<F: FnOnce() + Send + 'static>(f: F) -> *mut c_void {
    let boxed: Box<Box<dyn FnOnce() + Send>> = Box::new(Box::new(f));
    Box::into_raw(boxed) as *mut c_void
}

fn main_queue() -> DispatchQueue {
    // 与 C 宏 dispatch_get_main_queue() 等价：取全局变量的地址
    &raw const _dispatch_main_q as *mut c_void
}

/// 在主队列上延迟执行闭包
pub fn exec_after<F: FnOnce() + Send + 'static>(delay: Duration, f: F) {
    let ctx = into_ctx(f);
    let delay_ns = delay.as_nanos().min(i64::MAX as u128) as i64;
    unsafe {
        let when = dispatch_time(DISPATCH_TIME_NOW, delay_ns);
        dispatch_after_f(when, main_queue(), ctx, trampoline);
    }
}

/// 在主队列上异步执行闭包
pub fn exec_async<F: FnOnce() + Send + 'static>(f: F) {
    let ctx = into_ctx(f);
    unsafe { dispatch_async_f(main_queue(), ctx, trampoline) };
}
