# CLAUDE.md

KeePassHO — HarmonyOS password manager, compatible with KeePass (.kdbx), AES-256.

## Build & Deploy

**Windows (on this machine):**
```bash
hvigor="D:/Software/HarmonyOS/command-line-tools/bin/hvigorw.bat"
hdc="D:/Software/HarmonyOS/command-line-tools/sdk/default/openharmony/toolchains/hdc.exe"
hap="entry/build/default/outputs/default/entry-default-signed.hap"

cd "D:/workspace/harmonyos/kee-pass-ho"
"$hvigor" --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
"$hdc" install -r "$hap"
"$hdc" shell aa start -a EntryAbility -b com.aimilin.keepassho
```

**macOS:**
```bash
./hvigorw --mode module -p product=mac_debug -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
hdc install -r "entry/build/mac_debug/outputs/default/entry-default-signed.hap"
hdc shell aa start -a EntryAbility -b com.aimilin.keepassho
```

## Architecture

- **entry/** — Main app: pages, services, components, workers, storage
- **kdbxweb/** — KeePass library: crypto (ChaCha20, Argon2, AES), format (Kdbx/KdbxEntry/KdbxGroup), utils
- **Storage types**: LOCAL, WEBDAV, ONEDRIVE, FTP (via factory pattern)
- **Worker threading**: `DatabaseLoadWorker.ets`, `DatabaseSaveWorker.ets`
- **State**: `AppStorage`, `SettingsService` singleton, `EventBus`

## Tests

- Entry: `entry/src/test/` & `entry/src/ohosTest/`
- Kdbxweb: `kdbxweb/src/test/` & `kdbxweb/src/ohosTest/`
- Framework: Hypium + Hamock

## Key Dependencies

`kdbxweb`, `@ohos-rs/argon2`, `@ohos/flate2`, `@ohos/axios`, `@pura/harmony-dialog`, `@xmldom/xmldom`