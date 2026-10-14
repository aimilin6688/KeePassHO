import { describe, expect, it } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Kdbx, KdbxCredentials, KdbxGroup, ProtectedValue } from 'kdbxweb';
import { TestDataGenerator } from './TestDataGenerator';
import { TestPngBuilder } from './TestPngBuilder';
import { S3Storage } from '../../../../main/ets/storage/s3/S3Storage';
import { S3TestConfig } from '../storage/s3/S3TestConfig';

const DOMAIN = 0x0000;
const TAG = 'GenerateE2eTestDatabaseTest';
/** S3 桶内对象键（App 内「文件路径」与此一致） */
const S3_KEY = 'e2e-test-data.kdbx';

/**
 * E2E 测试数据库生成套件（仅测试目录，不进入主应用）：
 *
 * 1. png_builder_produces_valid_png —— PNG 生成器产物合法（签名/IHDR 尺寸/多 stored 块体积）
 * 2. generate_structure —— 生成的数据库结构完整（分组/条目规模、7 层深嵌套、颜色、
 *    标题边界、TOTP 受保护字段、附件、图片、tags、历史、过期、回收站）
 * 3. upload_and_verify_via_s3 —— 生成→保存→上传 S3（SeaweedFS rport 隧道）→
 *    下载→重载验证（主密码解锁 + 条目数一致）
 *
 * 运行前须确保：宿主机 SeaweedFS 网关 9000 端口 + 设备反向隧道（127.0.0.1:9000 → 宿主 9000）。
 * 连接方式与主密码见 docs/e2e-test-database.md。
 */
export default function GenerateE2eTestDatabaseTest() {
  describe('GenerateE2eTestDatabaseTest', () => {

    it('png_builder_produces_valid_png', 0, async () => {
      const small = TestPngBuilder.buildGradientPng(64, 64);
      // 8 签名 + 25 IHDR + (12 + 2 + 5 + 64*193 + 4) IDAT + 12 IEND
      expect(small.byteLength).assertEqual(12420);
      const smallBytes = new Uint8Array(small);
      expect(smallBytes[0]).assertEqual(0x89);
      expect(smallBytes[1]).assertEqual(0x50);
      expect(smallBytes[2]).assertEqual(0x4E);
      expect(smallBytes[3]).assertEqual(0x47);
      expect(smallBytes[4]).assertEqual(0x0D);
      expect(smallBytes[5]).assertEqual(0x0A);
      expect(smallBytes[6]).assertEqual(0x1A);
      expect(smallBytes[7]).assertEqual(0x0A);
      // IHDR 宽高（大端）：64 x 64
      expect(smallBytes[19]).assertEqual(64);
      expect(smallBytes[23]).assertEqual(64);
      // 256x256：4 个 stored 块（196864 字节原始数据）
      const large = TestPngBuilder.buildGradientPng(256, 256);
      expect(large.byteLength).assertEqual(196947);
    });

    it('generate_structure', 0, async () => {
      const db = await TestDataGenerator.generate();
      const root = db.getDefaultGroup();
      expect(db.meta.name).assertEqual(TestDataGenerator.DB_NAME);
      expect(db.meta.desc).assertEqual(TestDataGenerator.DB_DESCRIPTION);
      expect(db.meta.defaultUser).assertEqual(TestDataGenerator.DEFAULT_USER);
      expect(db.meta.historyMaxItems).assertEqual(TestDataGenerator.HISTORY_MAX_ITEMS);
      expect(db.meta.historyMaxSize).assertEqual(TestDataGenerator.HISTORY_MAX_SIZE_BYTES);
      expect(db.meta.recycleBinEnabled).assertTrue();

      const groupCount = TestDataGenerator.countGroups(root);
      const entryCount = TestDataGenerator.countEntries(root);
      hilog.info(DOMAIN, TAG, 'structure: groups=%{public}d entries=%{public}d', groupCount, entryCount);
      expect(groupCount >= 40).assertTrue();
      expect(entryCount >= 80).assertTrue();

      // 深层嵌套：从第 1 层沿第一个子链走到第 7 层（验证底部导航条层级展示）
      const level1 = TestDataGenerator.findGroupByName(root, '深层嵌套-第1层-区域一');
      expect(level1 !== undefined).assertTrue();
      if (level1 === undefined) {
        return;
      }
      let current: KdbxGroup | undefined = level1;
      let depth = 1;
      while (current !== undefined && current.groups.length > 0) {
        current = current.groups[0];
        depth++;
      }
      expect(depth).assertEqual(7);
      const level2Name = level1.groups[0].name ?? '';
      expect(level2Name.length > 40).assertTrue();

      // 分组颜色（前景/背景/混合）
      const red = TestDataGenerator.findGroupByName(root, '红色分组');
      expect(red !== undefined).assertTrue();
      if (red !== undefined) {
        expect(red.fgColor).assertEqual('#E53935');
      }
      const yellowBg = TestDataGenerator.findGroupByName(root, '黄色背景分组');
      expect(yellowBg !== undefined).assertTrue();
      if (yellowBg !== undefined) {
        expect(yellowBg.bgColor).assertEqual('#FDD835');
      }
      const mixed = TestDataGenerator.findGroupByName(root, '混合配色分组');
      expect(mixed !== undefined).assertTrue();
      if (mixed !== undefined) {
        expect(mixed.fgColor).assertEqual('#E53935');
        expect(mixed.bgColor).assertEqual('#FDD835');
      }

      // 标题边界
      expect(TestDataGenerator.findEntryByTitle(root, '') !== undefined).assertTrue();
      expect(TestDataGenerator.findEntryByTitle(root, 'A') !== undefined).assertTrue();
      expect(TestDataGenerator.findEntryByTitle(root, '😀🎉🔐⚡🌟手机') !== undefined).assertTrue();
      expect(TestDataGenerator.findEntryByTitle(root, '重复标题') !== undefined).assertTrue();
      expect(TestDataGenerator.findEntryByTitle(root,
        'Long English Title Boundary Test Entry With Many Words For Layout Verification') !== undefined)
        .assertTrue();

      // TOTP 受保护字段
      const totpEntry = TestDataGenerator.findEntryByTitle(root, 'TOTP-标准SHA1-30秒');
      expect(totpEntry !== undefined).assertTrue();
      if (totpEntry !== undefined) {
        expect(totpEntry.fields.get('otp') instanceof ProtectedValue).assertTrue();
      }

      // 附件与图片附件
      const attachEntry = TestDataGenerator.findEntryByTitle(root, '附件-文本文件');
      expect(attachEntry !== undefined).assertTrue();
      if (attachEntry !== undefined) {
        expect(attachEntry.binaries.size).assertEqual(2);
        expect(attachEntry.binaries.has('readme.txt')).assertTrue();
        expect(attachEntry.binaries.has('notes.md')).assertTrue();
      }
      const imgEntry = TestDataGenerator.findEntryByTitle(root, '图片-多图片条目');
      expect(imgEntry !== undefined).assertTrue();
      if (imgEntry !== undefined) {
        expect(imgEntry.binaries.size).assertEqual(3);
        expect(imgEntry.binaries.has('photo-1.png')).assertTrue();
        expect(imgEntry.binaries.has('photo-2.png')).assertTrue();
        expect(imgEntry.binaries.has('photo-3.png')).assertTrue();
      }

      // 综合条目：tags / 受保护自定义字段 / 历史 / 过期 / 回收站
      const fullEntry = TestDataGenerator.findEntryByTitle(root, '综合-全字段条目');
      expect(fullEntry !== undefined).assertTrue();
      if (fullEntry !== undefined) {
        expect(fullEntry.tags.length).assertEqual(3);
        expect(fullEntry.fields.get('受保护字段') instanceof ProtectedValue).assertTrue();
      }
      const historyEntry = TestDataGenerator.findEntryByTitle(root, '综合-历史版本条目');
      expect(historyEntry !== undefined).assertTrue();
      if (historyEntry !== undefined) {
        expect(historyEntry.history.length).assertEqual(2);
      }
      const expiredEntry = TestDataGenerator.findEntryByTitle(root, '综合-已过期条目');
      expect(expiredEntry !== undefined).assertTrue();
      if (expiredEntry !== undefined) {
        expect(expiredEntry.times.expires).assertTrue();
      }
      const trashEntry = TestDataGenerator.findEntryByTitle(root, '综合-已删除条目');
      expect(trashEntry !== undefined).assertTrue();
      if (trashEntry !== undefined) {
        expect(db.isInRecycleBin(trashEntry)).assertTrue();
      }
    });

    it('upload_and_verify_via_s3', 0, async () => {
      const db = await TestDataGenerator.generate();
      const entryCount = TestDataGenerator.countEntries(db.getDefaultGroup());
      const content = await db.save();
      hilog.info(DOMAIN, TAG, 'generated kdbx: %{public}d bytes, %{public}d entries',
        content.byteLength, entryCount);

      const storage = new S3Storage();
      storage.init(S3TestConfig.getStorageConfig(S3TestConfig.BUCKET));
      const path = '/' + S3TestConfig.BUCKET + '/' + S3_KEY;
      await storage.write(path, content);
      hilog.info(DOMAIN, TAG, 'uploaded to s3: %{public}s', path);

      const downloaded = await storage.read(path);
      expect(downloaded.byteLength).assertEqual(content.byteLength);

      const reloaded = await Kdbx.load(downloaded,
        new KdbxCredentials(ProtectedValue.fromString(TestDataGenerator.DB_PASSWORD)));
      expect(reloaded.meta.name).assertEqual(TestDataGenerator.DB_NAME);
      const reloadedCount = TestDataGenerator.countEntries(reloaded.getDefaultGroup());
      hilog.info(DOMAIN, TAG, 'reloaded entries: %{public}d', reloadedCount);
      expect(reloadedCount).assertEqual(entryCount);
      const deepGroup = TestDataGenerator.findGroupByName(reloaded.getDefaultGroup(),
        '深层嵌套-第1层-区域一');
      expect(deepGroup !== undefined).assertTrue();
      storage.close();
    });
  });
}
