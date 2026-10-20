# DiffPeek

A tiny macOS menu bar app that shows a **character-level diff** of the last two things you copied.

Copy the old text, copy the new text, and a floating panel shows exactly which characters changed — red strikethrough for removed, green for added. Built for the moment when a diff tool only shows you that a long line changed, but not *what* changed inside it.

## How it works

1. Click the ⇄ icon in the menu bar (or open the app). A floating, always-on-top panel appears.
2. Select the **old** text anywhere and press ⌘C.
3. Select the **new** text and press ⌘C.
4. The panel shows the diff with a "+N added / −N removed" summary. Copy something else and it compares against the previous copy.

You can also paste or type directly into the OLD / NEW boxes.

**Toolbar**

| Control | What it does |
|---|---|
| Watch clipboard | Automatic capture on/off. Only active while the panel is open, so normal copy/paste is unaffected. |
| Ignore whitespace | Collapses line wraps and repeated spaces, so text copied from a wrapped web page isn't flagged. |
| Inline / Side by side | One merged view, or OLD and NEW as two columns. |
| ⇄ Swap | Swap OLD and NEW. |
| Clear | Start over. |

Right-click the menu bar icon for Show/Hide, Clear and Quit. The panel follows your light/dark appearance.

## Install

Requirements: an Apple Silicon Mac running macOS 12 or later, and the Xcode Command Line Tools (`xcode-select --install` — already present if you use Homebrew or Git).

```bash
git clone https://github.com/faeriehacker/diffpeek.git
cp -R diffpeek/DiffPeek.app ~/Applications/
open ~/Applications/DiffPeek.app
```

The first launch compiles the app from source (a few seconds). Because it isn't signed with an Apple developer certificate, macOS may block that first launch: open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. This is a one-time step.

To start it at login: System Settings → General → Login Items → **+** → DiffPeek.

## How it's built

The whole app is one Swift file, `DiffPeek.app/Contents/Resources/DiffPeek.swift`, using AppKit and WebKit — no dependencies. The launcher script at `Contents/MacOS/DiffPeek` compiles it with `swiftc` on first run and whenever the source changes, so editing the `.swift` file and relaunching is the entire development loop.

The diff is a classic longest-common-subsequence comparison on characters, with common prefix/suffix trimming and a fallback to word- and line-level comparison for very large inputs.

Logs go to `~/Library/Logs/DiffPeek-build.log` and `~/Library/Logs/DiffPeek-launch.log`.

## Privacy

DiffPeek runs entirely on your Mac. It reads the clipboard only while its panel is open, keeps nothing between launches, and makes no network connections.

## License

MIT — see [LICENSE](LICENSE).
