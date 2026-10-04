/**
 * 打开数据库 UI 自动化测试
 *
 * 真实操作链路（全部通过模拟点击 / 输入完成，不调用任何业务接口）：
 *   启动应用 -> 返回首页 -> 打开设置 -> 更换数据库 -> 本地文件
 *   -> 返回首页 -> 最近打开的数据库 -> 选择 test-1.kdbx
 *   -> 输入密码 1 -> 点击解锁 -> 进入数据库页 -> 读取条目列表
 *
 * 运行方式：
 *   hdc shell aa test -b com.aimilin.keepassho -m entry_test \
 *     -s unittest OpenHarmonyTestRunner -s class OpenDatabaseUiTest -s timeout 180000
 *
 * 公共 UI 操作（启动 / 查找 / 点击 / 输入 / 等待 / 解锁流程）统一封装在
 * UiTestHelper，新增 UI 套件直接复用；本文件只保留用例编排与业务断言。
 *
 * 已知边界：本地文件的最终选取依赖系统 DocumentViewPicker（跨应用），
 * UI 测试覆盖到「拉起系统选择器之前」；随后从「最近打开的数据库」选择
 * test-1.kdbx，保证整条打开数据库的链路可在应用内闭环。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { Component, UIEventObserver } from '@kit.TestKit';
import { UiTestHelper } from './UiTestHelper';

const DOMAIN: number = 0x0000;
const TAG: string = 'OpenDatabaseUiTest';

/** 测试数据库文件名（已存在于最近打开列表） */
const DB_FILE_NAME: string = 'test-1.kdbx';
/** 测试数据库密码 */
const DB_PASSWORD: string = '1';

export default function OpenDatabaseUiTest(): void {
  describe('OpenDatabaseUiTest', () => {
    beforeAll(async () => {
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
     * 同时监听 toast，用于捕获解锁失败时的提示
     */
    it('08_input_password_and_unlock_should_open_database', 0, async () => {
      const toastMessages: Array<string> = [];
      const observer: UIEventObserver = UiTestHelper.getDriver().createUIEventObserver();
      observer.once('toastShow', (info) => {
        toastMessages.push(info.text);
      });

      const inputOk: boolean = await UiTestHelper.inputTextById('input_password', DB_PASSWORD);
      await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);

      // 解锁前确认按钮可用
      let unlockEnabled: boolean = false;
      const unlockBtn: Component | undefined = await UiTestHelper.findById('btn_unlock');
      if (unlockBtn !== undefined) {
        unlockEnabled = await unlockBtn.isEnabled();
      }
      const unlockClicked: boolean = await UiTestHelper.clickId('btn_unlock', UiTestHelper.FIND_TIMEOUT);
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
      const knownGroups: Array<string> = ['测试', '模板', 'Internet', 'f67', '分组2'];
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
