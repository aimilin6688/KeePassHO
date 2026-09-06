# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KeePassHO — HarmonyOS (ArkTS) password manager, fully compatible with the KeePass database format (.kdbx), AES-256 / ChaCha20 / Argon2. The `kdbxweb` module is a port of [keeweb/kdbxweb](https://github.com/keeweb/kdbxweb). `AGENTS.md` has overlapping contributor guidance; this file focuses on architecture and commands.

## Build & Deploy

All builds use the **hvigorw** CLI from the HarmonyOS command-line-tools (DevEco). On macOS the binary is at `<command-line-tools>/bin/hvigorw`; on Windows `hvigorw.bat`. `hdc` is the device tool under `<command-line-tools>/sdk/default/openharmony/toolchains/hdc`. The HAP is always `entry/build/<product>/outputs/default/entry-default-signed.hap`.

**macOS (current machine — product `mac_debug`):**
```bash
hvigor="D:/Software/HarmonyOS/command-line-tools/bin/hvigorw.bat"   # Windows
hvigor="/Users/liujunguang1/workspace/software/command-line-tools/bin/hvigorw"  # macOS
hdc="/Users/liujunguang1/workspace/software/command-line-tools/sdk/default/openharmony/toolchains/hdc"
hap="entry/build/mac_debug/outputs/default/entry-default-signed.hap"

"$hvigor" --mode module -p product=mac_debug -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
"$hdc" install -r "$hap"
"$hdc" shell aa start -a EntryAbility -b com.aimilin.keepassho
```

**Windows (product `default`):** swap product to `default`, hap path to `entry/build/default/outputs/default/entry-default-signed.hap`, and use the Windows tool paths shown in the project instructions.

Signing products (`default`→`win_debug`, `win_release`, `mac_debug`, `mac_release`) and their signing configs are defined in `build-profile.json5`. The package name / bundle is `com.aimilin.keepassho`; entry ability is `EntryAbility`.

## Tests

Framework: **Hypium** (`@ohos/hypium`) with **Hamock** (`@ohos/hamock`) for mocking. Tests run **on-device/emulator** via `hdc shell aa test`, not as node scripts. Test source mirrors production under `src/ohosTest/ets/test/`; the suite entry is `List.test.ets`, which imports and calls every `*.test.ets` suite. There is no off-device runner — a connected device/emulator (`hdc list targets`) is required.

**Build the ohosTest HAP** (macOS):
```bash
hvigorw --mode module -p module=entry@ohosTest -p isOhosTest=true -p product=mac_debug -p buildMode=test assembleHap --analyze=normal --parallel --incremental --daemon
```
Install it: `hdc install -r entry/build/mac_debug/outputs/ohosTest/entry-ohosTest-signed.hap`

**Run all tests:**
```bash
hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000
```

**Run a single test class** (note `-s class <SuiteName>` — the name is the default-exported function's name, e.g. `CacheStorageTest`, `S3StorageTest`, `TotpServiceTest`):
```bash
hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class CacheStorageTest -s timeout 60000
```
For an isolated kdbxweb-library run, build/install the `kdbxweb` ohosTest target the same way (`-p module=kdbxweb@ohosTest`) and its `List.test.ets` aggregates crypto/format/utils suites.

## Lint

`code-linter.json5` enforces `@performance/recommended` + `@typescript-eslint/recommended`, plus security rules (`@security/no-unsafe-aes`, `@security/no-unsafe-hash`, `@security/no-unsafe-rsa-*`, `@security/no-unsafe-3des`, …) as errors. Tests/build dirs are ignored. Lint runs inside DevEco Studio; do not weaken security rules without justification.

## Architecture

Two hvigor modules: **`entry`** (the app) and **`kdbxweb`** (the KeePass library, consumed as `'kdbxweb'`).

### State management
Three cooperating mechanisms, all global singletons — do not introduce ad-hoc global state:
- **`AppStorage`** (ArkUI built-in) for UI-reactive scalar state via `@StorageLink`/`@StorageProp` (e.g. `isLocked`, `navBarWidth`, theme keys).
- **`SettingsService`** (`services/SettingsService.ets`) — singleton (`getInstance()`, eagerly instantiated) backed by `@ohos.data.preferences`. All persisted user settings are `public static readonly KEY_*` string constants with paired `*_DEFAULT` values. Follow this pattern for new settings.
- **`EventBus`** (`services/EventBus.ets`) — thin wrapper over `@kit.BasicServicesKit` `emitter` for decoupled cross-component signaling. Named events are `static readonly` string constants (`DATABASE_RELOAD`, `DATABASE_UPDATE`, `KV_DATA_CHANGE`, `lock_screen`, `unlock_screen`, …). Subscribe in `aboutToAppear`, **always** `EventBus.off` in `aboutToDisappear` to avoid leaks. Use string constants, never inline literals.

### Navigation & split layout
`pages/AppNavigation.ets` is the `@Entry` root. It stacks multiple `Navigation` containers (Index, DatabaseView, TotpView, Settings) and toggles `Visibility` per the current root page. **`NavigationManager`** (singleton, `common/utils`) owns the named `NavPathStack`s (`getOrCreateNavPathStack('DatabaseView')`) and tracks stack-vs-split mode + root-page changes via listener callbacks. The split (分栏) mode is a first-class concern — see `docs/统一分栏导航改造方案-最终实施版.md` and `docs/HarmonyOS分栏布局开发指南.md` before touching navigation. Mode flips between `NavigationMode.Stack` and `NavigationMode.Auto` (split).

### KDBX load/save on Worker threads
Crypto and DB parsing run off the UI thread. Pattern in `workers/`:
- **`DatabaseLoad` / `DatabaseSave`** (`workers/DatabaseLoad.ets`, `DatabaseSave.ets`) are plain classes holding the actual logic (credential creation → `KdbxFileManager.read` → `Kdbx.load`, and the save inverse). They post progress/success/error through overridable `postMessage`/`postSuccessMessage`/`postErrorMessage` hooks.
- **`DatabaseLoadWorker` / `DatabaseSaveWorker`** extend them and override the post methods to bridge to the main thread via `workerPort.postMessage`. Success messages transfer the `ArrayBuffer` (KDBX bytes) with the transferable-list overload to avoid a copy.
- Communication is JSON-serialized `WorkerMessage` (`workers/WorkerParam.ets`) typed by `MessageType`. Params live in `DatabaseLoadWorkerParam.ets` / `DatabaseSaveWorkerParam.ets`.
- **Never** hold plaintext master passwords / secret material on the main thread longer than needed; keep that work in the worker.

### Storage backends (factory + decorator)
`storage/FileStorageFactory.ets` is a singleton registry mapping `StorageType` → `IFileStorage`. Implemented backends: `LOCAL`, `WEBDAV`, `S3`, `ONEDRIVE`, `FTP`, `HUAWEI_DRIVE` (plus `PCLOUD`, currently commented out). `getStorage()` wraps every non-LOCAL backend in **`CacheStorage`** (decorator) before returning. `KdbxFileManager` (`services/kdbx/`) is the app-level façade: it takes a `StorageType` + `StorageConfig`, delegates to the factory, and exposes `read`/`write`/`getInfo`/`listDir`/`exists` used by the workers. New backends: implement `IFileStorage`, register in the factory constructor, add the `StorageType` enum value. `services/kdbx/` (`KdbxFileManager`, `KdbxLoadService`, `KdbxSaveService`) is the boundary between app code and storage; `services/importExport/` handles CSV/XML/Bitwarden/KDBX import-export via a handler registry.

### kdbxweb library (`kdbxweb/src/main/ets/`)
Public API is re-exported from `index.ts`. Layout: `crypto/` (ChaCha20, Salsa20, AES key-encryptor, Argon2 via `crypto-engine`, `ProtectedValue` for in-memory secret masking, hashed/hmac block transforms), `format/` (`Kdbx`, `KdbxEntry`, `KdbxGroup`, `KdbxHeader`, `KdbxMeta`, credentials, UUID, field references, merge), `defs/` (consts, xml-names), `errors/` (`KdbxError`), `utils/` (`BinaryStream`, `ByteUtils`, `Int64`, `VarDictionary`, `XmlUtils`). Argon2 uses `@ohos-rs/argon2`. Treat this module as a library port — match existing keeweb conventions when extending.

## Conventions

- **Language**: ArkTS (TypeScript superset) with HarmonyOS decorators (`@State`, `@StorageLink`, `@Entry`, `@Component`). 2-space indent; PascalCase components/classes, camelCase methods/vars, UPPER_CASE constants.
- **Singletons**: `getInstance()` pattern (`SettingsService`, `FileStorageFactory`, `NavigationManager`, …).
- **Commit messages**: Conventional Commits, `<type>: <description>` (Chinese or English). Types in history: `feat`, `fix`, `refactor`, `docs`, `security`, `test`, `chore`.
- **Resources**: user-facing strings come from `entry/src/main/resources/base/element/string.json` via `$r('app.string.*')`; resource-manager helpers in `common/utils/ResourceManager`.
- Logging via `@kit.PerformanceAnalysisKit` `hilog` with a `0x0000` domain and a per-file `TAG`; use `%{public}s`/`%{private}s` formatting (do not log secrets).

## Key Dependencies

`kdbxweb` (local module), `@ohos-rs/argon2`, `@ohos/flate2`, `@ohos/axios`, `@pura/harmony-dialog`, `@xmldom/xmldom`.
