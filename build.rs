fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        // libdispatch 符号（dispatch_after_f, dispatch_async_f, _dispatch_main_q 等）
        // 在 SDK 的 usr/lib/system/libdispatch.tbd 中，通过 -ldispatch 或 -lSystem 链接
        println!("cargo:rustc-link-lib=dylib=System");
    }
}
