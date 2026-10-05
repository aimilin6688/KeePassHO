/**
 * 打开数据库 UI 自动化测试
 *
 * 真实操作链路（全部通过模拟点击 / 输入完成，不调用任何业务接口）：
 *   启动应用 -> 返回首页 -> 打开设置 -> 更换数据库 -> 本地文件
 *   -> 返回首页 -> 最近打开的数据库 -> 选择 test-1.kdbx
 *   -> 输入密码 1 -> 点击解锁 -> 进入数据库页 -> 读取条目列表
 *
 * 运行方式（UI 套件不进全量回归，单独运行，且运行前应用必须处于未运行状态：
 * 先 hdc shell aa force-stop com.aimilin.keepassho 再执行；
 * 应用残留运行中时 startAbility 仅回前台，不触发 onCreate 预载，种子不生效）：
 *   hdc shell aa test -b com.aimilin.keepassho -m entry_test \
 *     -s unittest OpenHarmonyTestRunner -s class OpenDatabaseUiTest -s timeout 180000
 *
 * 种子自足（beforeAll 自动完成，卸载重装/清数据后可自愈，无需手工预置）：
 *   1. 运行时真实加密生成 test-1.kdbx（密码 1，含已知分组）写入应用沙箱 files 目录
 *   2. 将其最近打开记录置顶写入 recent_files preferences XML（files[0] 为冷启动自动打开目标）
 *
 * 公共 UI 操作（启动 / 查找 / 点击 / 输入 / 等待 / 解锁流程）统一封装在
 * UiTestHelper，最近打开种子注入封装在 UiRecentFilesSeed；本文件只保留用例编排与业务断言。
 *
 * 已知边界：本地文件的最终选取依赖系统 DocumentViewPicker（跨应用），
 * UI 测试覆盖到「拉起系统选择器之前」；随后从「最近打开的数据库」选择
 * test-1.kdbx，保证整条打开数据库的链路可在应用内闭环。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { Component, UIEventObserver } from '@kit.TestKit';
import { Kdbx, KdbxCredentials, KdbxGroup, ProtectedValue } from 'kdbxweb';
import fileIo from '@ohos.file.fs';
import { StorageType } from '../../../../main/ets/storage';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';
import { UiTestHelper } from './UiTestHelper';
import { upsertRecordToFront, waitSeedOnDisk } from './UiRecentFilesSeed';

const DOMAIN: number = 0x0000;
const TAG: string = 'OpenDatabaseUiTest';

/** 测试数据库文件名（beforeAll 自动种入应用沙箱与最近打开列表） */
const DB_FILE_NAME: string = 'test-1.kdbx';
/** 测试数据库密码 */
const DB_PASSWORD: string = '1';
/** 应用沙箱 files 目录（应用进程 filesDir，同 bundle 测试进程可直接读写） */
const APP_FILES_DIR: string = '/data/storage/el2/base/files';
/** 测试数据库沙箱完整路径 */
const DB_FILE_PATH: string = APP_FILES_DIR + '/' + DB_FILE_NAME;
/** test-1.kdbx 根分组下的已知分组（09 用例断言至少一个可见） */
const KNOWN_GROUPS: Array<string> = ['测试', '模板', 'Internet', 'f67', '分组2'];

/**
 * 种子自足：真实加密生成 test-1.kdbx 写入应用沙箱，并将其最近打开记录置顶。
 * 幂等（文件与记录均覆盖式写入），重复运行安全。
 */
async function seedTestDatabase(): Promise<void> {
  const credentials: KdbxCredentials = new KdbxCredentials(ProtectedValue.fromString(DB_PASSWORD));
  const database: Kdbx = Kdbx.create(credentials, 'test-1');
  const rootGroup: KdbxGroup = database.getDefaultGroup();
  for (let i: number = 0; i < KNOWN_GROUPS.length; i++) {
    database.createGroup(rootGroup, KNOWN_GROUPS[i]);
  }
  const saved: ArrayBuffer = await database.save();
  try {
    fileIo.mkdirSync(APP_FILES_DIR, true);
  } catch (err) {
    // 目录已存在时忽略
  }
  const file: fileIo.File = fileIo.openSync(DB_FILE_PATH,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  fileIo.writeSync(file.fd, saved);
  fileIo.closeSync(file);
  hilog.info(DOMAIN, TAG, 'seed kdbx written: %{public}s, size=%{public}d', DB_FILE_PATH, saved.byteLength);

  const emptyConfig: Record<string, Object> = {};
  const record: Record<string, Object> = {
    'filePath': DB_FILE_PATH,
    'fileName': DB_FILE_NAME,
    'storageType': StorageType.LOCAL.toString(),
    'storageConfig': emptyConfig
  };
  await upsertRecordToFront(record);
  const onDisk: boolean = await waitSeedOnDisk(DB_FILE_PATH, 10000);
  hilog.info(DOMAIN, TAG, 'recent record seeded, onDisk=%{public}s', String(onDisk));
}

export default function OpenDatabaseUiTest(): void {
  describe('OpenDatabaseUiTest', () => {
    beforeAll(async () => {
      // 测试进程上下文注入（kdbxweb 运行时依赖）
      KdbxModeTestHelper.initContext();
      // 种子自足：数据库文件 + 最近打开记录置顶
      await seedTestDatabase();
      await UiTestHelper.launchApp();
    });

    afterAll(async () => {
      await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);
      hilog.info(DOMAIN, TAG, 'OpenDatabaseUiTest finished');
    });

    /**
     * 01 冷启动：有最近文件时自动进入解锁页
     */
    it('01_launch_should_show_unlock_page', 0, async () => {
      const onUnlock: boolean = await UiTestHelper.waitForId('input_password', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'unlock page visible=%{public}s', String(onUnlock));
      expect(onUnlock).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 02 返回首页
     */
    it('02_press_back_should_return_to_index_page', 0, async () => {
      const reached: boolean = await UiTestHelper.pressBackUntilId('btn_open_database', UiTestHelper.MAX_BACK_TIMES);
      hilog.info(DOMAIN, TAG, 'index page visible=%{public}s', String(reached));
      expect(reached).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 03 首页设置图标 -> 设置页（校验设置页专有菜单项可见）
     */
    it('03_click_settings_icon_should_open_settings_page', 0, async () => {
      const clicked: boolean = await UiTestHelper.clickId('btn_open_settings', UiTestHelper.FIND_TIMEOUT);
      await UiTestHelper.delay(UiTestHelper.NORMAL_WAIT);
      const onSettings: boolean = await UiTestHelper.waitForId('menu_change_database', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'settings clicked=%{public}s, settings page=%{public}s',
        String(clicked), String(onSettings));
      expect(clicked).assertTrue();
      expect(onSettings).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 04 设置页「更换数据库」-> 位置选择页
     */
    it('04_click_change_database_should_open_select_location_page', 0, async () => {
      const clicked: boolean = await UiTestHelper.clickId('menu_change_database', UiTestHelper.FIND_TIMEOUT);
      await UiTestHelper.delay(UiTestHelper.NORMAL_WAIT);
      const onLocation: boolean = await UiTestHelper.waitForId('opt_local_file', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'change db clicked=%{public}s, location page=%{public}s',
        String(clicked), String(onLocation));
      expect(clicked).assertTrue();
      expect(onLocation).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 05 位置选择页「本地文件」-> 本地文件页
     * 注：再往后点「选择本地文件」会拉起系统文件选择器（跨应用），UI 测试到此为止
     */
    it('05_click_local_file_should_open_local_file_page', 0, async () => {
      const clicked: boolean = await UiTestHelper.clickId('opt_local_file', UiTestHelper.FIND_TIMEOUT);
      await UiTestHelper.delay(UiTestHelper.NORMAL_WAIT);
      const onLocalFile: boolean = await UiTestHelper.waitForId('btn_select_local_file', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'local file clicked=%{public}s, local file page=%{public}s',
        String(clicked), String(onLocalFile));
      expect(clicked).assertTrue();
      expect(onLocalFile).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 06 返回首页 -> 最近打开的数据库
     */
    it('06_back_to_index_and_open_recent_files_page', 0, async () => {
      // 交替：点设置页返回 / 按返回键，直到回到首页
      // （设置页是导航根页，连按返回键会直接退出应用，因此优先点它的返回按钮）
      let reached: boolean = await UiTestHelper.waitForId('btn_open_database', 2000);
      let backClicked: boolean = false;
      for (let i: number = 0; i < 4 && !reached; i++) {
        if (await UiTestHelper.clickId('btn_settings_back', 2000)) {
          backClicked = true;
        }
        await UiTestHelper.delay(UiTestHelper.NORMAL_WAIT);
        reached = await UiTestHelper.waitForId('btn_open_database', 3000);
        if (!reached) {
          await UiTestHelper.pressBack();
          await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);
          reached = await UiTestHelper.waitForId('btn_open_database', 2000);
        }
      }
      hilog.info(DOMAIN, TAG, 'settings back=%{public}s, index page=%{public}s',
        String(backClicked), String(reached));
      expect(reached).assertTrue();

      const clicked: boolean = await UiTestHelper.clickId('btn_recent_files', UiTestHelper.FIND_TIMEOUT);
      await UiTestHelper.delay(UiTestHelper.NORMAL_WAIT);
      const onRecent: boolean = await UiTestHelper.waitForId('recent_file_item', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'recent clicked=%{public}s, recent page=%{public}s',
        String(clicked), String(onRecent));
      expect(clicked).assertTrue();
      expect(onRecent).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 07 最近文件列表选择 test-1.kdbx -> 解锁页
     */
    it('07_select_test_database_should_enter_unlock_page', 0, async () => {
      const clicked: boolean = await UiTestHelper.clickText(DB_FILE_NAME, UiTestHelper.FIND_TIMEOUT);
      await UiTestHelper.delay(UiTestHelper.NORMAL_WAIT);
      const onUnlock: boolean = await UiTestHelper.waitForId('input_password', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'file clicked=%{public}s, unlock page=%{public}s',
        String(clicked), String(onUnlock));
      expect(clicked).assertTrue();
      expect(onUnlock).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 08 输入密码 1 -> 点击解锁 -> 进入数据库页
     * 密码框为安全字段：Component.inputText 的 IME 键入链路会丢文本（实测
     * 按钮不启用），改用坐标注入 inputTextSecure（手工 E2E 验证有效）。
     * 坐标注入会拉起系统键盘，点击解锁前先按 Back 收起。
     * 同时监听 toast，用于捕获解锁失败时的提示
     */
    it('08_input_password_and_unlock_should_open_database', 0, async () => {
      const toastMessages: Array<string> = [];
      const observer: UIEventObserver = UiTestHelper.getDriver().createUIEventObserver();
      observer.once('toastShow', (info) => {
        toastMessages.push(info.text);
      });

      const passwordInput: Component | undefined = await UiTestHelper.findById('input_password');
      const inputOk: boolean = passwordInput !== undefined ?
        await UiTestHelper.inputTextSecure(passwordInput, DB_PASSWORD) : false;
      await UiTestHelper.pressBack();
      await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);

      // 解锁前确认按钮可用
      let unlockEnabled: boolean = false;
      const unlockBtn: Component | undefined = await UiTestHelper.findById('btn_unlock');
      if (unlockBtn !== undefined) {
        unlockEnabled = await unlockBtn.isEnabled();
      }
      const unlockClicked: boolean = await UiTestHelper.clickId('btn_unlock', UiTestHelper.FIND_TIMEOUT);
      // 安装后首次解锁会触发系统通知授权弹框，遮挡应用导致组件查询失效，先关闭
      await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);
      await UiTestHelper.dismissNotificationDialog(4000);
      await UiTestHelper.delay(UiTestHelper.UNLOCK_WAIT);

      // 解锁成功标志：数据库主界面的悬浮添加按钮可见
      // （input_search 只有在点击搜索后才渲染，不能作为进入数据库页的判据）
      const onDatabase: boolean = await UiTestHelper.waitForId('btn_add_fab', UiTestHelper.FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG,
        'input=%{public}s unlockEnabled=%{public}s unlockClicked=%{public}s databasePage=%{public}s toast=%{public}s',
        String(inputOk), String(unlockEnabled), String(unlockClicked), String(onDatabase),
        JSON.stringify(toastMessages));

      if (!onDatabase) {
        hilog.error(DOMAIN, TAG, 'database page not reached after unlock');
      }

      expect(inputOk).assertTrue();
      expect(unlockEnabled).assertTrue();
      expect(unlockClicked).assertTrue();
      expect(onDatabase).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);

    /**
     * 09 读取数据库条目列表并断言非空
     */
    it('09_should_read_database_entry_list', 0, async () => {
      const onDatabase: boolean = await UiTestHelper.existsId('btn_add_fab');
      expect(onDatabase).assertTrue();

      // test-1.kdbx 根分组下的已知分组，断言至少有一个可见
      const knownGroups: Array<string> = KNOWN_GROUPS;
      const matchedNames: Array<string> = [];
      for (let i: number = 0; i < knownGroups.length; i++) {
        if (await UiTestHelper.existsText(knownGroups[i])) {
          matchedNames.push(knownGroups[i]);
        }
      }
      hilog.info(DOMAIN, TAG, 'matched groups=%{public}s', JSON.stringify(matchedNames));
      expect(matchedNames.length > 0).assertTrue();

      // 抓取当前页可见文本，作为条目列表内容输出
      const visibleTexts: Array<string> = await UiTestHelper.collectVisibleTexts();
      hilog.info(DOMAIN, TAG, 'entry list count=%{public}d', visibleTexts.length);
      hilog.info(DOMAIN, TAG, 'entry list=%{public}s', JSON.stringify(visibleTexts));
      expect(visibleTexts.length > 0).assertTrue();
    }, UiTestHelper.IT_TIMEOUT);
  });
}
