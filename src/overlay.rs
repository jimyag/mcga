#![cfg(target_os = "macos")]

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::MainThreadOnly;
use objc2_app_kit::{
    NSBackingStoreType, NSColor, NSEvent, NSFont, NSFloatingWindowLevel, NSPanel, NSScreen,
    NSScrollView, NSTextView, NSView, NSWindowStyleMask,
};
use objc2_foundation::{MainThreadMarker, NSPoint, NSRect, NSSize, NSString};

use crate::config::Config;
use crate::parser::ParseResult;

// ── 活跃浮层槽位（最多两个）────────────────────────────────────────────────

struct ActivePanel {
    raw: usize,
    cancelled: Arc<AtomicBool>,
}

static ACTIVE_PANELS: Mutex<VecDeque<ActivePanel>> = Mutex::new(VecDeque::new());

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
        }
        panels.len() // 0 or 1 → slot index for new panel
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

    // NSScrollView（双向滚动）
    let scroll_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, height));
    let scroll = NSScrollView::initWithFrame(NSScrollView::alloc(mtm), scroll_rect);
    scroll.setHasVerticalScroller(true);
    scroll.setHasHorizontalScroller(true);
    scroll.setAutohidesScrollers(true);
    scroll.setDrawsBackground(false);

    // NSTextView（横向可扩展，不换行）
    let text_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, height));
    let text_view = NSTextView::initWithFrame(NSTextView::alloc(mtm), text_rect);
    text_view.setEditable(false);
    text_view.setSelectable(true);
    text_view.setDrawsBackground(false);
    text_view.setTextContainerInset(NSSize::new(12.0, 12.0));
    text_view.setHorizontallyResizable(true);
    text_view.setMaxSize(NSSize::new(f64::MAX / 2.0, f64::MAX / 2.0));

    if let Some(container) = text_view.textContainer() {
        container.setWidthTracksTextView(false);
        container.setContainerSize(NSSize::new(f64::MAX / 2.0, f64::MAX / 2.0));
    }

    // NSFontWeight 是 CGFloat 的别名，Regular = 0.0
    let font = NSFont::monospacedSystemFontOfSize_weight(12.5, 0.0);
    text_view.setFont(Some(&font));

    let fg = NSColor::colorWithRed_green_blue_alpha(0.92, 0.92, 0.92, 1.0);
    text_view.setTextColor(Some(&fg));

    let full_text = format!("{}\n\n{}", title, content);
    text_view.setString(&NSString::from_str(&full_text));

    let text_as_view: &NSView = &**text_view;
    scroll.setDocumentView(Some(text_as_view));

    let scroll_as_view: &NSView = &**scroll;
    panel.setContentView(Some(scroll_as_view));

    panel.orderFrontRegardless();

    let cancelled = Arc::new(AtomicBool::new(false));
    let panel_raw = Retained::into_raw(panel) as usize;
    {
        let mut panels = ACTIVE_PANELS.lock().unwrap();
        panels.push_back(ActivePanel { raw: panel_raw, cancelled: Arc::clone(&cancelled) });
    }

    let dismiss_after = Duration::from_secs(config.overlay_dismiss_secs);
    crate::gcd::exec_after(dismiss_after, move || {
        check_hover_and_dismiss(panel_raw, cancelled);
    });
}

// ── 悬停检测 + 关闭 ──────────────────────────────────────────────────────────

fn check_hover_and_dismiss(panel_raw: usize, cancelled: Arc<AtomicBool>) {
    if cancelled.load(Ordering::Relaxed) {
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
            check_hover_and_dismiss(raw_again, cancelled);
        });
    } else {
        panel.orderOut(None::<&AnyObject>);
        remove_from_active(panel_raw);
    }
}

fn remove_from_active(raw: usize) {
    if let Ok(mut panels) = ACTIVE_PANELS.lock() {
        panels.retain(|p| p.raw != raw);
    }
}

fn rect_contains(rect: NSRect, point: NSPoint) -> bool {
    point.x >= rect.origin.x
        && point.x <= rect.origin.x + rect.size.width
        && point.y >= rect.origin.y
        && point.y <= rect.origin.y + rect.size.height
}
