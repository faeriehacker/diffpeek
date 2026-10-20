// DiffPeek — character-level diff from your menu bar.
// Copy the OLD text, copy the NEW text, see exactly what changed.
// Single-file AppKit app; compiled on first launch by Contents/MacOS/DiffPeek.

import Cocoa
import WebKit

// MARK: - Diff engine

enum DiffOp { case equal, insert, delete }

struct DiffSegment {
    var op: DiffOp
    var text: String
}

/// Max DP cells for the LCS table (Int32 each). 16M cells ≈ 64 MB.
let maxLCSCells = 16_000_000

func tokenizeChars(_ s: String) -> [String] { s.map { String($0) } }

/// Splits into alternating runs of non-whitespace / whitespace.
func tokenizeWords(_ s: String) -> [String] {
    var out: [String] = []
    var cur = ""
    var curIsSpace: Bool? = nil
    for ch in s {
        let isSpace = ch.isWhitespace || ch.isNewline
        if let c = curIsSpace, c != isSpace {
            out.append(cur)
            cur = ""
        }
        cur.append(ch)
        curIsSpace = isSpace
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

func tokenizeLines(_ s: String) -> [String] {
    var out: [String] = []
    var cur = ""
    for ch in s {
        cur.append(ch)
        if ch == "\n" { out.append(cur); cur = "" }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

/// Classic LCS dynamic programming. dp[i][j] = LCS length of a[i...] and b[j...],
/// filled from the bottom-right so the backtrack walks forward naturally.
func lcsDiff(_ a: [String], _ b: [String]) -> [DiffSegment] {
    let n = a.count, m = b.count
    if n == 0 && m == 0 { return [] }
    if n == 0 { return [DiffSegment(op: .insert, text: b.joined())] }
    if m == 0 { return [DiffSegment(op: .delete, text: a.joined())] }

    let w = m + 1
    var dp = [Int32](repeating: 0, count: (n + 1) * (m + 1))
    for i in stride(from: n - 1, through: 0, by: -1) {
        let row = i * w
        let next = (i + 1) * w
        for j in stride(from: m - 1, through: 0, by: -1) {
            if a[i] == b[j] {
                dp[row + j] = dp[next + j + 1] + 1
            } else {
                dp[row + j] = max(dp[next + j], dp[row + j + 1])
            }
        }
    }

    var segs: [DiffSegment] = []
    var i = 0, j = 0
    while i < n && j < m {
        if a[i] == b[j] {
            segs.append(DiffSegment(op: .equal, text: a[i])); i += 1; j += 1
        } else if dp[(i + 1) * w + j] >= dp[i * w + j + 1] {
            segs.append(DiffSegment(op: .delete, text: a[i])); i += 1
        } else {
            segs.append(DiffSegment(op: .insert, text: b[j])); j += 1
        }
    }
    while i < n { segs.append(DiffSegment(op: .delete, text: a[i])); i += 1 }
    while j < m { segs.append(DiffSegment(op: .insert, text: b[j])); j += 1 }
    return segs
}

/// Strips common prefix/suffix, then diffs the middle. Falls back to coarser
/// tokens (words, then lines) when the middle is too large for the DP table.
func diffTokens(_ a: [String], _ b: [String], level: Int) -> [DiffSegment] {
    var p = 0
    while p < a.count && p < b.count && a[p] == b[p] { p += 1 }
    var s = 0
    while s < a.count - p && s < b.count - p && a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }

    let midA = Array(a[p..<(a.count - s)])
    let midB = Array(b[p..<(b.count - s)])

    var segs: [DiffSegment] = []
    if p > 0 { segs.append(DiffSegment(op: .equal, text: a[0..<p].joined())) }

    if midA.count * midB.count > maxLCSCells {
        let ja = midA.joined(), jb = midB.joined()
        switch level {
        case 0: segs.append(contentsOf: diffTokens(tokenizeWords(ja), tokenizeWords(jb), level: 1))
        case 1: segs.append(contentsOf: diffTokens(tokenizeLines(ja), tokenizeLines(jb), level: 2))
        default:
            if !ja.isEmpty { segs.append(DiffSegment(op: .delete, text: ja)) }
            if !jb.isEmpty { segs.append(DiffSegment(op: .insert, text: jb)) }
        }
    } else {
        segs.append(contentsOf: lcsDiff(midA, midB))
    }

    if s > 0 { segs.append(DiffSegment(op: .equal, text: a[(a.count - s)...].joined())) }
    return mergeSegments(segs)
}

/// Merges adjacent segments of the same op and groups each changed region as
/// "all deletions, then all insertions" so interleaved d/i/d/i reads cleanly.
func mergeSegments(_ segs: [DiffSegment]) -> [DiffSegment] {
    var out: [DiffSegment] = []
    var eq = "", del = "", ins = ""
    func flushChanges() {
        if !del.isEmpty { out.append(DiffSegment(op: .delete, text: del)); del = "" }
        if !ins.isEmpty { out.append(DiffSegment(op: .insert, text: ins)); ins = "" }
    }
    func flushEqual() {
        if !eq.isEmpty { out.append(DiffSegment(op: .equal, text: eq)); eq = "" }
    }
    for s in segs {
        switch s.op {
        case .equal:
            flushChanges()
            eq += s.text
        case .delete:
            flushEqual()
            del += s.text
        case .insert:
            flushEqual()
            ins += s.text
        }
    }
    flushChanges()
    flushEqual()
    return out
}

func collapseWhitespace(_ s: String) -> String {
    s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func computeDiff(old: String, new: String, ignoreWhitespace: Bool) -> [DiffSegment] {
    let o = ignoreWhitespace ? collapseWhitespace(old) : old
    let n = ignoreWhitespace ? collapseWhitespace(new) : new
    return diffTokens(tokenizeChars(o), tokenizeChars(n), level: 0)
}

// MARK: - HTML rendering

func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// Changed text gets a visible ↵ so inserted/removed line breaks are noticeable.
func htmlChanged(_ s: String) -> String {
    htmlEscape(s).replacingOccurrences(of: "\n", with: "↵\n")
}

let pageCSS = """
:root{color-scheme:light dark;
  --bg:#ffffff;--fg:#1d1d1f;--muted:#6e6e73;--border:#e3e3e8;
  --del-bg:#ffd7d5;--del-fg:#8a1f11;--ins-bg:#ccffd8;--ins-fg:#0f5323;}
@media (prefers-color-scheme:dark){:root{
  --bg:#1e1e20;--fg:#e8e8ea;--muted:#9a9aa0;--border:#3a3a3f;
  --del-bg:#5a1f1f;--del-fg:#ffb3ad;--ins-bg:#1c4a2a;--ins-fg:#9be7ad;}}
html,body{margin:0;background:var(--bg);color:var(--fg);}
body{padding:10px 12px;font:12.5px/1.6 ui-monospace,"SF Mono",Menlo,monospace;}
.summary{display:flex;gap:14px;align-items:baseline;margin:0 0 10px;
  font:12px -apple-system,system-ui,sans-serif;color:var(--muted);}
.summary .ins{color:var(--ins-fg);font-weight:600}
.summary .del{color:var(--del-fg);font-weight:600}
pre{white-space:pre-wrap;word-wrap:break-word;overflow-wrap:anywhere;margin:0;font:inherit;}
del{background:var(--del-bg);color:var(--del-fg);text-decoration:line-through;border-radius:3px;padding:0 1px;}
ins{background:var(--ins-bg);color:var(--ins-fg);text-decoration:none;border-radius:3px;padding:0 1px;font-weight:600;}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:10px;}
.col{border:1px solid var(--border);border-radius:8px;padding:8px 10px;min-width:0;}
.col h4{margin:0 0 6px;font:600 11px -apple-system,system-ui,sans-serif;color:var(--muted);letter-spacing:.06em;}
.hint{color:var(--muted);font:13px/1.5 -apple-system,system-ui,sans-serif;text-align:center;padding:28px 12px;}
.hint kbd{font:inherit;border:1px solid var(--border);border-radius:4px;padding:0 5px;}
"""

func renderHTML(segments: [DiffSegment], sideBySide: Bool, hint: String?) -> String {
    var body = ""
    if let hint = hint {
        body = "<div class=\"hint\">\(hint)</div>"
    } else {
        var added = 0, removed = 0
        for s in segments {
            if s.op == .insert { added += s.text.count }
            if s.op == .delete { removed += s.text.count }
        }
        let summary: String
        if added == 0 && removed == 0 {
            summary = "<div class=\"summary\">No differences.</div>"
        } else {
            summary = "<div class=\"summary\"><span class=\"ins\">+\(added) added</span>"
                + "<span class=\"del\">−\(removed) removed</span><span>(characters)</span></div>"
        }
        if sideBySide {
            var left = "", right = ""
            for s in segments {
                switch s.op {
                case .equal:
                    left += htmlEscape(s.text); right += htmlEscape(s.text)
                case .delete:
                    left += "<del>\(htmlChanged(s.text))</del>"
                case .insert:
                    right += "<ins>\(htmlChanged(s.text))</ins>"
                }
            }
            body = summary + "<div class=\"cols\"><div class=\"col\"><h4>OLD</h4><pre>\(left)</pre></div>"
                + "<div class=\"col\"><h4>NEW</h4><pre>\(right)</pre></div></div>"
        } else {
            var inline = ""
            for s in segments {
                switch s.op {
                case .equal: inline += htmlEscape(s.text)
                case .delete: inline += "<del>\(htmlChanged(s.text))</del>"
                case .insert: inline += "<ins>\(htmlChanged(s.text))</ins>"
                }
            }
            body = summary + "<pre>\(inline)</pre>"
        }
    }
    return "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(pageCSS)</style></head><body>\(body)</body></html>"
}

// MARK: - App

func launchLog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiffPeek-launch.log")
    let line = "\(Date()) app: \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        if let d = line.data(using: .utf8) { h.write(d) }
        h.closeFile()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
    NSLog("DiffPeek: %@", msg)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var oldTextView: NSTextView!
    var newTextView: NSTextView!
    var webView: WKWebView!
    var modeControl: NSSegmentedControl!
    var statusLabel: NSTextField!
    var oldLabel: NSTextField!
    var newLabel: NSTextField!
    var watchItem: NSMenuItem!
    var wsItem: NSMenuItem!
    var dockItem: NSMenuItem!
    var watchEnabled = true
    var ignoreWhitespace = true
    var showInDock: Bool {
        get { UserDefaults.standard.bool(forKey: "showInDock") }
        set { UserDefaults.standard.set(newValue, forKey: "showInDock") }
    }

    var clipboardTimer: Timer?
    var lastChangeCount = NSPasteboard.general.changeCount
    var hasPositionedPanel = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchLog("applicationDidFinishLaunching")
        if showInDock { NSApp.setActivationPolicy(.regular) }
        buildMainMenu()
        buildStatusItem()
        launchLog("status item created, button=\(statusItem.button != nil)")
        buildPanel()
        launchLog("panel built")
        startClipboardWatcher()
        updateDiff()
        togglePanel()   // show the panel on launch so there's immediate feedback
        launchLog("panel visible=\(panel.isVisible) frame=\(panel.frame)")
    }

    // Clicking the app in Finder/Dock while it's already running brings the panel back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { togglePanel() }
        return true
    }

    // Edit menu so ⌘C / ⌘V / ⌘A work inside the text boxes (menu bar apps have no visible menu).
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DiffPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "arrow.left.arrow.right.square", accessibilityDescription: "DiffPeek")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "DiffPeek — click to show/hide, right-click for menu"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func statusItemClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "Hide DiffPeek" : "Show DiffPeek", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "Clear", action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit DiffPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if !hasPositionedPanel { positionPanelUnderStatusItem(); hasPositionedPanel = true }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func positionPanelUnderStatusItem() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return }
        let x = v.midX - panel.frame.width / 2
        let y = v.maxY - panel.frame.height - 12
        panel.setFrameOrigin(NSPoint(x: max(v.minX + 8, x), y: max(v.minY + 8, y)))
    }

    func buildPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "DiffPeek"
        panel.isFloatingPanel = true
        panel.level = .floating                       // always on top
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 480, height: 320)
        panel.setFrameAutosaveName("DiffPeekPanel")

        // Toolbar row: [Inline | Side by side]   status…   [⇄ Swap] [Clear] [⚙]
        modeControl = NSSegmentedControl(labels: ["Inline", "Side by side"], trackingMode: .selectOne,
                                         target: self, action: #selector(settingsChanged))
        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .rounded

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let swapButton = NSButton(title: "⇄ Swap", target: self, action: #selector(swapSides))
        swapButton.bezelStyle = .rounded
        swapButton.toolTip = "Swap OLD and NEW"
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded

        let gear = NSPopUpButton(frame: .zero, pullsDown: true)
        gear.bezelStyle = .rounded
        gear.toolTip = "Options"
        let gearMenu = NSMenu()
        let gearTitle = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        gearTitle.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Options")
        gearMenu.addItem(gearTitle)   // pull-down buttons show the first item as their face
        watchItem = NSMenuItem(title: "Watch clipboard", action: #selector(toggleWatch), keyEquivalent: "")
        watchItem.target = self
        watchItem.state = .on
        watchItem.toolTip = "While the panel is open: first ⌘C fills OLD, second fills NEW, later ones shift NEW→OLD"
        wsItem = NSMenuItem(title: "Ignore whitespace", action: #selector(toggleWhitespace), keyEquivalent: "")
        wsItem.target = self
        wsItem.state = .on
        wsItem.toolTip = "Collapse line wraps and runs of spaces before comparing"
        dockItem = NSMenuItem(title: "Show in Dock", action: #selector(toggleDock), keyEquivalent: "")
        dockItem.target = self
        dockItem.state = showInDock ? .on : .off
        dockItem.toolTip = "Show a Dock icon with a running indicator (also appears in ⌘-Tab)"
        gearMenu.addItem(watchItem)
        gearMenu.addItem(wsItem)
        gearMenu.addItem(dockItem)
        gearMenu.addItem(NSMenuItem.separator())
        gearMenu.addItem(withTitle: "Quit DiffPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        gear.menu = gearMenu
        gear.setContentHuggingPriority(.required, for: .horizontal)

        let toolbar = NSStackView(views: [modeControl, statusLabel, swapButton, clearButton, gear])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // OLD / NEW boxes
        let (oldCol, oldTV) = makeColumn(title: "OLD")
        let (newCol, newTV) = makeColumn(title: "NEW")
        oldTextView = oldTV
        newTextView = newTV

        // Result
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        for v in [toolbar, oldCol, newCol, webView] as [NSView] { content.addSubview(v) }
        let m: CGFloat = 12
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            oldCol.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            oldCol.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            oldCol.heightAnchor.constraint(equalToConstant: 118),
            newCol.topAnchor.constraint(equalTo: oldCol.topAnchor),
            newCol.heightAnchor.constraint(equalTo: oldCol.heightAnchor),
            newCol.leadingAnchor.constraint(equalTo: oldCol.trailingAnchor, constant: 10),
            newCol.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            newCol.widthAnchor.constraint(equalTo: oldCol.widthAnchor),

            webView.topAnchor.constraint(equalTo: oldCol.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
        ])
        panel.contentView = content
    }

    func makeColumn(title: String) -> (NSView, NSTextView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        if title == "OLD" { oldLabel = label } else { newLabel = label }

        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.delegate = self

        let col = NSView()
        col.translatesAutoresizingMaskIntoConstraints = false
        col.addSubview(label)
        col.addSubview(scroll)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: col.topAnchor),
            label.leadingAnchor.constraint(equalTo: col.leadingAnchor, constant: 2),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: col.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: col.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: col.bottomAnchor),
        ])
        return (col, tv)
    }

    /// NSTextView.string hands back a live reference to the view's backing store, so it
    /// changes under you when the view is edited. Always take a detached copy.
    func text(_ tv: NSTextView) -> String {
        (tv.string as NSString).copy() as! String
    }

    // MARK: Clipboard watching

    func startClipboardWatcher() {
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
    }

    func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard watchEnabled, panel.isVisible else { return }
        // Ignore copies made inside DiffPeek itself (e.g. from the OLD/NEW boxes).
        if NSApp.isActive && panel.isKeyWindow { return }
        guard let s = pb.string(forType: .string), !s.isEmpty else { return }

        let old = text(oldTextView)
        let new = text(newTextView)
        if s == new || (new.isEmpty && s == old) { return }

        if new.isEmpty {
            if old.isEmpty { oldTextView.string = s } else { newTextView.string = s }
        } else {
            oldTextView.string = new
            newTextView.string = s
        }
        updateDiff()
    }

    // MARK: Actions

    @objc func settingsChanged() { updateDiff() }

    @objc func toggleWatch() {
        watchEnabled.toggle()
        watchItem.state = watchEnabled ? .on : .off
        updateDiff()
    }

    @objc func toggleDock() {
        showInDock.toggle()
        dockItem.state = showInDock ? .on : .off
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock { NSApp.activate(ignoringOtherApps: true) }
    }

    @objc func toggleWhitespace() {
        ignoreWhitespace.toggle()
        wsItem.state = ignoreWhitespace ? .on : .off
        updateDiff()
    }

    @objc func swapSides() {
        let o = text(oldTextView)
        let n = text(newTextView)
        oldTextView.string = n
        newTextView.string = o
        updateDiff()
    }

    @objc func clearAll() {
        oldTextView.string = ""
        newTextView.string = ""
        updateDiff()
    }

    func textDidChange(_ notification: Notification) { updateDiff() }

    func updateDiff() {
        let old = text(oldTextView)
        let new = text(newTextView)
        oldLabel.stringValue = old.isEmpty ? "OLD" : "OLD · \(old.count) chars"
        newLabel.stringValue = new.isEmpty ? "NEW" : "NEW · \(new.count) chars"
        let watching = watchEnabled
        let sideBySide = modeControl.selectedSegment == 1

        var hint: String? = nil
        if old.isEmpty && new.isEmpty {
            hint = watching
                ? "Select the <b>old</b> text anywhere and press <kbd>⌘C</kbd>.<br>Then select the <b>new</b> text and press <kbd>⌘C</kbd> again."
                : "Paste the old text into OLD and the new text into NEW."
            statusLabel.stringValue = watching ? "Waiting for OLD (⌘C)" : "Clipboard watch is off"
        } else if new.isEmpty {
            hint = watching
                ? "Got OLD. Now select the <b>new</b> text and press <kbd>⌘C</kbd>."
                : "Paste the new text into NEW."
            statusLabel.stringValue = watching ? "Got OLD — now copy NEW (⌘C)" : "Clipboard watch is off"
        } else if old.isEmpty {
            hint = "Paste the old text into OLD."
            statusLabel.stringValue = "Missing OLD"
        } else {
            statusLabel.stringValue = watching ? "⌘C again to compare against NEW" : ""
        }

        let segments = hint == nil ? computeDiff(old: old, new: new, ignoreWhitespace: ignoreWhitespace) : []
        let html = renderHTML(segments: segments, sideBySide: sideBySide, hint: hint)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
