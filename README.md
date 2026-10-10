# Claude Guardian

A macOS menu bar app that shows the Claude Code sessions running on your Mac:

```
⚙ 3  ✋ 1  ☾ 2
```

- **⚙ working**: Claude is thinking or running tools
- **✋ waiting for you**: Claude needs a permission or has asked you a question
- **☾ idle**: the turn is over and the session is waiting for a new prompt (also includes "working" sessions with no activity for more than 10 minutes)

Click the icon to see your sessions grouped by app and then by project, each shown with its title:

```
Working: 2 · Waiting for you: 1 · Idle: 1
─────────────
IntelliJ IDEA
   📁 shop
         ✋  Migrate to Spring 3 · Waiting for you · now
─────────────
Visual Studio Code
   📁 mangiaresg-app
         ⚙️  Fix OAuth login · Working · 2 min. ago
         💤  Refactor menu · Idle · 11 min. ago
```

Apps, projects and sessions are sorted by urgency: anything waiting for you comes first, then working, then idle. Clicking a project brings its window to the front. On each session:

- **click**: jump back to the app and window the session was started from
- **Option+click**: reveal the project folder in Finder
- **Shift+click**: copy diagnostics to the clipboard (permissions, windows found, which one gets picked), useful if the wrong window opens

It works with sessions started from a terminal, VS Code, IntelliJ/JetBrains, and with sessions you drive from your phone through Remote Control, since they all run on your Mac.

## How it works

1. A Claude Code hook (`hooks/claude-activity-hook.sh`) runs on every state change and writes a small file to `~/.claude/activity/<session_id>.json` with the state, folder, project root, transcript path, PID, originating app and terminal.
2. The app watches that folder, drops sessions whose process no longer exists, and updates the menu bar.

| Claude Code event | State |
|---|---|
| `SessionStart`, `Stop` | idle |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | working |
| `Notification` (permission or question) | waiting for you |
| `Notification` ("waiting for your input") | idle |
| `SessionEnd` | file removed |

Claude Code does not run the `Stop` hook when you interrupt a turn (Esc or the stop button) or when a turn ends with an API error. The app detects both from the session transcript and marks the session as idle.

### Session titles

The title shown in the menu is, in order of preference:

1. the name set with `/rename` (or `--name`);
2. the title Claude Code generates automatically;
3. the first message you wrote in the session, truncated to 60 characters.

It is read incrementally from the session transcript (only new lines are read). The transcript format is not a documented API, so the parser accepts several field names and falls back to the first prompt.

## Installation

### From a release (no build needed)

1. Download `ClaudeGuardian-<version>.zip` from the [Releases](https://github.com/fcaldarelli/claude-guardian-macos/releases) page and unzip it. It runs on Apple Silicon and Intel Macs with macOS 13+.
2. Install the hooks: in Terminal, `cd` into the unzipped folder and run `./install-hooks.sh` (see [Hooks](#1-hooks) below).
3. Move `Claude Guardian.app` to `/Applications` and open it.

#### "Claude Guardian can't be opened" (Gatekeeper)

The app is free and open source, so it is not signed with a paid Apple Developer ID or notarized by Apple. The first time you open it, macOS blocks it with a message like *"Apple could not verify Claude Guardian is free of malware"*. To open it anyway, use one of these:

- **System Settings**: try to open the app once, then go to System Settings › Privacy & Security, scroll down to the message about Claude Guardian and click **Open Anyway**. Confirm with your password. You only need to do this once.
- **Terminal**: remove the quarantine flag macOS adds to downloaded files:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/Claude Guardian.app"
  ```

If macOS says the app *"is damaged and can't be opened"*, use the Terminal command above: that message also comes from the quarantine flag, not from a broken download. If you would rather not trust a prebuilt binary, build the app from source as described below.

### From source

#### 1. Hooks

```bash
./install-hooks.sh
```

This copies the hook to `~/.claude/hooks/` and registers it in `~/.claude/settings.json` (a backup is made, and existing hooks are kept). It uses `jq`, which ships with macOS 15+; without `jq`, merge the contents of `hooks/hooks-settings.json` into your settings manually.

Restart any Claude Code sessions that are already open so they pick up the hooks.

#### 2. App

Requires macOS 13+ with Xcode or the Command Line Tools (`xcode-select --install`).

```bash
cd app
./build-app.sh
cp -R "build/Claude Guardian.app" /Applications/
open "/Applications/Claude Guardian.app"
```

You can enable **Open at Login** from the menu. Alternatively, open the `app` folder in Xcode (File › Open, select `Package.swift`) and run it from there.

### Version

The version is defined in code, in `app/Sources/ClaudeGuardian/AppInfo.swift`:

```swift
static let version = "1.0.0"
static let build = "1"
```

To release a new version, change these values and run `build-app.sh --release`. It builds a universal binary (Apple Silicon and Intel) and creates `app/build/ClaudeGuardian-<version>.zip` with the app, the hooks, `install-hooks.sh` and the license, ready to attach to a GitHub release; it also prints the zip's SHA-256 for the release notes. The menu shows the version from this file, and the build script reads the same values to write them into `Info.plist`, so Finder's "Get Info" always matches.

### Icon

The icon lives in `app/icon/` (`AppIcon.icns` plus a 1024 px PNG) and is bundled by `build-app.sh`. It is generated by `app/icon/make-icon.py`: to change colors or shapes, edit the values at the top of the script and run it again (`python3 make-icon.py`, requires Pillow).

If Finder still shows a generic icon after installing, restart the Dock with `killall Dock`.

### Quick try without building: SwiftBar

With [SwiftBar](https://github.com/swiftbar/SwiftBar) installed, copy `swiftbar/claude-guardian.2s.sh` into its plugin folder. It shows the same counts and list; clicking a session brings its app to the front, but does not select the exact terminal tab.

## Jumping back to the originating app

The hook records the app that started the session, its terminal (tty) and the **project root** (the first parent folder containing `.idea`, `.vscode` or `.git`). On click, the app tries, in order:

1. **Terminal and iTerm2**: select the exact tab via its tty.
2. **Window by title**: find the app window whose title contains the project name and bring it to the front. Requires the Accessibility permission.
3. **Editors**: ask the editor to open the project root, which brings forward the window already showing that project. For IntelliJ and other JetBrains IDEs this uses the same mechanism as the command-line launcher (`idea /path`), which also works with full-screen windows in other Spaces.
4. Otherwise, bring the app to the front.

| App | Precision |
|---|---|
| Terminal, iTerm2 | Exact tab, even with many windows |
| VS Code, Cursor, Windsurf, Zed, IntelliJ and other JetBrains IDEs | The project window, even with several projects open and sessions started in subfolders |
| Ghostty, Warp, WezTerm, kitty, Alacritty, Hyper | The window whose title contains the project name or path; otherwise the app |
| Claude desktop app and others | The app |
| Not identified (e.g. inside `tmux`) | The folder in Finder |

If several copies of the same app are installed (e.g. IntelliJ Ultimate and Community), the one that actually started the session is used.

### Permissions

- **Accessibility**: choose *Enable Accessibility to Open the Right Window…* from the menu and turn on Claude Guardian in System Settings › Privacy & Security › Accessibility. Without it the app still works, but for non-scriptable terminals it brings forward the app rather than the specific window.
- **Automation**: for Terminal and iTerm2, macOS asks the first time whether Claude Guardian may control them.

Because the app is ad-hoc signed, macOS may treat each new build as a different app and drop the Accessibility permission. If that happens, remove Claude Guardian from the list and add it again.

### Limitations

- **Two sessions in the same project** in one editor (two integrated-terminal tabs in the same window): the right window opens, but not the specific tab.
- In non-scriptable terminals the window is found only if its title contains the project name or path; if several windows match ambiguously, the app is activated instead of risking the wrong window.
- A very long command (e.g. a 15-minute build) can show as idle ("No activity") until it finishes, because there is no hook event or transcript write while it runs.

## Notes

- The hooks are installed in your **user** settings, so they apply to every project.
- Claude Code on the web (cloud) sessions are not shown: they run on Anthropic's servers, not on your Mac.
- The app is not sandboxed, because it needs to read `~/.claude/activity`.

## Uninstall

```bash
rm -rf "/Applications/Claude Guardian.app" ~/.claude/activity ~/.claude/hooks/claude-activity-hook.sh
```

Then remove the entries containing `claude-activity-hook` from `~/.claude/settings.json` (or restore the backup).

## License

[MIT](LICENSE)
