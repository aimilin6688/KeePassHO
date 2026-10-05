import { beforeAll, describe, expect, it } from '@ohos/hypium';
import {
  ByteUtils,
  Kdbx,
  KdbxBinaryWithHash,
  KdbxCredentials,
  KdbxEntry,
  KdbxError,
  KdbxGroup,
  KdbxSnapshot,
  KdbxUuid,
  ProtectedValue,
  VarDictionary
} from 'kdbxweb';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/**
 * 生成确定性测试数据（非随机，便于逐字节比对）
 */
function makePatternData(length: number): ArrayBuffer {
  const arr = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    arr[i] = i % 251;
  }
  return arr.buffer;
}

/**
 * 按标题递归查找条目
 */
function findEntryByTitle(database: Kdbx, title: string): KdbxEntry | null {
  return findEntryInGroup(database.getDefaultGroup(), title);
}

function findEntryInGroup(group: KdbxGroup, title: string): KdbxEntry | null {
  for (let i = 0; i < group.entries.length; i++) {
    if (group.entries[i].fields.get('Title') === title) {
      return group.entries[i];
    }
  }
  for (let i = 0; i < group.groups.length; i++) {
    const found = findEntryInGroup(group.groups[i], title);
    if (found !== null) {
      return found;
    }
  }
  return null;
}

/**
 * 读取附件字节（兼容 KdbxBinary 与 KdbxBinaryWithHash 两种运行时形态）
 */
function getAttachmentBytes(entry: KdbxEntry, name: string): ArrayBuffer | null {
  const binary = entry.binaries.get(name);
  if (binary === undefined) {
    return null;
  }
  if (binary instanceof ProtectedValue) {
    return ByteUtils.arrayToBuffer(binary.getBinary());
  }
  if (binary instanceof ArrayBuffer) {
    return binary;
  }
  const withHash = binary as KdbxBinaryWithHash;
  if (withHash.value instanceof ProtectedValue) {
    return ByteUtils.arrayToBuffer(withHash.value.getBinary());
  }
  return withHash.value as ArrayBuffer;
}

/**
 * KPSN 二进制快照协议单元测试（Kdbx.saveSnapshot / Kdbx.loadSnapshot / KdbxSnapshot 编解码）。
 *
 * 快照为跨线程传输格式：头部 + 明文 XML（附件仅引用）+ 二进制池，不经过 XML base64 内联，
 * 加密 KDBX 落盘仍走 Kdbx.save。全部使用真实加密数据库，不使用 mock 数据。
 */
export default function KdbxSnapshotTest() {
  describe('KdbxSnapshotTest', () => {
    let credentials: KdbxCredentials;

    beforeAll(() => {
      KdbxModeTestHelper.initContext();
      credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
    });

    it('saveSnapshot produces KPSN buffer detected by isSnapshot', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('SnapshotDb', 'snapshot-entry');
      const snapshot = await database.saveSnapshot();

      expect(snapshot instanceof ArrayBuffer).assertTrue();
      expect(KdbxSnapshot.isSnapshot(snapshot)).assertTrue();
      expect(snapshot.byteLength > 18).assertTrue();

      // 非 KPSN 输入不误判：加密 KDBX 文件 / 空缓冲 / 短于固定头的缓冲
      const savedKdbx = await database.save();
      expect(KdbxSnapshot.isSnapshot(savedKdbx)).assertFalse();
      expect(KdbxSnapshot.isSnapshot(new ArrayBuffer(0))).assertFalse();
      expect(KdbxSnapshot.isSnapshot(snapshot.slice(0, 10))).assertFalse();
    });

    it('v4 roundtrip keeps entries, protected fields and version', 0, async () => {
      const database = Kdbx.create(credentials, 'RoundtripDb');
      const entry = database.createEntry(database.getDefaultGroup());
      entry.fields.set('Title', 'rt-entry');
      entry.fields.set('UserName', 'user01');
      entry.fields.set('URL', 'https://example.com');
      entry.fields.set('Password', ProtectedValue.fromString('rt-secret-P@ss'));

      const snapshot = await database.saveSnapshot();
      const restored = await Kdbx.loadSnapshot(snapshot, credentials);

      expect(restored.header.versionMajor).assertEqual(4);
      const restoredEntry = findEntryByTitle(restored, 'rt-entry');
      expect(restoredEntry !== null).assertTrue();
      if (restoredEntry !== null) {
        expect(restoredEntry.fields.get('UserName')).assertEqual('user01');
        expect(restoredEntry.fields.get('URL')).assertEqual('https://example.com');
        const password = restoredEntry.fields.get('Password');
        expect(password instanceof ProtectedValue).assertTrue();
        if (password instanceof ProtectedValue) {
          expect(password.getText()).assertEqual('rt-secret-P@ss');
        }
      }
    });

    it('roundtrip keeps attachments and dedups shared binaries', 0, async () => {
      const database = Kdbx.create(credentials, 'AttachDb');
      const entryA = database.createEntry(database.getDefaultGroup());
      entryA.fields.set('Title', 'attach-a');
      const entryB = database.createEntry(database.getDefaultGroup());
      entryB.fields.set('Title', 'attach-b');

      const data = makePatternData(256 * 1024);
      const binary = await database.binaries.add(data);
      entryA.binaries.set('file.bin', binary);
      entryB.binaries.set('same.bin', binary);

      const snapshot = await database.saveSnapshot();
      const restored = await Kdbx.loadSnapshot(snapshot, credentials);

      const restoredA = findEntryByTitle(restored, 'attach-a');
      const restoredB = findEntryByTitle(restored, 'attach-b');
      expect(restoredA !== null).assertTrue();
      expect(restoredB !== null).assertTrue();
      if (restoredA !== null && restoredB !== null) {
        // 还原后为哈希引用形态，两条目共享同一池条目
        expect(restored.binaries.getAllWithHashes().length).assertEqual(1);
        const binA = restoredA.binaries.get('file.bin') as KdbxBinaryWithHash;
        const binB = restoredB.binaries.get('same.bin') as KdbxBinaryWithHash;
        expect(binA.hash).assertEqual(binary.hash);
        expect(binB.hash).assertEqual(binary.hash);
        const bytesA = getAttachmentBytes(restoredA, 'file.bin');
        expect(bytesA !== null).assertTrue();
        if (bytesA !== null) {
          expect(ByteUtils.arrayBufferEquals(bytesA, data)).assertTrue();
        }
        const bytesB = getAttachmentBytes(restoredB, 'same.bin');
        expect(bytesB !== null).assertTrue();
        if (bytesB !== null) {
          expect(ByteUtils.arrayBufferEquals(bytesB, data)).assertTrue();
        }
      }

      // 快照还原的模型可直接加密落盘，再加载后附件完整（v4 走二进制池引用）
      const saved = await restored.save();
      const reloaded = await Kdbx.load(saved, credentials);
      const reloadedA = findEntryByTitle(reloaded, 'attach-a');
      expect(reloadedA !== null).assertTrue();
      if (reloadedA !== null) {
        const bytes = getAttachmentBytes(reloadedA, 'file.bin');
        expect(bytes !== null).assertTrue();
        if (bytes !== null) {
          expect(ByteUtils.arrayBufferEquals(bytes, data)).assertTrue();
        }
      }
    });

    it('roundtrip keeps protected attachment bytes', 0, async () => {
      const database = Kdbx.create(credentials, 'ProtectedAttachDb');
      const entry = database.createEntry(database.getDefaultGroup());
      entry.fields.set('Title', 'protected-attach');
      const secret = makePatternData(4096);
      // fromBinary 接管传入缓冲并原地 XOR 破坏内容，先保留期望比对副本
      const expected = secret.slice(0);
      const binary = await database.binaries.add(ProtectedValue.fromBinary(secret));
      entry.binaries.set('secret.bin', binary);

      const snapshot = await database.saveSnapshot();
      const restored = await Kdbx.loadSnapshot(snapshot, credentials);

      const restoredEntry = findEntryByTitle(restored, 'protected-attach');
      expect(restoredEntry !== null).assertTrue();
      if (restoredEntry !== null) {
        expect(restoredEntry.binaries.has('secret.bin')).assertTrue();
        const restoredBinary = restoredEntry.binaries.get('secret.bin') as KdbxBinaryWithHash;
        expect(restoredBinary.value instanceof ProtectedValue).assertTrue();
        const bytes = getAttachmentBytes(restoredEntry, 'secret.bin');
        expect(bytes !== null).assertTrue();
        if (bytes !== null) {
          expect(ByteUtils.arrayBufferEquals(bytes, expected)).assertTrue();
        }
      }
    });

    it('v3 roundtrip keeps version and re-save validity', 0, async () => {
      const database = Kdbx.create(credentials, 'V3Db');
      database.setVersion(3);
      KdbxModeTestHelper.addEntry(database, 'v3-entry');

      const snapshot = await database.saveSnapshot();
      const restored = await Kdbx.loadSnapshot(snapshot, credentials);

      expect(restored.header.versionMajor).assertEqual(3);
      expect(restored.header.keyEncryptionRounds)
        .assertEqual(database.header.keyEncryptionRounds);

      // 快照模型可正常加密落盘为合法 v3 文件并再次加载
      const saved = await restored.save();
      const reloaded = await Kdbx.load(saved, credentials);
      expect(reloaded.header.versionMajor).assertEqual(3);
      expect(KdbxModeTestHelper.collectEntryTitles(reloaded).includes('v3-entry')).assertTrue();
    });

    it('roundtrip keeps kdf parameters', 0, async () => {
      const database = Kdbx.create(credentials, 'KdfDb');
      const sourceKdf = database.header.kdfParameters;
      expect(sourceKdf !== undefined).assertTrue();
      if (sourceKdf !== undefined) {
        sourceKdf.set('I', VarDictionary.ValueType.UInt32, 3);

        const snapshot = await database.saveSnapshot();
        const restored = await Kdbx.loadSnapshot(snapshot, credentials);

        const restoredKdf = restored.header.kdfParameters;
        expect(restoredKdf !== undefined).assertTrue();
        if (restoredKdf !== undefined) {
          expect(restoredKdf.length).assertEqual(sourceKdf.length);
          expect(Number(restoredKdf.get('I'))).assertEqual(3);
        }
      }
    });

    it('arrayBufferToKdbx dispatches snapshot, kdbx and plain xml', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('DispatchDb', 'dispatch-entry');
      const loadParam = KdbxModeTestHelper.makeLoadParam('/data/dispatch.kdbx', 'dispatch.kdbx',
        KdbxModeTestHelper.DB_PASSWORD);

      // KPSN 快照 → KdbxSnapshot.load 直达
      const snapshot = await database.saveSnapshot();
      const fromSnapshot = await KdbxUtils.arrayBufferToKdbx(snapshot, loadParam);
      expect(KdbxModeTestHelper.collectEntryTitles(fromSnapshot).includes('dispatch-entry'))
        .assertTrue();

      // KDBX 加密文件 → Kdbx.load
      const savedKdbx = await database.save();
      const fromKdbx = await KdbxUtils.arrayBufferToKdbx(savedKdbx, loadParam);
      expect(KdbxModeTestHelper.collectEntryTitles(fromKdbx).includes('dispatch-entry'))
        .assertTrue();

      // 明文 XML（旧边界格式）→ loadXml 回退路径
      const xml = await database.saveXml();
      const fromXml = await KdbxUtils.arrayBufferToKdbx(ByteUtils.stringToBuffer(xml), loadParam);
      expect(KdbxModeTestHelper.collectEntryTitles(fromXml).includes('dispatch-entry'))
        .assertTrue();
    });

    it('load rejects corrupt snapshot inputs with KdbxError', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('CorruptDb', 'corrupt-entry');
      const snapshot = await database.saveSnapshot();

      // 截断：魔数完整但布局越界 → FileCorrupt
      let error: KdbxError | null = null;
      try {
        await KdbxSnapshot.load(snapshot.slice(0, 30), credentials);
      } catch (e) {
        error = e as KdbxError;
      }
      expect(error instanceof KdbxError).assertTrue();

      // 非 KPSN 数据（加密 KDBX）→ InvalidArg
      const savedKdbx = await database.save();
      error = null;
      try {
        await KdbxSnapshot.load(savedKdbx, credentials);
      } catch (e) {
        error = e as KdbxError;
      }
      expect(error instanceof KdbxError).assertTrue();

      // 破坏魔数 → isSnapshot 识别失败
      const badMagic = snapshot.slice(0);
      new Uint8Array(badMagic)[0] = 0;
      expect(KdbxSnapshot.isSnapshot(badMagic)).assertFalse();
    });

    it('model remains usable after saveSnapshot', 0, async () => {
      const database = await KdbxModeTestHelper.createDatabase('ReuseDb', 'reuse-entry');

      // 连续两次快照均有效（上下文标志位可复位）
      const first = await database.saveSnapshot();
      const second = await database.saveSnapshot();
      expect(KdbxSnapshot.isSnapshot(first)).assertTrue();
      expect(KdbxSnapshot.isSnapshot(second)).assertTrue();

      // 之后仍可正常加密保存
      const saved = await database.save();
      const reloaded = await Kdbx.load(saved, credentials);
      expect(KdbxModeTestHelper.collectEntryTitles(reloaded).includes('reuse-entry')).assertTrue();

      // 修改模型后再快照，增量完整
      KdbxModeTestHelper.addEntry(database, 'reuse-entry-2');
      const third = await database.saveSnapshot();
      const restored = await Kdbx.loadSnapshot(third, credentials);
      const titles = KdbxModeTestHelper.collectEntryTitles(restored);
      expect(titles.includes('reuse-entry')).assertTrue();
      expect(titles.includes('reuse-entry-2')).assertTrue();
    });

    it('roundtrip keeps custom icons', 0, async () => {
      const database = Kdbx.create(credentials, 'IconDb');
      const entry = database.createEntry(database.getDefaultGroup());
      entry.fields.set('Title', 'icon-entry');
      const iconUuid = new KdbxUuid();
      const iconData = makePatternData(2048);
      database.meta.customIcons.set(iconUuid.id, { data: iconData });
      entry.customIcon = iconUuid;

      const snapshot = await database.saveSnapshot();
      const restored = await Kdbx.loadSnapshot(snapshot, credentials);

      expect(restored.meta.customIcons.has(iconUuid.id)).assertTrue();
      const restoredIcon = restored.meta.customIcons.get(iconUuid.id);
      expect(restoredIcon !== undefined).assertTrue();
      if (restoredIcon !== undefined) {
        expect(ByteUtils.arrayBufferEquals(restoredIcon.data, iconData)).assertTrue();
      }
      const restoredEntry = findEntryByTitle(restored, 'icon-entry');
      expect(restoredEntry !== null).assertTrue();
      if (restoredEntry !== null) {
        expect(restoredEntry.customIcon !== undefined).assertTrue();
        if (restoredEntry.customIcon !== undefined) {
          expect(restoredEntry.customIcon.id).assertEqual(iconUuid.id);
        }
      }
    });
  });
}
