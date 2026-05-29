# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeePassHO is a HarmonyOS password manager application built with ArkTS. It is fully compatible with KeePass database format (.kdbx) and supports AES-256 encryption, local storage, and multiple cloud sync options.

## Build Commands

**Windows:**
```bash
hvigorw --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```

**macOS:**
```bash
hvigorw --mode module -p product=mac_debug -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```

**Clean build (Windows):**
```bash
hvigorw clean --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --parallel --incremental --enable-build-script-type-check --daemon
```

**Clean build (macOS):**
```bash
hvigorw clean --mode module -p product=mac_debug -p buildMode=debug assembleHap --analyze=normal --parallel --incremental --enable-build-script-type-check --daemon
```

## Testing

Tests use the Hypium test framework (`@ohos/hypium`) and Hamock for mocking (`@ohos/hamock`).

**Test locations:**
- Entry module tests: `entry/src/test/` and `entry/src/ohosTest/`
- Kdbxweb module tests: `kdbxweb/src/test/` and `kdbxweb/src/ohosTest/`

## Architecture

### Two-Module Structure

1. **entry** - Main HarmonyOS application module
   - Pages: `entry/src/main/ets/pages/` - UI screens (Index, DatabaseView, EntryEdit, etc.)
   - Services: `entry/src/main/ets/services/` - Business logic layer
   - Storage: `entry/src/main/ets/storage/` - File storage abstractions
   - Components: `entry/src/main/ets/components/` - Reusable UI components
   - Workers: `entry/src/main/ets/workers/` - Background threading for database operations

2. **kdbxweb** - KeePass database library (ported from keeweb/kdbxweb)
   - Crypto: `kdbxweb/src/main/ets/crypto/` - Encryption (ChaCha20, Salsa20, Argon2, AES)
   - Format: `kdbxweb/src/main/ets/format/` - KDBX file format handling (Kdbx, KdbxEntry, KdbxGroup, etc.)
   - Utils: `kdbxweb/src/main/ets/utils/` - Binary streams, XML utilities

### Key Data Flow

1. **Database Loading** (`KdbxLoadService`):
   - Uses Worker threads for async database loading
   - `DatabaseLoadWorker.ets` handles the actual KDBX parsing
   - Returns `Kdbx` object containing groups and entries

2. **File Storage** (`FileStorageFactory`):
   - Factory pattern for multiple storage backends
   - Implementations: `LocalFileStorage`, `WebDAVStorage`, `OneDriveStorage`, `FTPStorage`
   - Cache decorator wraps non-local storage for performance

3. **Entry Management** (`DatabaseView.ets`):
   - Central page for browsing password entries
   - Groups and entries displayed in hierarchical list
   - Supports search, sorting, TOTP preview, and batch operations

### Storage Types

Defined in `entry/src/main/ets/storage/StorageType.ets`:
- `LOCAL` - Device local storage
- `WEBDAV` - WebDAV server
- `ONEDRIVE` - Microsoft OneDrive (OAuth2)
- `FTP` - FTP/SFTP servers

### Template System

Entry templates in `entry/src/main/ets/services/template/`:
- Strategy pattern with `ITemplateStrategy`
- `PresetTemplateStrategy` for built-in templates
- `UserTemplateStrategy` for user-defined templates

## Key Dependencies

- `kdbxweb` - Local KeePass database library (modified for HarmonyOS)
- `@ohos-rs/argon2` - Argon2 password hashing (native)
- `@ohos/flate2` - Gzip compression (native)
- `@ohos/axios` - HTTP client
- `@pura/harmony-dialog` - Dialog components
- `@xmldom/xmldom` - XML parsing for KDBX format

## Navigation

Page routes defined in `entry/src/main/resources/base/profile/main_pages.json`. Navigation uses HarmonyOS Router via `CommonUtils.pushUrl()`.

## State Management

- `AppStorage` for global state (location info, preload data)
- `@State`, `@StorageLink` decorators for component state
- `SettingsService` singleton for user preferences
- `RecentFilesService` for file history

## Worker Threading

Database operations use Worker threads to avoid UI blocking:
- `DatabaseLoadWorker.ets` - Loads and parses KDBX files
- `DatabaseSaveWorker.ets` - Saves database changes
- Communication via JSON-serialized messages defined in `WorkerParam.ets`

## Important Patterns

- Services use singleton pattern (e.g., `SettingsService.getInstance()`)
- Factory pattern for `FileStorageFactory`
- Strategy pattern for templates and storage implementations
- Observer pattern via `EventBus` for cross-component communication
