# Repository Guidelines

## Project Structure & Module Organization

This is a HarmonyOS password manager (KeePassHO) built with ArkTS, consisting of two hvigor modules:

- **entry/** — Main application module. Source code lives under `entry/src/main/ets/` with these subdirectories:
  - `entryability/` — `EntryAbility.ets` (UIAbility, service orchestration)
  - `pages/` — All UI pages (AppNavigation as @Entry root, Index, DatabaseView, Settings, etc.)
  - `components/` — Reusable UI components (PageContainer, dialogs, TotpPreview, etc.)
  - `services/` — Business logic services (SettingsService, EventBus, AuthService, TotpService, importExport, otp, template, kdbx, store)
  - `storage/` — IFileStorage implementations (Local, WebDAV, S3, OneDrive, FTP, Huawei Drive, pCloud)
  - `workers/` — Worker thread KDBX load/save
  - `common/` — Shared utilities & constants
    - `utils/` — 25+ utility classes (KdbxUtils, NavigationManager, ShareUtils, Sm4Utils, AssetUtils, etc.)
    - `constants/` — All constants (NavigationConstants, PageConstants, UIConstants, etc.)
    - `oauth2/` — OAuth2 authentication framework
  - Tests are in `src/ohosTest/ets/test/`.
- **kdbxweb/** — KeePass database format library (ported from keeweb/kdbxweb). `src/main/ets/` contains crypto, format, and utils modules. Tests in `src/ohosTest/`.
- **AppScope/** — Global app configuration and shared resources.
- **hvigor/** — Project-level build configuration.

## Build, Test, and Development Commands

All commands use `hvigorw` as the build orchestrator. Build products are signing-dependent (win_debug, mac_debug, default).

## Workflow Rule: Auto-Deploy After Each Task

After every task's `devecocli build` succeeds, ALWAYS automatically deploy the app to the connected phone and launch it via `devecocli run --skip-build` — do not ask, this is the default end-of-task step. Skip only when no device is connected or the user explicitly declines.

- `hvigorw assembleHap --no-daemon -p product=default` — Build debug HAP for Windows
- `hvigorw clean assembleHap --no-daemon -p product=default` — Clean build (removes cached artifacts)
- `hvigorw assembleHap --no-daemon -p product=mac_debug` — Build debug HAP for macOS

HAP output is placed at `entry/build/<product>/outputs/default/entry-<product>-signed.hap`.

Tests use Hypium (`@ohos/hypium`) and Hamock (`@ohos/hamock`). Run tests **on-device/emulator** via `hdc shell aa test`, not via `hvigorw test`.

## Coding Style and Naming Conventions

- ArkTS/TypeScript source files use `.ets` or `.ts` extensions.
- Linting is configured in `code-linter.json5` — applies `@typescript-eslint/recommended` and `@performance/recommended` rules.
- Lint checks integrate with DevEco Studio builds; can also be run via the built-in linter.
- Indentation uses 2 spaces (HarmonyOS/ArkTS convention).
- Security rules are enforced at error level for unsafe AES, hash, DH, DSA, ECDSA, RSA, and 3DES usage.
- Test files and mock directories (`src/ohosTest/`, `src/mock/`) are excluded from linting.
- PascalCase for components/classes, camelCase for methods/vars, UPPER_CASE for constants.

## Service Conventions

- Singletons use `getInstance()` pattern.
- Services that need ability context receive it via `init(context)` called from `EntryAbility`.
- Cross-component communication uses `EventBus` (emitter wrapper) — **always** `EventBus.off` in `aboutToDisappear`.
- Settings use `SettingsService.put()`/`get()`/`getSync()` with paired `KEY_*` + `*_DEFAULT` constants.

## Testing Guidelines

- Uses Hypium test framework with Hamock for mocking, running **on-device/emulator**.
- Test files mirror source structure under `src/ohosTest/ets/test/`.
- Suite entry is `List.test.ets` which imports all `*.test.ets` suites.
- Single test class run: `hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class <SuiteName> -s timeout 60000`.
- Test files excluded from linting ruleset — prefer explicit, descriptive test names mirroring source functions/components.

## Commit and Pull Request Guidelines

This project uses **Conventional Commits** with one of these prefixes:

- `feat:` — New feature
- `fix:` — Bug fix
- `refactor:` — Code change that neither fixes a bug nor adds a feature
- `docs:` — Documentation-only changes
- `chore:` — Maintenance, dependencies, tooling
- `security:` — Security-related fixes or hardening

PRs should include a clear description, link any related issue or discussion, and attach screenshots for UI changes. Keep scope focused — prefer small, single-purpose commits over large monolithic changes.

## Security and Configuration Tips

- `code-linter.json5` enforces strict cryptographic safety rules.
- Prefer HarmonyOS system APIs (`@ohos.security.*`) over custom implementations for crypto operations.
- **Never** bypass security linter rules without explicit team review.
- SM4 encryption (`Sm4Utils`) uses `@hw-agconnect/petal-aegis` with keys stored in HarmonyOS Asset Kit.
- OAuth2 tokens are persisted encrypted via `OAuth2TokenStorageService`.
- Master passwords / secret material must not be held on the main thread longer than necessary — use Worker threads.
- Database paths, sync settings, and preload configurations are defined in `services/` (`RecentFilesService`, `SyncSettingsService`, `SettingsService`).
- Crash logs are stored in EL1 area (shareable) via `CrashLogService`.