---
name: deveco-cli
description: >-
  **MUST** use 'devecocli' for HarmonyOS apps (scaffold, build, run, debug, devices, emulators, logs, docs, UI inspection, 鸿蒙开发文档, skills). **REQUIRED** and **MANDATORY** if workspace has build-profile.json5 or oh-package.json5, or user mentions HarmonyOS, 鸿蒙, DevEco, ArkTS, ArkUI, docs, 鸿蒙文档, 知识, 搜索, skills, UI, UI测试, 组件调试.
---

# DevEco CLI

`devecocli` wraps DevEco Studio's `hvigor`, `ohpm`, `hdc`, emulator toolchain, and bundled skills installer. **Prefer `devecocli` over invoking underlying tools directly.**

Available commands: `build`, `check`, `run`, `update`, `device`, `emulator`, `ui`, `skills`, `log`, `create`, `init`, `serve`, `docs`, `signature`, `auth`.

**Sandbox Rule**: Commands tagged `[Outside sandbox]` must be run outside the sandbox.

## 1. Code → Build → Deploy → Run → Debug

### `devecocli create`
Scaffold a new HarmonyOS project.
- `--app-name <name>` (Req): 1–200 chars, `^[a-zA-Z][a-zA-Z0-9_]*$`
- `--project-path <path>`: Auto-created if omitted (`./<app-name>`). Must be empty if exists.
- `--bundle-name <bundle>`: Default `com.example.<appname-lowercase>`. 7–128 chars, ≥3 segments.
- `--api-level <level>`: int ≥17 (default: auto or 23).
*Ex*: `devecocli create --app-name MyApp --project-path ./CustomDir --api-level 23`

### `devecocli build` `[Outside sandbox]`
Compile and package project/modules. (Defaults: `--product default`, `--build-mode debug`)
| Goal | Command |
|---|---|
| Single-module / single-`entry` | `devecocli build` |
| Specific modules | `devecocli build --modules <m1> <m2>@<target>` |
| Whole product bundle (.app) | `devecocli build --product <name>` |
| Clean build outputs | `devecocli build clean` |

### `devecocli check lint`
Run DevEco Code Linter checks for TS/ArkTS code.
- `[path]`: File or directory to lint. Defaults to the project root from `build-profile.json5`, otherwise the current directory.
- Options: `--config-path <file>`, `--fix`, `--incremental`, `--product <name>`, `--format <default|json>`, `--output-path <path>`, `--limit <number>`.
- Set `DEVECO_CLI_CLT_PATH` to the Command Line Tools root when DevEco Studio is not installed; CLT is not discovered automatically from PATH or default installation directories.

### `devecocli emulator`
Manage local emulator instances and system images.
- `list`: Show instances (status, serial, device type). Opt: `--format <table|json>` (default: `table`).
- `start <names...>`: Start instances. Quote names with spaces. (See Troubleshooting if blocked).
- `stop <names...>`: Stop by name or serial (`127.0.0.1:<port>`).
- Scene control commands require Emulator 7.0 or later. Use `DEVECO_CLI_DEBUG=1` to inspect the underlying `Emulator` command mapping.
- `shake` / `power` / `rotate <left|right>` / `volume <up|down>` (Req: `--target <nameOrSerial>`): Basic emulator controls.
- `fold <state>` (Req: `--target <nameOrSerial>`): Set foldable display state, matched against the target emulator's reported `deviceType`. `foldable` uses `open|half-open|close`; `2in1_foldable` uses `open|vertical-open|half-open|close`; `triplefold` uses `single|double|triple` or one of its six left/right folded-state combinations. Other device types and cross-device states are rejected before execution.
- `battery` (Req: `--target`; one of `--level <0-100>` or `--status <charging|discharging>`): Set battery state. `--level` checks the current emulator charging state automatically (`0-100` while charging, `1-100` otherwise).
- `geolocation` (Req: `--target`; one of `--longitude`, `--latitude`, `--altitude`, `--direction`): Inject GPS data.
- `scene <outdoorRunning|outdoorCycling|drivingNavigation>` (Req: `--target`): Start motion simulation.
- `sensor` (Req: `--target`; one of `--light-intensity`, `--humidity`, `--temperature`, `--steps`, `--heartrate`): Inject sensor data.
- `create <name>` (Req: `--device-type`, `--os-version`): Create instance. Optional: `--force`.
- `delete <name>`: Delete instance.
- `image list`: List downloaded images. Opts: `--device-type <type>`, `--all`, `--format <table|json>`.
- `image download` / `image remove` (Req: `--device-type`, `--os-version`): Download/remove image. (Takes 30+ min, set long timeout).
*Device types*: `phone`, `foldable`, `widefold`, `triplefold`, `tablet`, `2in1`, `2in1 foldable`, `wearable`, `tv`.

### `devecocli ui`
Inspect UI on a connected physical device or running emulator.
- `screenshot`: Capture a screenshot from a physical device or running emulator. `--device <name|serial>` is optional when exactly one device is connected, and required when multiple devices are connected.
- Optional: `--display <displayId>`. Required: `--path <path>` (existing directory or PNG file path, including paths relative to the current directory; writable destination; no overwrite).
- Implementation uses `hdc shell snapshot_display` and `hdc file recv`; set `DEVECO_CLI_DEBUG=1` to inspect the actual `hdc` commands.
*Ex*: `devecocli ui screenshot --device Phone --path ./screenshots/phone.png`

### `devecocli docs`
Search/read local HarmonyOS docs.
- `search <keywords...>`: Match any keyword. Opts: `--catalog <name>`, `--format <default|json>`, `--limit <n>`.
- `read <documentId>`: Read full content by ID (e.g. `devecocli docs read 开发指南/冷启动_Launch分析/Launch模板基本操作/ide-insight-session-launch`).
- `catalog`: List available catalogs.

### `devecocli device`
- `list`: Show active real devices and running emulators.
- `view`: Detailed info. Req `-t <name|serial>` on multi-device hosts.

### `devecocli run` `[Outside sandbox]`
Build, install, and launch.
- `--module <module>`: Target module (auto-selected if only one runnable).
- `--device <name|serial>`: Target device (Req if multiple connected).
- `--product <product>` / `--build-mode <mode>`: Defaults: `default` / `debug`.
- `--ability <ability>`: Default from `module.json5`.
- `--uninstall`: Uninstall existing app first (Fixes signing key issues).
- `--skip-build`: Deploy existing artifacts.
- `--apply <fileName>`: **Fast incremental deploy** — rebuilds only changed files into a signed hqf, installs via `bm quickfix -a -f -o`, then restarts the app. Much faster than a full `devecocli run` for iterating on code changes. Modules are auto-detected from the file paths in `<fileName>` (no `--module` needed).
  - `<fileName>`: a plain file name (no path separators) under the project's `.hvigor/` directory; the caller writes the changed-file list there. File name is sanitized to prevent path traversal. Content: list of **source file paths changed this round** (one per line, relative to project root or absolute; `#` comments and blank lines ignored; typically `.ets`/`.ts`/`.cpp`/resource files). The changeFileList is **incrementally merged** — only list files changed since the last apply; previously listed files are retained automatically.
  - **Prereq**: DevEco Studio ≥6.1.1 (hvigor `assembleDevHqf` support; below is rejected with an upgrade hint); run `devecocli run` once first (full build + deploy + generates the `buildConfig.json` cache that `--apply` reuses).
  - **If changes don't take effect**: check `<module>/build/config/buildConfig.json` has content — empty/missing means `devecocli run` wasn't run; on any apply failure, fall back to a full `devecocli run`.
*Ex*: `devecocli run` → edit code → write `.hvigor/changes.txt` → `devecocli run --apply changes.txt`
- `--hotreload [action]`: **Hot-reload watch session** — must be started as a **background process** (the process holds a persistent socket to the hvigor daemon). It builds the hap in hot-reload mode (`hotReload=true debuggable=true`), deploys+launches the app, then the process itself connects a socket to the daemon and sends `CommonBuild assembleHap --hot-reload-build --watch`, **staying connected** so the daemon's watch worker (rollup watch) stays alive for `--hotreload-apply` to reuse. The process stays alive (onBuildOutput streams to its stdout). **Must be stopped (kill the background process) when the hot-reload debug session ends** — otherwise the watch worker/daemon leaks. `--hotreload stop` additionally stops the hvigor daemon.
  - **Usage**: start `devecocli run --module <m> --hotreload` as a background process; wait for the `.hotreload-mode` marker (or "watch session active" on its stdout) = ready; then run `devecocli run --module <m> --hotreload-apply <file>` (foreground). When done: kill the background process + `devecocli run --hotreload stop`.
- `--hotreload-apply <fileName>`: **Hot reload without app restart** — reads the changed-file list from `.hvigor/<fileName>` (same format/merge rules as `--apply`), opens a **short socket** to the daemon (kept alive by the background `--hotreload` process) and sends `CommonBuild assembleDevHqf --hot-compile` → the watch worker incrementally hot-compiles changed `.ets`/`.ts` into abc (HotReloadArkTS; output/errors streamed live via WatchLog), then **manually** packs + signs a hqf from that abc (`app_packing_tool.jar` + `hap-sign-tool.jar`, DevEco material password decrypted via `DecipherUtil`), and installs it via `bm quickfix -a -f -o`. The app is **not restarted** — changes take effect immediately.
  - **Prereq**: the background `devecocli run --hotreload` process must be running (holds the watch session). If `--hotreload-apply` times out, the watch session isn't alive — (re)start the background `--hotreload`.
  - **Scope (important)**: hot reload targets a **single module** (`--module` required; the target can be entry/hsp/feature; `har` deps are folded in and fine). **`har` dependency changes are auto-routed** to the dependent main module's (entry/feature/hsp) `hotReload/changedFileList.json` — so editing a har's `.ets` and listing it hot-reloads via the target module. Changes in **`feature`/`hsp` dependency modules** (not the target) are NOT hot-reloadable — they're detected and warned (run a full `devecocli run` to redeploy those). `@State`/state-decorator changes are **not** hot-reloadable (state isn't re-initialized); hot-reloadable changes are non-state code: UI property values (`.fontColor`/`.fontSize`), `Text`/`Button` literal labels, method bodies, expressions. Resources/native changes need a full run.
  - **Compile errors**: ArkTS compile errors from the hot compile are routed (via WatchLog) to the **background `--hotreload` process**, which writes them to **`.hvigor/hotreload-watch.log`** (and its stdout). On failure, `--hotreload-apply` reads that file and prints the errors inline (fast-fail, ~15s timeout if the watch session is dead).
  - **Artifacts under `.hvigor/`** (shared with `--apply`): `.hvigor/<fileName>` = the changed-file list you write; `.hvigor/hotreload-watch.log` = the watch session's onBuildOutput/compile-errors (written by the background `--hotreload` process; safe to read/delete). The hot-reload marker is `<module>/build/<product>/.hotreload-mode`.
*Ex*: background `devecocli run --module entry --hotreload` → (ready) → edit `.fontColor` in `entry/src/main/ets/pages/Index.ets` → write path to `.hvigor/changes.txt` → `devecocli run --module entry --hotreload-apply changes.txt` (UI updates without restart). When done: kill the background process + `devecocli run --hotreload stop`.

### `devecocli signature generate` `[Outside sandbox]`
Auto-generate HarmonyOS signing materials (local p12/csr + cloud cert + test profile) and write signing config to `build-profile.json5`.
- **Prereq**: `devecocli auth login` first; run from a project directory (with `build-profile.json5`); a connected device or emulator is required for device registration.
- `--product <name>`: Product name for local p12/csr file naming (default: `default`).
- `--team-id <id>`: Specify the team-id (default: current user's id).
- `--force`: Force regenerate even if existing materials are valid.
- Generates under `~/.ohos/config/`: `.p12` keystore, `.csr`, downloaded `.cer` certificate, `.p7b` profile.
- Writes `signingConfigs` + `products` entries to `build-profile.json5` with encrypted key/store passwords (AES-128-GCM).
- Cloud cert name: `auto_debug_<teamId>.cer`. Local files: `<product>_<project>_<hash>=.{p12,csr,cer,p7b}`.
- Error handling (aligned with DevEco Studio JAR): 401→re-login, 403→no AGC permission, `205389872`→cert limit, `205389904`→not Harmony user, `205389938`→provision limit, invalid `.cer`→retry.
*Ex*: `devecocli signature generate --product default`


### `devecocli log`
Fetch hilog or crash logs. Req `--device <name|serial>` on multi-device hosts.
- `--crash`: Dump crash logs.
- `--level D|I|W|E|F`: Filter by level.
- `--bundle-name` / `--keyword`: Filter output.
- `--from <start>` / `--to <end>`: Relative offsets (`30s`, `5m`).
- `--tail <num>` / `--follow`: Keep last N lines / stream real-time (no `--to`).
*Ex*: `devecocli log --crash --bundle-name com.example.app`, `devecocli log --level E --from 5m --tail 200`

### `devecocli ui`
Inspect UI on a connected device. All subcommands accept `--device <name|serial>` (Req on multi-device hosts).

| Subcommand | Description | Key Options |
|---|---|---|
| `layout` | Dump ArkUI accessibility layout tree — **visible area only** (on-screen nodes) | `--id <id>`, `--window <windowId>`, `--all-windows`, `--depth <n>` (0=unlimited, 1=root only, 2=root+children), `--format default\|json`, `--mode full\|simplified` |
| `window list` | List active windows | `--format default\|json`, `--all` (include system windows) |
| `screenshot` | Capture a screenshot of the device screen | `--display <displayId>`, required `--path <path>` (existing directory or PNG file path; relative paths supported; writable destination; no overwrite) |
| `click [x] [y]` | Tap at the specified coordinates or node | `--id <id>` (auto-resolves to center), `--window <windowId>` (used with `--id`) |
| `doubleclick [x] [y]` | Double-tap at the specified coordinates or node | `--id <id>`, `--window <windowId>` |
| `longclick [x] [y]` | Long-press at the specified coordinates or node | `--id <id>`, `--window <windowId>` |
| `swipe <x1> <y1> <x2> <y2>` | Swipe from one point to another (precise coordinates, custom speed) | `--speed <n>` (200–40000, px/s) |
| `fling <x1> <y1> <x2> <y2>` | Fling from one point to another | `--speed <n>` (200–40000, px/s) |
| `drag <x1> <y1> <x2> <y2>` | Drag from one point to another | `--speed <n>` (200–40000, px/s) |
| `dircfling <direction>` | Quick directional fling (system default speed, ideal for scrolling) | `direction`: `up`, `down`, `left`, `right` |
| `text <text> [x] [y]` | Input text at a target location or the currently focused field | `--id <id>` (auto-resolves to center), `--window <windowId>` (used with `--id`) |

- **Coordinates vs `--id`**: Mutually exclusive. Provide either `x y` or `--id <id>`. For `text`, if neither is given, text goes to the currently focused field.
- **`--window`**: May only be used together with `--id`. Default is focused window. Secondary display operations via `--id` + `--window` are not supported.
- **`swipe` vs `dircfling`**: `swipe` requires exact start/end coordinates and supports `--speed`; `dircfling` only needs a direction (`up/down/left/right`) and uses system default speed (ideal for page/list scrolling).
- **Text encoding**: Special characters in `text` are Base64-encoded internally to safely pass through device shell.
- `--format json` pairs well with `jq`.
- `--mode full`: full layout tree, no filtering.
- `--mode simplified` (default): folds meaningless wrapper containers (non-root, no `id`, no text, not interactive) by lifting their surviving children up. `--depth` truncates after folding.


## 2. Setup

### `devecocli init`
MUTUALLY EXCLUSIVE modes for setup:
1. `--skill` (Default): Install `deveco-cli` skill to AI agents.
2. `--mcp`: Configure `deveco-mcp` server (ArkTS/C++ syntax checking).
*Options*:
- `--agent <agents>`: Comma-separated (e.g. `opencode,cursor`). Omitting targets all.
- `--project <path>`: Project-level config (Abs path for MCP).
- `--path <path>`: Direct skill install path.
- `-f, --force`: Overwrite existing config.
*MCP Rules*: Global MCP (no `--project`) only supports `opencode` and `cursor`. Others require `--project`.

### `devecocli auth login`
Sign in to your Huawei Developer account. Opens a browser for OAuth authentication. Required before `signature generate`.
*Ex*: `devecocli auth login`

### `devecocli auth logout`
Sign out and clear locally stored credentials.

### `devecocli auth status`
Show the current logged-in user.

### `devecocli auth team list`
List team accounts the current user has joined.

### `devecocli skills`
Manage HarmonyOS skills in AI agents/projects.
- `list [-l|--long]` / `find <keyword>`: List or search skills.
- `add (--all | --skill <name>) [--agent <a,b…>] [--project <path>] [--path <path>] [-f]`: Install.
- `remove --skill <name> [...]`: Uninstall.

### `devecocli check compat` `[Outside sandbox]`
Scan source code for breaking API changes between two SDK versions. Built on top of DevEco Studio's `arkanalyzer-apiscan` plugin.
- `versions`: List available target SDK versions. Opts: `--format <default|json>` (default: `default`).
- Default (no args): project-level scan.
- `--modules <m1> [m2...]`: Module-level scan.
- `<file1> [file2...]`: File-level scan (`.ets`/`.c`/`.cpp` only).
- `--source-version <v>` (Req) / `--target-version <v>` (Req): SDK version pair. Run `devecocli check compat versions` first; on zsh, **quote the value** (e.g. `"<source_version>"`, `"<target_version>"`).
- `--format <default|csv|json>` (default: `default`): Console output accepts `default` (text) or `json`; file output (via `--output-path`) accepts `default` (csv), `csv`, or `json`. `csv` requires `--output-path`.
- `--output-path <path>`: Directory (writes `apiChange-*.csv`/`apiChange-*.json`) or explicit file (extension must match `--format`).
- `--limit <n>` (default `100`): Max records shown on console when no `--output-path`.

Validation order: `files` + `--modules` mutually exclusive → `--source-version`/`--target-version` required → `csv` requires `--output-path` → project dir valid → modules exist → files exist + extension valid → versions in catalog + `target > source` → format/extension match → output target writable.

*Ex*: `devecocli check compat --source-version "<source_version>" --target-version "<target_version>" --output-path ./report`

## 3. Maintenance

- **`devecocli update`** `[Outside sandbox]`: Update CLI to latest version.
- **`devecocli serve mcp`**: Host stdio MCP server (`check` tool for `.ets`/C/C++). Used via `init --mcp`. (Env: `PROJECT_PATH`, `DEVECO_PATH`, `NODE_MAX_OLD_SPACE_SIZE`, `DEBUG=1`).

## Recipes

- **Fresh checkout to emulator**:
  `devecocli build` -> `devecocli emulator list` -> `devecocli emulator start "Name"` -> `devecocli run`
- **Diagnose crash**:
  `devecocli log --crash --bundle-name <bundle>`
- **Release build**:
  `devecocli build --product oversea --build-mode release`
- **First-time signing setup**:
  `devecocli auth login` -> `devecocli signature generate --product default` -> `devecocli build` -> `devecocli run`

## Troubleshooting

- **"Product / Build mode `<x>` not found"**: Check `build-profile.json5`.
- **"Multiple entry modules" / "No entry module"**: Pass `--modules` (build) or `--module` (run).
- **"No active devices" / "Multiple devices connected"**: Connect/start emulator. Pass `-t <serial>` (device view) or `--device <name|serial>` (run/log).
- **`error:install sign info inconsistent`**: Signing key changed. Run `devecocli run --uninstall` or `devecocli signature generate --force`.
- **`Not logged in. Run devecocli auth login first`**: Run `devecocli auth login` to authenticate.
- **`Provision number exceeds limit`**: Test provision quota is full. Delete old test provisions in DevEco Studio (Signing Configs) or AGC console, then retry `devecocli signature generate`.
- **`Invalid AccessToken. Sign in and try again`**: Token expired. Run `devecocli auth login` again.
- **`skills add` agent not found**: Valid: `codebuddy`, `cursor`, `opencode`, `qoder`, `trae-cn`.
- **`emulator start` / `image download` blocked on agreement**: User MUST accept agreements. Interactive: `devecocli emulator license` (requires TTY). Non-interactive (CI/scripts): `devecocli emulator license accept`. Agents cannot run the interactive form; suggest the user run it, or use `license accept` if a non-TTY flow is acceptable. Do not retry until accepted.
- **`image download` failure / timeout**: Do NOT auto-retry. Give the command to the user to run manually in their terminal.
- **`emulator create` timeout**: Treat as user-action step. Ask user to open DevEco Studio -> Device Manager. Check `emulator list` after user confirms. Do NOT auto-retry or edit SDK files.
- **`image list` duplicate OS rows**: `phone`/`foldable`/`widefold`/`triplefold` share the same image. Download/remove ONCE per OS version.
**`ui layout` missing expected node**: `layout` only returns on-screen nodes. The user must scroll the target into view on the device before retrying (no CLI input subcommands in this build).
