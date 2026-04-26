#![cfg(target_os = "macos")]

use std::collections::VecDeque;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use objc2::rc::Retained;
use objc2::runtime::{AnyClass, AnyObject, ClassBuilder, NSObject, Sel};
use objc2::{msg_send, sel, ClassType, MainThreadOnly};
use objc2_app_kit::{
    NSBackingStoreType, NSButton, NSColor, NSEvent, NSFont, NSFloatingWindowLevel, NSPanel,
    NSScreen, NSScrollView, NSTextView, NSView, NSWindowStyleMask,
};
use objc2_foundation::{MainThreadMarker, NSPoint, NSRect, NSSize, NSString};

use crate::config::Config;
use crate::parser::ParseResult;

// ── 历史按钮 action 目标（通过 ClassBuilder 注册自定义 selector）─────────────

static HISTORY_TARGET_CLASS: OnceLock<&'static AnyClass> = OnceLock::new();

/// 注册 MCGAHistoryButtonTarget 类，若已注册则复用
fn history_target_class() -> &'static AnyClass {
    HISTORY_TARGET_CLASS.get_or_init(|| {
        let mut builder = ClassBuilder::new(c"MCGAHistoryButtonTarget", NSObject::class())
            .expect("class MCGAHistoryButtonTarget already registered");

        // historyClicked: — 按钮 action
        unsafe extern "C-unwind" fn history_clicked(
            _this: &AnyObject,
            _cmd: Sel,
            _sender: *mut AnyObject,
        ) {
            let entries = crate::history::load_all().unwrap_or_default();
            if entries.is_empty() {
                return;
            }
            let text = crate::history::format_for_overlay(&entries, 30);
            let cfg = crate::config_file::load();
            unsafe { show_inner("历史记录", &text, &cfg) };
        }

        unsafe {
            builder.add_method(
                sel!(historyClicked:),
                history_clicked as unsafe extern "C-unwind" fn(_, _, _),
            );
        }

        builder.register()
    })
}

// ── 活跃浮层槽位（最多两个）────────────────────────────────────────────────

struct ActivePanel {
    raw: usize,        // Retained<NSPanel>
    target_raw: usize, // Retained<AnyObject> — 按钮 target，保持其存活
    cancelled: Arc<AtomicBool>,
}

static ACTIVE_PANELS: Mutex<VecDeque<ActivePanel>> = Mutex::new(VecDeque::new());

static QUIT_ON_EMPTY: AtomicBool = AtomicBool::new(false);

pub fn set_quit_on_empty(v: bool) {
    QUIT_ON_EMPTY.store(v, Ordering::Relaxed);
}

// ── 公开接口 ─────────────────────────────────────────────────────────────────

pub fn show_results(results: &[ParseResult], config: &Config) {
    if results.is_empty() {
        return;
    }

    let title = format!(
        "[{}] {}",
        results[0].parser_name,
        &results[0].original[..results[0].original.len().min(40)]
    );

    let mut body = String::new();
    for (i, r) in results.iter().enumerate() {
        if i > 0 {
            body.push_str("\n---\n\n");
        }
        body.push_str(&format!("[ {} ]\n\n", r.parser_name));
        body.push_str(&r.parsed);
        if let Some(ref d) = r.details {
            body.push('\n');
            body.push_str(d);
        }
    }

    unsafe { show_inner(&title, &body, config) }
}

const BTN_H: f64 = 28.0;

unsafe fn show_inner(title: &str, content: &str, config: &Config) {
    let mtm = MainThreadMarker::new_unchecked();

    let screen = match NSScreen::mainScreen(mtm) {
        Some(s) => s,
        None => return,
    };
    let sf = screen.frame();

    let width = sf.size.width * config.overlay_width_pct;
    let height = sf.size.height * config.overlay_height_pct;
    let margin_right = sf.size.width * config.overlay_margin_right_pct;
    let margin_bottom = sf.size.height * config.overlay_margin_bottom_pct;
    let gap = sf.size.height * config.overlay_gap_pct;
    let x = sf.origin.x + sf.size.width - width - margin_right;

    // 确定槽位，超出两个时关掉最旧的
    let slot = {
        let mut panels = ACTIVE_PANELS.lock().unwrap();
        if panels.len() >= 2 {
            let oldest = panels.pop_front().unwrap();
            oldest.cancelled.store(true, Ordering::Relaxed);
            if let Some(p) = Retained::from_raw(oldest.raw as *mut NSPanel) {
                p.orderOut(None::<&AnyObject>);
            }
            drop(Retained::from_raw(oldest.target_raw as *mut AnyObject));
        }
        panels.len()
    };

    let y = sf.origin.y + margin_bottom + slot as f64 * (height + gap);
    let panel_rect = NSRect::new(NSPoint::new(x, y), NSSize::new(width, height));
    let style = NSWindowStyleMask::Borderless | NSWindowStyleMask::NonactivatingPanel;

    let panel = NSPanel::initWithContentRect_styleMask_backing_defer(
        NSPanel::alloc(mtm),
        panel_rect,
        style,
        NSBackingStoreType::Buffered,
        false,
    );

    panel.setLevel(NSFloatingWindowLevel);
    panel.setAlphaValue(0.96);
    panel.setHasShadow(true);
    panel.setMovableByWindowBackground(true);

    let bg = NSColor::colorWithRed_green_blue_alpha(0.11, 0.11, 0.11, 1.0);
    panel.setBackgroundColor(Some(&bg));

    // ── 按钮 target 对象
    let cls = history_target_class();
    let target: Retained<AnyObject> = {
        let alloc: *mut AnyObject = msg_send![cls, alloc];
        Retained::from_raw(msg_send![alloc, init]).unwrap()
    };

    // ── 容器 NSView
    let container_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, height));
    let container = NSView::initWithFrame(NSView::alloc(mtm), container_rect);

    // ── 历史按钮（底部）
    let btn = NSButton::buttonWithTitle_target_action(
        &NSString::from_str("历史记录"),
        Some(&*target),
        Some(sel!(historyClicked:)),
        mtm,
    );
    btn.setFrame(NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, BTN_H)));
    // 无边框按钮 + contentTintColor 可直接设置文字颜色
    btn.setBordered(false);
    let btn_fg = NSColor::colorWithRed_green_blue_alpha(0.92, 0.92, 0.92, 1.0);
    btn.setContentTintColor(Some(&btn_fg));
    container.addSubview(&**btn);

    // ── NSScrollView（占据按钮以上区域）
    let scroll_rect = NSRect::new(
        NSPoint::new(0.0, BTN_H),
        NSSize::new(width, height - BTN_H),
    );
    let scroll = NSScrollView::initWithFrame(NSScrollView::alloc(mtm), scroll_rect);
    scroll.setHasVerticalScroller(true);
    scroll.setHasHorizontalScroller(true);
    scroll.setAutohidesScrollers(true);
    scroll.setDrawsBackground(false);

    // ── NSTextView
    let text_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, height - BTN_H));
    let text_view = NSTextView::initWithFrame(NSTextView::alloc(mtm), text_rect);
    text_view.setEditable(false);
    text_view.setSelectable(true);
    text_view.setDrawsBackground(false);
    text_view.setTextContainerInset(NSSize::new(12.0, 12.0));
    text_view.setHorizontallyResizable(true);
    text_view.setMaxSize(NSSize::new(f64::MAX / 2.0, f64::MAX / 2.0));

    if let Some(tc) = text_view.textContainer() {
        tc.setWidthTracksTextView(false);
        tc.setContainerSize(NSSize::new(f64::MAX / 2.0, f64::MAX / 2.0));
    }

    let font = NSFont::monospacedSystemFontOfSize_weight(12.5, 0.0);
    text_view.setFont(Some(&font));
    let fg = NSColor::colorWithRed_green_blue_alpha(0.92, 0.92, 0.92, 1.0);
    text_view.setTextColor(Some(&fg));

    let full_text = format!("{}\n\n{}", title, content);
    text_view.setString(&NSString::from_str(&full_text));

    scroll.setDocumentView(Some(&**text_view));
    container.addSubview(&**scroll);

    panel.setContentView(Some(&*container));
    panel.orderFrontRegardless();

    let cancelled = Arc::new(AtomicBool::new(false));
    let panel_raw = Retained::into_raw(panel) as usize;
    let target_raw = Retained::into_raw(target) as usize;
    {
        let mut panels = ACTIVE_PANELS.lock().unwrap();
        panels.push_back(ActivePanel { raw: panel_raw, target_raw, cancelled: Arc::clone(&cancelled) });
    }

    let dismiss_after = Duration::from_secs(config.overlay_dismiss_secs);
    crate::gcd::exec_after(dismiss_after, move || {
        check_hover_and_dismiss(panel_raw, target_raw, cancelled);
    });
}

// ── 悬停检测 + 关闭 ──────────────────────────────────────────────────────────

fn check_hover_and_dismiss(panel_raw: usize, target_raw: usize, cancelled: Arc<AtomicBool>) {
    if cancelled.load(Ordering::Relaxed) {
        unsafe { drop(Retained::from_raw(target_raw as *mut AnyObject)) };
        return;
    }

    let panel: Retained<NSPanel> =
        match unsafe { Retained::from_raw(panel_raw as *mut NSPanel) } {
            Some(p) => p,
            None => return,
        };

    let frame = panel.frame();
    let mouse: NSPoint = NSEvent::mouseLocation();

    if rect_contains(frame, mouse) {
        let raw_again = Retained::into_raw(panel) as usize;
        crate::gcd::exec_after(Duration::from_millis(300), move || {
            check_hover_and_dismiss(raw_again, target_raw, cancelled);
        });
    } else {
        panel.orderOut(None::<&AnyObject>);
        unsafe { drop(Retained::from_raw(target_raw as *mut AnyObject)) };
        remove_from_active(panel_raw);
    }
}

fn remove_from_active(raw: usize) {
    let empty = {
        let mut panels = ACTIVE_PANELS.lock().unwrap();
        panels.retain(|p| p.raw != raw);
        panels.is_empty()
    };

    if empty && QUIT_ON_EMPTY.load(Ordering::Relaxed) {
        crate::gcd::exec_async(|| unsafe {
            use objc2_app_kit::NSApplication;
            let mtm = MainThreadMarker::new_unchecked();
            let app = NSApplication::sharedApplication(mtm);
            app.terminate(None::<&AnyObject>);
        });
    }
}

fn rect_contains(rect: NSRect, point: NSPoint) -> bool {
    point.x >= rect.origin.x
        && point.x <= rect.origin.x + rect.size.width
        && point.y >= rect.origin.y
        && point.y <= rect.origin.y + rect.size.height
}
