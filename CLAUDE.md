# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KeePassHO — HarmonyOS (ArkTS) password manager, fully compatible with the KeePass database format (.kdbx), AES-256 / ChaCha20 / Argon2. The `kdbxweb` module is a port of [keeweb/kdbxweb](https://github.com/keeweb/kdbxweb). `AGENTS.md` has overlapping contributor guidance; this file focuses on architecture and commands.

> **文档状态：** 2026-09-08 全面更新。新增内容：EntryAbility 聚合架构、全局 Navigation 分栏导航重构、20+新增组件、OAuth2 框架、导入导出 (import/export) 子系统、OTP/TOTP 解析兼容层、条目模板系统、华为云盘/pCloud/百度网盘存储后端、跨设备同步、崩溃日志收集、SM4加密、扫码服务、分享工具、网络图片下载、WebDavClient 等。

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

Two hvigor modules: **`entry`** (the app) and **`kdbxweb`** (the KeePass library, consumed as `'kdbxweb'`). App entry point: `entryability/EntryAbility.ets` — a `UIAbility` that orchestrates core service initialization (theme, resource manager, recent files, settings, SM4 encryption, distributed sync, crash logging) during `onCreate`/`onWindowStageCreate`. `main_pages.json` registers only `pages/AppNavigation` as the root page.

### State management
Three cooperating mechanisms, all global singletons — do not introduce ad-hoc global state:
- **`AppStorage`** (ArkUI built-in) for UI-reactive scalar state via `@StorageLink`/`@StorageProp` (e.g. `isLocked`, `navBarWidth`, theme keys, `context`).
- **`SettingsService`** (`services/SettingsService.ets`) — singleton (`getInstance()`, eagerly instantiated) backed by `@ohos.data.preferences`. All persisted user settings are `public static readonly KEY_*` string constants with paired `*_DEFAULT` values. Follow this pattern for new settings. Notable settings: theme mode, sort mode, security auto-lock/clear-pasteboard/auth-type, TOTP display, support dialog, database extension filter, cross-device sync toggle (`KEY_APP_SYNC_SETTING_ENABLE`), local cache toggle (`KEY_APP_ENABLE_LOCAL_CACHE`), breadcrumb visibility (`KEY_APP_BREADCRUMB_VISIBLE`), smart grip posture (`KEY_APP_HOLDING_HAND_ENABLE`).
- **`EventBus`** (`services/EventBus.ets`) — thin wrapper over `@kit.BasicServicesKit` `emitter` for decoupled cross-component signaling. Named events are `static readonly` string constants (`DATABASE_RELOAD`, `DATABASE_UPDATE`, `KV_DATA_CHANGE`, `lock_screen`, `unlock_screen`, `KV_SYNC_COMPLETE`, …). Subscribe in `aboutToAppear`, **always** `EventBus.off` in `aboutToDisappear` to avoid leaks. Use string constants, never inline literals.

### Navigation & split layout
`pages/AppNavigation.ets` is the `@Entry` root (`@Entry @Component struct AppNavigation`). It stacks multiple `Navigation` containers (Index, DatabaseView, TotpView, Settings) and toggles `Visibility` per the current root page. **`NavigationManager`** (singleton, `common/utils/NavigationManager`) owns the named `NavPathStack`s (`getOrCreateNavPathStack('DatabaseView')`) and tracks stack-vs-split mode + root-page changes via listener callbacks. **`PageConfigManager`** (`common/utils/PageConfigManager`) configures each page's navigation mode and max-width constraints. Navigation mode types are `NavigationModeType.EXCLUSIVE` (single-column, max-width constrained — for Index/home pages) and `NavigationModeType.SPLIT` (split Auto mode — for DatabaseView/Settings/TotpView). **`PageContainer`** (`components/PageContainer.ets`) is a reusable wrapper that applies per-page constraints based on `PageConfig`. See `docs/2026-07-09-global-navigation-refactor.md` and `docs/HarmonyOS分栏布局开发指南.md` before touching navigation.

### EntryAbility — 聚合初始化
`EntryAbility` (`entryability/EntryAbility.ets`) follows this lifecycle:
1. `onCreate`: stores context in `AppStorage`, calls `init()`.
2. `init`: sets EL4 storage area, initializes `CommonUtils`, `ThemeManager`, `ResourceManager`, then fires `preloadEssentialServices()`.
3. `preloadEssentialServices`: loads `RecentFilesService`, `SettingsService` (theme, sync), preloads most recent file info into `AppStorage` (`preloadRecentFile` / `preloadReady` keys), then schedules `initNonEssentialServices()` via `setTimeout`.
4. `initNonEssentialServices`: `Sm4Utils.init()`, `SyncSettingsService.initSync()`, `CrashLogService.init()`, `DialogHelper` config.
5. `onWindowStageCreate`: initializes `LockScreenService`, loads `pages/AppNavigation` (or opens a DB via URL).
6. Foreground/Background: auto-lock screen after configurable timeout via `LockScreenService.showLockWindow()`.
7. `onNewWant`: handles URI-based database opening requests (KFDL file association).

### KDBX load/save on Worker threads
Crypto and DB parsing run off the UI thread. Pattern in `workers/`:
- **`DatabaseLoad` / `DatabaseSave`** (`workers/DatabaseLoad.ets`, `DatabaseSave.ets`) are plain classes holding the actual logic (credential creation → `KdbxFileManager.read` → `Kdbx.load`, and the save inverse). They post progress/success/error through overridable `postMessage`/`postSuccessMessage`/`postErrorMessage` hooks.
- **`DatabaseLoadWorker` / `DatabaseSaveWorker`** extend them and override the post methods to bridge to the main thread via `workerPort.postMessage`. Success messages transfer the `ArrayBuffer` (KDBX bytes) with the transferable-list overload to avoid a copy.
- Communication is JSON-serialized `WorkerMessage` (`workers/WorkerParam.ets`) typed by `MessageType`. Params live in `DatabaseLoadWorkerParam.ets` / `DatabaseSaveWorkerParam.ets`.
- **Never** hold plaintext master passwords / secret material on the main thread longer than needed; keep that work in the worker.

### Storage backends (factory + decorator)
`storage/FileStorageFactory.ets` is a singleton registry mapping `StorageType` → `IFileStorage`. All exports unified through `storage/index.ets`.

Implemented backends:
| StorageType | Class | Status |
|---|---|---|
| `LOCAL` | `LocalFileStorage` | Registered |
| `WEBDAV` | `WebDAVStorage` | Registered |
| `S3` | `S3Storage` | Registered |
| `ONEDRIVE` | `OneDriveStorage` | Registered |
| `FTP` | `FTPStorage` | Registered |
| `HUAWEI_DRIVE` | `HuaweiDriveStorage` | Registered |
| `PCLOUD` | `PCloudStorage` | Enum+impl done, factory line commented |
| `BAIDU_NETDISK` | — | Enum defined, not yet implemented |

`getStorage()` wraps every non-LOCAL backend in **`CacheStorage`** (decorator) before returning. `KdbxFileManager` (`services/kdbx/`) is the app-level façade. Each backend has a parallel directory structure:
- `*Page.ets` — config/connect UI page
- `*Config.ets` — config data class
- `*Storage.ets` — IFileStorage implementation
- OAuth2 backends (OneDrive, Huawei Drive, pCloud, Google Drive) also have `*OAuth2Provider.ets` + `*Client.ets`

New backends: implement `IFileStorage`, register in the factory constructor, add the `StorageType` enum value. `services/kdbx/` (`KdbxFileManager`, `KdbxLoadService`, `KdbxSaveService`) is the boundary between app code and storage; `services/importExport/` handles CSV/XML/Bitwarden/KDBX import-export via a handler registry. See `docs/research/baidu-netdisk-api.md` for the Baidu Netdisk API research.

### kdbxweb library (`kdbxweb/src/main/ets/`)
Public API is re-exported from `index.ts`. Layout: `crypto/` (ChaCha20, Salsa20, AES key-encryptor, Argon2 via `crypto-engine`, `ProtectedValue` for in-memory secret masking, hashed/hmac block transforms), `format/` (`Kdbx`, `KdbxEntry`, `KdbxGroup`, `KdbxHeader`, `KdbxMeta`, credentials, UUID, field references, merge), `defs/` (consts, xml-names), `errors/` (`KdbxError`), `utils/` (`BinaryStream`, `ByteUtils`, `Int64`, `VarDictionary`, `XmlUtils`). Argon2 uses `@ohos-rs/argon2`. Treat this module as a library port — match existing keeweb conventions when extending.

## Conventions

- **Language**: ArkTS (TypeScript superset) with HarmonyOS decorators (`@State`, `@StorageLink`, `@Entry`, `@Component`). 2-space indent; PascalCase components/classes, camelCase methods/vars, UPPER_CASE constants.
- **Singletons**: `getInstance()` pattern (`SettingsService`, `FileStorageFactory`, `NavigationManager`, …).
- **Commit messages**: Conventional Commits, `<type>: <description>` (Chinese or English). Types in history: `feat`, `fix`, `refactor`, `docs`, `security`, `test`, `chore`.
- **Resources**: user-facing strings come from `entry/src/main/resources/base/element/string.json` via `$r('app.string.*')`; resource-manager helpers in `common/utils/ResourceManager`.
- Logging via `@kit.PerformanceAnalysisKit` `hilog` with a `0x0000` domain and a per-file `TAG`; use `%{public}s`/`%{private}s` formatting (do not log secrets).

## Services Overview (entry/src/main/ets/services/)

| Service | File | Description |
|---|---|---|
| `SettingsService` | `SettingsService.ets` | Singleton, backed by `@ohos.data.preferences`. Persisted user settings, theme, sort mode, security options, sync toggle, cache, breadcrumb, smart grip. Observer pattern for change notification. |
| `EventBus` | `EventBus.ets` | Thin wrapper over `@kit.BasicServicesKit` `emitter`. Decoupled cross-component signaling. |
| `FileService` | `FileService.ets` | Manages currently opened database file params (path, credentials, Kdbx instance). |
| `DataService` | `DataService.ets` | KDBX save, export (KDBX/XML/CSV), file content management. |
| `AuthService` | `AuthService.ets` | Biometric auth (fingerprint + face using `@kit.UserAuthenticationKit`) and master password verification. |
| `CredentialsService` | `CredentialsService.ets` | Creates `KdbxCredentials` from password + keyfile (password-only, keyfile-only, or combined). |
| `LockScreenService` | `LockScreenService.ets` | Manages lock/unlock lifecycle. Communicates via EventBus. Used by EntryAbility foreground/background auto-lock. |
| `CrashLogService` | `CrashLogService.ets` | Listens to `hiAppEvent` crash events, writes logs to EL1 storage, manages log rotation (max 5 files). |
| `ScanService` | `ScanService.ets` | QR code scanning via `@kit.ScanKit`. Used for TOTP setup. |
| `TotpService` | `TotpService.ets` | TOTP generation (RFC6238/Steam/Custom). SHA1/SHA256/SHA512. Auto-refresh timer. |
| `RecentFilesService` | `RecentFilesService.ets` | Manages recently opened database files list, preloads most recent file for cold-start optimization. |
| `SupportService` | `SupportService.ets` | In-app support/donation dialog management, tracks install time and show frequency. |
| `TemplateService` | `template/TemplateService.ets` | Entry template system: preset (20+ types) + user-defined strategies. |
| `KdbxFileManager` | `kdbx/KdbxFileManager.ets` | Facade: read/write/getInfo/listDir/exists over IFileStorage. |
| `KdbxLoadService` | `kdbx/KdbxLoadService.ets` | KDBX load orchestration from storage. |
| `KdbxSaveService` | `kdbx/KdbxSaveService.ets` | KDBX save orchestration to storage (with callback). |
| `ImportExportFacade` | `importExport/ImportExportFacade.ets` | Unified import/export entry point. |
| `DistributedKVService` | `store/DistributedKVService.ets` | Cross-device distributed KV store (`@kit.ArkData`). |
| `SyncSettingsService` | `store/SyncSettingsService.ets` | Settings + recent files sync across devices via DistributedKVService. |

### OTP/TOTP 兼容层 (`services/otp/`)
`OtpCompatibilityManager` (singleton) aggregates multiple parsers to extract OTP URLs from KeePass entries. Supports formats: `otpauth://totp/` URL, KeeOTP custom fields, KeeTrayTOTP custom fields, KeePass2 TOTP fields. Parsers: `OtpUrlParser`, `KeeOtpParser`, `KeeTrayTotpParser`, `KeePass2Parser`. Unified through `services/otp/index.ets`.

### 导入导出 (`services/importExport/`)
`FormatHandlerRegistry` (singleton) maps formats to `IImportHandler`/`IExportHandler`. `ImportExportViewModel` drives the companion UI. Supported formats:
- **Import**: CSV, XML, Bitwarden JSON
- **Export**: CSV, XML, KDBX, KeyFile
Register all default handlers via `registerDefaultHandlers()` from `importExport/index.ets`.

### 条目模板系统 (`services/template/`)
20+ preset templates across 6 categories: General, Identity, Finance, Network, Development, Other. `TemplateFactory` + `TemplateBuilder` create `KdbxEntry` instances from templates. `UserTemplateStrategy` / `PresetTemplateStrategy` implement `ITemplateStrategy`. Template constants define field keys, protected fields, placeholders, icons.

## Components Overview (entry/src/main/ets/components/)

| Component | Description |
|---|---|
| `PageContainer.ets` | Reusable wrapper that applies per-page max-width/padding constraints from `PageConfig` |
| `EntryViewFieldItem.ets` | Field item in entry detail view |
| `OpenMethodButton.ets` | Open method selection button |
| `ImageAddComponent.ets` | Image picker component for custom icons |
| `TotpPreviewComponent.ets` | TOTP token display with countdown timer |
| `ColorPickerDialog.ets` | Color picker (14 preset colors) for entry/group foreground/background |
| `TemplateSelectorDialog.ets` | Template selection dialog for new entry creation |
| `PasswordGeneratorDialog.ets` | Password generator dialog |
| `IconSelectorDialog.ets` | Icon selection dialog |
| `AddGroupDialog.ets` | Add/rename group dialog |
| `EntryEditFieldDialog.ets` | Edit custom field in entry |
| `DownloadImageDialog.ets` | Download web image dialog |
| `ImageViewerDialog.ets` | Image viewer dialog |
| `ContextLoadingDialog.ets` | Context-aware loading overlay |
| `SettingDialogWrapper.ets` | Settings dialog helper |
| `TotpConfigDialog.ets` | TOTP configuration dialog |
| `loading/LoadingViews.ets` | Shared loading view components |
| `loading/LoadingDialogUtils.ets` | Loading dialog utility |
| `loading/LoadingDialogGlobalSettings.ets` | Global loading dialog config |
| `loading/LoadingSettings.ets` | Loading settings component |
| `loading/PromptActionUtils.ets` | Prompt action utility |

## Utility Modules (entry/src/main/ets/common/utils/)

| Utils | Description |
|---|---|
| `CommonUtils.ets` | App-wide utilities (init, toast, UI context etc.) |
| `AssetUtils.ets` | HarmonyOS `@kit.AssetStoreKit` key asset query/add/delete |
| `ClipboardUtils.ets` | Clipboard read/write with auto-clear timer |
| `CryptoUtils.ets` | Crypto helper (PKCS7 padding, AES-CBC encrypt/decrypt, random hex) |
| `DateUtils.ets` | Date formatting helpers |
| `DeviceUtils.ets` | Device info utilities |
| `DialogWindowHelper.ets` | Dialog window size change listener |
| `ErrorUtils.ets` | Predefined BusinessError constants |
| `FileUtils.ets` | File system operations (read/write/mkdir/list etc.) |
| `FilenameUtils.ets` | File name/path parsing utilities |
| `IconUtils.ets` | Icon resource mapping for Kdbx standard icons |
| `ImagePickerUtils.ets` | Photo picker integration |
| `KdbxUtils.ets` | KDBX data operations: search, sort, get/set fields, custom icons, TOTP extraction, pin/favorite tags, save, group path, indexer |
| `NavigationManager.ets` | Navigation stack manager singleton |
| `PageConfigManager.ets` | Per-page navigation/max-width config manager |
| `ResourceManager.ets` | `@ohos.resourceManager` wrapper for string/plural/color/number resources |
| `ResourceUtils.ets` | Resource value retrieval utilities |
| `ShareUtils.ets` | System share panel (file/text/link) via `@kit.ShareKit` |
| `Sm4Utils.ets` | SM4 encryption via `@hw-agconnect/petal-aegis`, key stored in Asset Kit |
| `StringUtils.ets` | String utilities (pinyin sorting, first letter extraction) |
| `ThemeManager.ets` | Theme mode management (LIGHT/DARK/SYSTEM) |
| `UIUtils.ets` | Content width calculation, dialog width adaptation |
| `UrlUtils.ets` | URL validation, favicon URL construction |
| `WebDavClient.ets` | WebDAV protocol client over `@kit.RemoteCommunicationKit` rcp |
| `WebImageDownloader.ets` | Download images from URL via rcp, convert to base64 |
| `WindowUtils.ets` | Window state management (maximize/fullscreen/center) |

### OAuth2 框架 (`common/oauth2/`)
Base classes for OAuth2 authentication flows: `IOAuth2Provider` interface, `BaseOAuth2Provider` (abstract, implements authorization URL, token exchange, refresh), `OAuth2TokenStorageService` (persist tokens encrypted to preferences). Used by: OneDrive, Huawei Drive, pCloud, Google Drive providers. Unified through `common/oauth2/index.ets`.

### Constants (`common/constants/`)
All constants exported through `common/constants/index.ets`:
- `Constants.ets` — app-level constants (async save/load flags, AppStorage keys)
- `NavigationConstants.ets` — nav bar width/range, split threshold, root page list
- `PageConstants.ets` — page name strings, layout widths/paddings per page group
- `PageConfig.ets` — `NavigationModeType` enum + `PageConfig` interface
- `SortConstants.ets` — `SortMode` enum
- `ThemeConstants.ets` — `ThemeMode` enum
- `UIConstants.ets` — UI sizing (width thresholds, corner radii, icon sizes, shadows, paddings, heights)
- `SettingDialogConstants.ets` — setting dialog configs

### Pages (entry/src/main/ets/pages/)

| Page | Description |
|---|---|
| `AppNavigation.ets` | **@Entry** root — multi-Navigation container, root-page switching |
| `Index.ets` | Home page — recent files, open/create database |
| `Password.ets` | Database unlock/password entry |
| `DatabaseView.ets` | Main database view — group tree + entry list |
| `EntryView.ets` | Entry detail view — fields, TOTP, attachments, history |
| `EntryEdit.ets` | Entry edit form |
| `TotpView.ets` | TOTP token dashboard |
| `UnLockDatabase.ets` | Lock screen overlay with re-auth |
| `RecentFiles.ets` | Recently opened files list |
| `SelectLocation.ets` | Select storage location to open |
| `CreateDatabase.ets` | Create new database wizard |
| `ChangePassword.ets` | Change master password |
| `OAuth2Login.ets` | OAuth2 login WebView |
| `TemplateEntryCreate.ets` | Create entry from template |
| `FileList.ets` | Remote file browser |
| `setting/Settings.ets` | Main settings page (split layout) |
| `setting/SettingApplication.ets` | App settings sub-page |
| `setting/SettingDatabase.ets` | Database-specific settings |
| `setting/SettingDatabaseKeyFunction.ets` | Key function settings |
| `setting/SettingDatabaseMeta.ets` | Database metadata settings |
| `setting/SettingDatabaseProtectedFiled.ets` | Protected field config |
| `setting/SettingSecurity.ets` | Security settings |
| `setting/SettingCustomIcons.ets` | Custom icon management |
| `about/About.ets` | About page |
| `about/Support.ets` | Support page |

## Key Dependencies

Local & third-party:
- `kdbxweb` — local library module (KeePass format)
- `@ohos-rs/argon2` — Argon2 KDF (used by kdbxweb)
- `@ohos/flate2` — GZip compression (used by kdbxweb)
- `@ohos/axios` — HTTP client
- `@pura/harmony-dialog` — Dialog component library
- `@xmldom/xmldom` — XML parser (used by kdbxweb)
- `@hw-agconnect/petal-aegis` — SM4 encryption (Sm4Utils)
- `@kit.UserAuthenticationKit` — Biometric auth (AuthService)
- `@kit.ScanKit` — QR code scanning (ScanService)
- `@kit.ShareKit` — System share panel (ShareUtils)
- `@kit.AssetStoreKit` — Key asset storage (AssetUtils, Sm4Utils)
- `@kit.RemoteCommunicationKit` — rcp HTTP client (WebDavClient, WebImageDownloader)
- `@kit.DistributedServiceKit` — Device discovery for cross-device sync
- `@kit.ArkData` — Distributed KV store (DistributedKVService)
