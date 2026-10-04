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
 * 两个关键设计：
 * 1. 定位一律用控件 id（纯文本断言会被隐藏根栈干扰）
 * 2. 命中控件后校验其 bounds 落在窗口可视区内（AppNavigation 的 4 个根导航栈
 *    常驻组件树，未显示的栈也在匹配范围内，仅靠 id 仍会误命中）
 *
 * 已知边界：本地文件的最终选取依赖系统 DocumentViewPicker（跨应用），
 * UI 测试覆盖到「拉起系统选择器之前」；随后从「最近打开的数据库」选择
 * test-1.kdbx，保证整条打开数据库的链路可在应用内闭环。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { Component, Driver, ON, On, Rect, UiWindow, UIEventObserver } from '@kit.TestKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'OpenDatabaseUiTest';

const BUNDLE_NAME: string = 'com.aimilin.keepassho';
const ABILITY_NAME: string = 'EntryAbility';

/** 测试数据库文件名（已存在于最近打开列表） */
const DB_FILE_NAME: string = 'test-1.kdbx';
/** 测试数据库密码 */
const DB_PASSWORD: string = '1';

/** 页面切换等待时长（ms） */
const SHORT_WAIT: number = 1500;
const NORMAL_WAIT: number = 3000;
/** 解锁耗时较长，单独放宽 */
const UNLOCK_WAIT: number = 15000;
/** 控件查找超时（ms） */
const FIND_TIMEOUT: number = 8000;
/** 每个 it 的看门狗上限：IDE 运行不带 -s timeout 时 hypium 默认仅 15s */
const IT_TIMEOUT: number = 300000;
/** 最大返回次数 */
const MAX_BACK_TIMES: number = 6;
/** 窗口可视区（beforeAll 中填充） */
let windowRect: Rect = { left: 0, top: 0, right: 0, bottom: 0 };

let driver: Driver = Driver.create();

/**
 * 判断控件 bounds 是否落在窗口可视区内
 */
function inWindow(r: Rect): boolean {
  return r.right > r.left && r.bottom > r.top &&
    r.left >= windowRect.left && r.right <= windowRect.right &&
    r.top >= windowRect.top && r.bottom <= windowRect.bottom;
}

/**
 * 在可见控件中查找第一个匹配项
 */
async function findVisible(on: On): Promise<Component | undefined> {
  try {
    const list: Array<Component> = await driver.findComponents(on);
    for (let i: number = 0; i < list.length; i++) {
      const r: Rect = await list[i].getBounds();
      if (inWindow(r)) {
        return list[i];
      }
    }
  } catch (err) {
    return undefined;
  }
  return undefined;
}

/**
 * 可见控件是否存在
 */
async function exists(on: On): Promise<boolean> {
  const found: Component | undefined = await findVisible(on);
  return found !== undefined;
}

/**
 * 轮询等待可见控件出现
 */
async function waitFor(on: On, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    if (await exists(on)) {
      return true;
    }
    await driver.delayMs(500);
  }
  return false;
}

/**
 * 等待可见控件出现并点击
 */
async function click(on: On, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    const target: Component | undefined = await findVisible(on);
    if (target !== undefined) {
      try {
        await target.click();
        return true;
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'click error: %{public}s', JSON.stringify(err));
        return false;
      }
    }
    await driver.delayMs(500);
  }
  hilog.error(DOMAIN, TAG, 'click timeout, no visible component');
  return false;
}

/**
 * 连续返回，直到目标控件可见
 */
async function pressBackUntil(on: On, maxTimes: number): Promise<boolean> {
  for (let i: number = 0; i < maxTimes; i++) {
    if (await exists(on)) {
      return true;
    }
    await driver.pressBack();
    await driver.delayMs(SHORT_WAIT);
  }
  return await exists(on);
}

export default function OpenDatabaseUiTest(): void {
  describe('OpenDatabaseUiTest', () => {
    beforeAll(async () => {
      const delegator: abilityDelegatorRegistry.AbilityDelegator =
        abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({
        bundleName: BUNDLE_NAME,
        abilityName: ABILITY_NAME
      });
      driver = Driver.create();
      await driver.delayMs(NORMAL_WAIT);
      try {
        const window: UiWindow = await driver.findWindow({ bundleName: BUNDLE_NAME });
        windowRect = await window.getBounds();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'get window bounds failed');
      }
      hilog.info(DOMAIN, TAG, 'started, window=%{public}s',
        JSON.stringify({
          left: windowRect.left, top: windowRect.top,
          right: windowRect.right, bottom: windowRect.bottom
        }));
      await driver.delayMs(SHORT_WAIT);
    });

    afterAll(async () => {
      await driver.delayMs(SHORT_WAIT);
      hilog.info(DOMAIN, TAG, 'OpenDatabaseUiTest finished');
    });

    /**
     * 01 冷启动：有最近文件时自动进入解锁页
     */
    it('01_launch_should_show_unlock_page', 0, async () => {
      const onUnlock: boolean = await waitFor(ON.id('input_password'), FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'unlock page visible=%{public}s', String(onUnlock));
      expect(onUnlock).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 02 返回首页
     */
    it('02_press_back_should_return_to_index_page', 0, async () => {
      const reached: boolean = await pressBackUntil(ON.id('btn_open_database'), MAX_BACK_TIMES);
      hilog.info(DOMAIN, TAG, 'index page visible=%{public}s', String(reached));
      expect(reached).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 03 首页设置图标 -> 设置页（校验设置页专有菜单项可见）
     */
    it('03_click_settings_icon_should_open_settings_page', 0, async () => {
      const clicked: boolean = await click(ON.id('btn_open_settings'), FIND_TIMEOUT);
      await driver.delayMs(NORMAL_WAIT);
      const onSettings: boolean = await waitFor(ON.id('menu_change_database'), FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'settings clicked=%{public}s, settings page=%{public}s',
        String(clicked), String(onSettings));
      expect(clicked).assertTrue();
      expect(onSettings).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 04 设置页「更换数据库」-> 位置选择页
     */
    it('04_click_change_database_should_open_select_location_page', 0, async () => {
      const clicked: boolean = await click(ON.id('menu_change_database'), FIND_TIMEOUT);
      await driver.delayMs(NORMAL_WAIT);
      const onLocation: boolean = await waitFor(ON.id('opt_local_file'), FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'change db clicked=%{public}s, location page=%{public}s',
        String(clicked), String(onLocation));
      expect(clicked).assertTrue();
      expect(onLocation).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 05 位置选择页「本地文件」-> 本地文件页
     * 注：再往后点「选择本地文件」会拉起系统文件选择器（跨应用），UI 测试到此为止
     */
    it('05_click_local_file_should_open_local_file_page', 0, async () => {
      const clicked: boolean = await click(ON.id('opt_local_file'), FIND_TIMEOUT);
      await driver.delayMs(NORMAL_WAIT);
      const onLocalFile: boolean = await waitFor(ON.id('btn_select_local_file'), FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'local file clicked=%{public}s, local file page=%{public}s',
        String(clicked), String(onLocalFile));
      expect(clicked).assertTrue();
      expect(onLocalFile).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 06 返回首页 -> 最近打开的数据库
     */
    it('06_back_to_index_and_open_recent_files_page', 0, async () => {
      // 交替：点设置页返回 / 按返回键，直到回到首页
      // （设置页是导航根页，连按返回键会直接退出应用，因此优先点它的返回按钮）
      let reached: boolean = await waitFor(ON.id('btn_open_database'), 2000);
      let backClicked: boolean = false;
      for (let i: number = 0; i < 4 && !reached; i++) {
        if (await click(ON.id('btn_settings_back'), 2000)) {
          backClicked = true;
        }
        await driver.delayMs(NORMAL_WAIT);
        reached = await waitFor(ON.id('btn_open_database'), 3000);
        if (!reached) {
          await driver.pressBack();
          await driver.delayMs(SHORT_WAIT);
          reached = await waitFor(ON.id('btn_open_database'), 2000);
        }
      }
      hilog.info(DOMAIN, TAG, 'settings back=%{public}s, index page=%{public}s',
        String(backClicked), String(reached));
      expect(reached).assertTrue();

      const clicked: boolean = await click(ON.id('btn_recent_files'), FIND_TIMEOUT);
      await driver.delayMs(NORMAL_WAIT);
      const onRecent: boolean = await waitFor(ON.id('recent_file_item'), FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'recent clicked=%{public}s, recent page=%{public}s',
        String(clicked), String(onRecent));
      expect(clicked).assertTrue();
      expect(onRecent).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 07 最近文件列表选择 test-1.kdbx -> 解锁页
     */
    it('07_select_test_database_should_enter_unlock_page', 0, async () => {
      const clicked: boolean = await click(ON.text(DB_FILE_NAME), FIND_TIMEOUT);
      await driver.delayMs(NORMAL_WAIT);
      const onUnlock: boolean = await waitFor(ON.id('input_password'), FIND_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'file clicked=%{public}s, unlock page=%{public}s',
        String(clicked), String(onUnlock));
      expect(clicked).assertTrue();
      expect(onUnlock).assertTrue();
    }, IT_TIMEOUT);

    /**
     * 08 输入密码 1 -> 点击解锁 -> 进入数据库页
     * 同时监听 toast，用于捕获解锁失败时的提示
     */
    it('08_input_password_and_unlock_should_open_database', 0, async () => {
      const toastMessages: Array<string> = [];
      const observer: UIEventObserver = driver.createUIEventObserver();
      observer.once('toastShow', (info) => {
        toastMessages.push(info.text);
      });

      let inputOk: boolean = false;
      const input: Component | undefined = await findVisible(ON.id('input_password'));
      if (input !== undefined) {
        try {
          await input.inputText(DB_PASSWORD);
          inputOk = true;
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'input password error: %{public}s', JSON.stringify(err));
        }
      }
      await driver.delayMs(SHORT_WAIT);

      // 解锁前确认按钮可用
      let unlockEnabled: boolean = false;
      const unlockBtn: Component | undefined = await findVisible(ON.id('btn_unlock'));
      if (unlockBtn !== undefined) {
        unlockEnabled = await unlockBtn.isEnabled();
      }
      const unlockClicked: boolean = await click(ON.id('btn_unlock'), FIND_TIMEOUT);
      await driver.delayMs(UNLOCK_WAIT);

      // 解锁成功标志：数据库主界面的悬浮添加按钮可见
      // （input_search 只有在点击搜索后才渲染，不能作为进入数据库页的判据）
      const onDatabase: boolean = await waitFor(ON.id('btn_add_fab'), FIND_TIMEOUT);
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
    }, IT_TIMEOUT);

    /**
     * 09 读取数据库条目列表并断言非空
     */
    it('09_should_read_database_entry_list', 0, async () => {
      const onDatabase: boolean = await exists(ON.id('btn_add_fab'));
      expect(onDatabase).assertTrue();

      // test-1.kdbx 根分组下的已知分组，断言至少有一个可见
      const knownGroups: Array<string> = ['测试', '模板', 'Internet', 'f67', '分组2'];
      const matchedNames: Array<string> = [];
      for (let i: number = 0; i < knownGroups.length; i++) {
        if (await exists(ON.text(knownGroups[i]))) {
          matchedNames.push(knownGroups[i]);
        }
      }
      hilog.info(DOMAIN, TAG, 'matched groups=%{public}s', JSON.stringify(matchedNames));
      expect(matchedNames.length > 0).assertTrue();

      // 抓取当前页可见文本，作为条目列表内容输出
      const visibleTexts: Array<string> = [];
      const texts: Array<Component> = await driver.findComponents(ON.type('Text'));
      for (let i: number = 0; i < texts.length; i++) {
        try {
          const r: Rect = await texts[i].getBounds();
          if (!inWindow(r)) {
            continue;
          }
          const text: string = await texts[i].getText();
          if (text.length > 0) {
            visibleTexts.push(text);
          }
        } catch (err) {
          // 页面滚动导致部分控件失效，忽略
        }
      }
      hilog.info(DOMAIN, TAG, 'entry list count=%{public}d', visibleTexts.length);
      hilog.info(DOMAIN, TAG, 'entry list=%{public}s', JSON.stringify(visibleTexts));
      expect(visibleTexts.length > 0).assertTrue();
    }, IT_TIMEOUT);
  });
}
