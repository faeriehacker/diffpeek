DiffPeek — character-level diff from your menu bar
===================================================

HOW TO USE
  1. Click the ⇄ icon in the menu bar. The floating panel appears (always on top).
  2. Select the OLD text anywhere (a web page, an editor, a chat...) and press ⌘C.
  3. Select the NEW text and press ⌘C.
  4. The panel shows the diff: red strikethrough = removed, green = added.
     Copy again and it compares the newest copy against the previous one.
  You can also paste directly into the OLD / NEW boxes and edit them.

TOOLBAR
  Watch clipboard    — turn automatic clipboard capture on/off (only active while the panel is open)
  Ignore whitespace  — collapse line wraps / repeated spaces so GitHub's wrapping isn't flagged
  Inline / Side by side — how the result is shown
  ⇄ Swap             — swap OLD and NEW
  Clear              — start over
  Right-click the menu bar icon for Show/Hide, Clear, Quit.

FIRST LAUNCH
  The app compiles itself from Contents/Resources/DiffPeek.swift the first time it
  opens (a few seconds; needs the Xcode Command Line Tools, which Homebrew already
  installed). Build output goes to ~/Library/Logs/DiffPeek-build.log.

  If macOS says the app "can't be opened" or is from an unidentified developer:
  right-click DiffPeek.app → Open → Open, or run in Terminal:
      xattr -dr com.apple.quarantine ~/Applications/DiffPeek.app

  If double-clicking does nothing, make the launcher executable:
      chmod +x ~/Applications/DiffPeek.app/Contents/MacOS/DiffPeek

START AT LOGIN (optional)
  System Settings → General → Login Items → "+" → choose DiffPeek.

CUSTOMIZE
  Everything is in Contents/Resources/DiffPeek.swift. Edit it and relaunch —
  the launcher rebuilds automatically when the source is newer than the binary.
