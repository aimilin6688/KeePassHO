/**
 * UI 自动化测试公共操作封装（所有 UI 套件复用）
 *
 * 两个关键设计（新 UI 测试务必沿用）：
 * 1. 定位一律用控件 id（纯文本断言会被隐藏根栈干扰）
 * 2. 命中控件后校验其 bounds 落在窗口可视区内（AppNavigation 的 4 个根导航栈
 *    常驻组件树，未显示的栈也在匹配范围内，仅靠 id 仍会误命中）
 *
 * 分层：
 *   基础原语：launchApp / findVisible / findAnywhere / exists / waitFor / waitGone /
 *             click / inputText / pressBack 系列 / collectVisibleTexts /
 *             dismissNotificationDialog（系统通知授权弹框）
 *   便捷封装：*Id / *Text 变体（id 定位为主，文本匹配兜底）
 *   应用流程：unlockDatabase（解锁页 -> 数据库列表）、openRecentDatabase
 *             （锁定 -> 关闭数据库 -> 最近打开 -> 选择文件 -> 解锁）
 *
 * 新增 UI 测试套件模板：
 *   beforeAll: await UiTestHelper.launchApp();
 *   用例内:    UiTestHelper.waitForId / clickId / existsText / inputTextById 等静态方法
 *
 * 弹框等位于独立子窗口的场景：findVisible 找不到时用 findAnywhere 放开窗口过滤。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Component, Driver, ON, On, Point, Rect, UiWindow, abilityDelegatorRegistry } from '@kit.TestKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'UiTestHelper';

/** 轮询间隔（ms） */
const POLL_INTERVAL: number = 500;

export class UiTestHelper {
  public static readonly BUNDLE_NAME: string = 'com.aimilin.keepassho';
  public static readonly ABILITY_NAME: string = 'EntryAbility';

  /** 页面切换等待时长（ms） */
  public static readonly SHORT_WAIT: number = 1500;
  public static readonly NORMAL_WAIT: number = 3000;
  /** 解锁耗时较长（远端库含下载），单独放宽 */
  public static readonly UNLOCK_WAIT: number = 20000;
  /** 控件查找超时（ms） */
  public static readonly FIND_TIMEOUT: number = 8000;
  /** 每个 it 的看门狗上限：IDE 运行不带 -s timeout 时 hypium 默认仅 15s */
  public static readonly IT_TIMEOUT: number = 300000;
  /** 最大返回次数 */
  public static readonly MAX_BACK_TIMES: number = 6;
  /** 系统通知授权弹框的拒绝按钮候选文案（系统版本措辞可能不同） */
  private static readonly DIALOG_DENY_TEXTS: Array<string> = ['不允许', '禁止', '暂不'];

  private static driver: Driver = Driver.create();
  private static windowRect: Rect = { left: 0, top: 0, right: 0, bottom: 0 };

  public static getDriver(): Driver {
    return UiTestHelper.driver;
  }

  public static getWindowRect(): Rect {
    return UiTestHelper.windowRect;
  }

  /**
   * 冷启动应用并初始化 Driver 与窗口可视区（beforeAll 中调用）
   */
  public static async launchApp(): Promise<void> {
    const delegator: abilityDelegatorRegistry.AbilityDelegator =
      abilityDelegatorRegistry.getAbilityDelegator();
    await delegator.startAbility({
      bundleName: UiTestHelper.BUNDLE_NAME,
      abilityName: UiTestHelper.ABILITY_NAME
    });
    UiTestHelper.driver = Driver.create();
    await UiTestHelper.driver.delayMs(UiTestHelper.NORMAL_WAIT);
    try {
      const window: UiWindow = await UiTestHelper.driver.findWindow({ bundleName: UiTestHelper.BUNDLE_NAME });
      UiTestHelper.windowRect = await window.getBounds();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'get window bounds failed');
    }
    hilog.info(DOMAIN, TAG, 'started, window=%{public}s',
      JSON.stringify({
        left: UiTestHelper.windowRect.left, top: UiTestHelper.windowRect.top,
        right: UiTestHelper.windowRect.right, bottom: UiTestHelper.windowRect.bottom
      }));
    await UiTestHelper.driver.delayMs(UiTestHelper.SHORT_WAIT);
    // 首次安装后冷启动可能残留/弹出系统通知授权弹框，遮挡应用导致组件查询失效
    await UiTestHelper.dismissNotificationDialog(2000);
  }

  public static async delay(ms: number): Promise<void> {
    await UiTestHelper.driver.delayMs(ms);
  }

  public static async pressBack(): Promise<void> {
    await UiTestHelper.driver.pressBack();
  }

  /**
   * 判断控件 bounds 是否落在窗口可视区内
   */
  public static inWindow(r: Rect): boolean {
    return r.right > r.left && r.bottom > r.top &&
      r.left >= UiTestHelper.windowRect.left && r.right <= UiTestHelper.windowRect.right &&
      r.top >= UiTestHelper.windowRect.top && r.bottom <= UiTestHelper.windowRect.bottom;
  }

  /**
   * 在可见控件中查找第一个匹配项
   */
  public static async findVisible(on: On): Promise<Component | undefined> {
    try {
      const list: Array<Component> = await UiTestHelper.driver.findComponents(on);
      for (let i: number = 0; i < list.length; i++) {
        const r: Rect = await list[i].getBounds();
        if (UiTestHelper.inWindow(r)) {
          return list[i];
        }
      }
    } catch (err) {
      return undefined;
    }
    return undefined;
  }

  /**
   * 不做窗口过滤的查找（弹框位于子窗口时使用）
   */
  public static async findAnywhere(on: On): Promise<Component | undefined> {
    try {
      const list: Array<Component> = await UiTestHelper.driver.findComponents(on);
      if (list.length > 0) {
        return list[0];
      }
    } catch (err) {
      return undefined;
    }
    return undefined;
  }

  public static async findById(id: string): Promise<Component | undefined> {
    return await UiTestHelper.findVisible(ON.id(id));
  }

  public static async exists(on: On): Promise<boolean> {
    const found: Component | undefined = await UiTestHelper.findVisible(on);
    return found !== undefined;
  }

  public static async existsId(id: string): Promise<boolean> {
    return await UiTestHelper.exists(ON.id(id));
  }

  public static async existsText(text: string): Promise<boolean> {
    return await UiTestHelper.exists(ON.text(text));
  }

  /**
   * 轮询等待可见控件出现
   */
  public static async waitFor(on: On, timeout: number): Promise<boolean> {
    for (let waited: number = 0; waited <= timeout; waited += POLL_INTERVAL) {
      if (await UiTestHelper.exists(on)) {
        return true;
      }
      await UiTestHelper.driver.delayMs(POLL_INTERVAL);
    }
    return false;
  }

  /**
   * 轮询等待可见控件消失
   */
  public static async waitGone(on: On, timeout: number): Promise<boolean> {
    for (let waited: number = 0; waited <= timeout; waited += POLL_INTERVAL) {
      if (!await UiTestHelper.exists(on)) {
        return true;
      }
      await UiTestHelper.driver.delayMs(POLL_INTERVAL);
    }
    return false;
  }

  public static async waitForId(id: string, timeout: number): Promise<boolean> {
    return await UiTestHelper.waitFor(ON.id(id), timeout);
  }

  public static async waitForText(text: string, timeout: number): Promise<boolean> {
    return await UiTestHelper.waitFor(ON.text(text), timeout);
  }

  public static async waitGoneId(id: string, timeout: number): Promise<boolean> {
    return await UiTestHelper.waitGone(ON.id(id), timeout);
  }

  /**
   * 等待可见控件出现并点击
   */
  public static async click(on: On, timeout: number): Promise<boolean> {
    for (let waited: number = 0; waited <= timeout; waited += POLL_INTERVAL) {
      const target: Component | undefined = await UiTestHelper.findVisible(on);
      if (target !== undefined) {
        try {
          await target.click();
          return true;
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'click error: %{public}s', JSON.stringify(err));
          return false;
        }
      }
      await UiTestHelper.driver.delayMs(POLL_INTERVAL);
    }
    hilog.error(DOMAIN, TAG, 'click timeout, no visible component');
    return false;
  }

  public static async clickId(id: string, timeout: number): Promise<boolean> {
    return await UiTestHelper.click(ON.id(id), timeout);
  }

  public static async clickText(text: string, timeout: number): Promise<boolean> {
    return await UiTestHelper.click(ON.text(text), timeout);
  }

  /**
   * 向指定控件输入文本（异常吞掉并返回 false）
   */
  public static async inputText(target: Component, text: string): Promise<boolean> {
    try {
      await target.inputText(text);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'inputText error: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  public static async inputTextById(id: string, text: string): Promise<boolean> {
    const target: Component | undefined = await UiTestHelper.findById(id);
    if (target === undefined) {
      return false;
    }
    return await UiTestHelper.inputText(target, text);
  }

  /**
   * 向安全密码框（InputType.Password）注入文本。
   * Component.inputText 走「聚焦 -> 光标置尾 -> IME 键入」链路，安全字段上
   * 文本会被 IME 丢弃（实测 HMKeyboard inputTextLength=0，按钮始终不启用）；
   * 坐标注入（等价 uitest uiInput inputText x y text）已在手工 E2E 中对
   * 同一密码框验证有效（docs/ui/uitest-manual-driving-guide.md 阶段 C）。
   * 注意：坐标点击会拉起系统键盘，调用方点击后续按钮前需 pressBack 收起。
   */
  public static async inputTextSecure(target: Component, text: string): Promise<boolean> {
    try {
      const r: Rect = await target.getBounds();
      const p: Point = {
        x: Math.max(1, Math.round((r.left + r.right) / 2)),
        y: Math.max(1, Math.round((r.top + r.bottom) / 2))
      };
      await UiTestHelper.driver.click(p.x, p.y);
      await UiTestHelper.driver.delayMs(1200);
      await UiTestHelper.driver.inputText(p, text);
      hilog.info(DOMAIN, TAG, 'inputTextSecure at (%{public}d, %{public}d)',
        p.x, p.y);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'inputTextSecure error: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 关闭系统通知授权弹框（requestEnableNotification 触发，安装后首次解锁必弹）。
   * 弹框位于系统子窗口，出现期间 uitest 查不到任何应用组件，
   * 必须点击拒绝按钮关闭后才能继续断言（拒绝一次后本次安装内不再弹出）。
   * @return true 表示发现并关闭了弹框
   */
  public static async dismissNotificationDialog(timeout: number): Promise<boolean> {
    for (let waited: number = 0; waited <= timeout; waited += POLL_INTERVAL) {
      for (let i: number = 0; i < UiTestHelper.DIALOG_DENY_TEXTS.length; i++) {
        const denyText: string = UiTestHelper.DIALOG_DENY_TEXTS[i];
        const btn: Component | undefined = await UiTestHelper.findAnywhere(ON.text(denyText));
        if (btn !== undefined) {
          try {
            await btn.click();
            hilog.info(DOMAIN, TAG, 'notification dialog dismissed by click: %{public}s', denyText);
            await UiTestHelper.driver.delayMs(UiTestHelper.SHORT_WAIT);
            return true;
          } catch (err) {
            hilog.error(DOMAIN, TAG, 'dismiss dialog click error: %{public}s', JSON.stringify(err));
          }
        }
      }
      await UiTestHelper.driver.delayMs(POLL_INTERVAL);
    }
    return false;
  }

  /**
   * 控件是否可用（异常按不可用处理）
   */
  public static async isEnabled(target: Component): Promise<boolean> {
    try {
      return await target.isEnabled();
    } catch (err) {
      return false;
    }
  }

  /**
   * 连续返回，直到目标控件可见
   */
  public static async pressBackUntilVisible(on: On, maxTimes: number): Promise<boolean> {
    for (let i: number = 0; i < maxTimes; i++) {
      if (await UiTestHelper.exists(on)) {
        return true;
      }
      await UiTestHelper.driver.pressBack();
      await UiTestHelper.driver.delayMs(UiTestHelper.SHORT_WAIT);
    }
    return await UiTestHelper.exists(on);
  }

  /**
   * 连续返回，直到目标控件消失（用于从编辑页回到数据库列表）
   */
  public static async pressBackUntilGone(on: On, maxTimes: number): Promise<boolean> {
    for (let i: number = 0; i < maxTimes; i++) {
      if (!await UiTestHelper.exists(on)) {
        return true;
      }
      await UiTestHelper.driver.pressBack();
      await UiTestHelper.driver.delayMs(UiTestHelper.SHORT_WAIT);
    }
    return !await UiTestHelper.exists(on);
  }

  public static async pressBackUntilId(id: string, maxTimes: number): Promise<boolean> {
    return await UiTestHelper.pressBackUntilVisible(ON.id(id), maxTimes);
  }

  public static async pressBackUntilGoneId(id: string, maxTimes: number): Promise<boolean> {
    return await UiTestHelper.pressBackUntilGone(ON.id(id), maxTimes);
  }

  /**
   * 抓取当前页所有可见非空文本（条目列表内容输出用）
   */
  public static async collectVisibleTexts(): Promise<Array<string>> {
    const visibleTexts: Array<string> = [];
    try {
      const texts: Array<Component> = await UiTestHelper.driver.findComponents(ON.type('Text'));
      for (let i: number = 0; i < texts.length; i++) {
        try {
          const r: Rect = await texts[i].getBounds();
          if (!UiTestHelper.inWindow(r)) {
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
    } catch (err) {
      return visibleTexts;
    }
    return visibleTexts;
  }

  /**
   * 解锁页输入主密码并解锁，等待进入数据库列表（btn_add_fab 可见）。
   * 密码框为 InputType.Password 安全字段，Component.inputText 的 IME 键入
   * 链路会丢文本，改用坐标注入（inputTextSecure，手工 E2E 验证有效）。
   * 密码框会拉起系统安全键盘（独立窗口），其遮挡会导致底层控件在控件树中被过滤，
   * 必须先按 Back 收起键盘再点击解锁（与手工 E2E 流程一致）。
   * @param verifyText 非空时解锁成功后额外等待该文本可见（如种子条目标题）
   */
  public static async unlockDatabase(password: string, verifyText: string = ''): Promise<boolean> {
    const input: Component | undefined = await UiTestHelper.findById('input_password');
    if (input === undefined) {
      return false;
    }
    if (!await UiTestHelper.inputTextSecure(input, password)) {
      return false;
    }
    await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);
    await UiTestHelper.pressBack();
    await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);
    if (!await UiTestHelper.clickId('btn_unlock', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    // 安装后首次解锁会触发系统通知授权弹框（遮挡应用导致组件查询失效），先关闭再等列表页
    await UiTestHelper.delay(UiTestHelper.SHORT_WAIT);
    await UiTestHelper.dismissNotificationDialog(4000);
    if (!await UiTestHelper.waitForId('btn_add_fab', UiTestHelper.UNLOCK_WAIT)) {
      return false;
    }
    if (verifyText.length > 0) {
      return await UiTestHelper.waitForText(verifyText, UiTestHelper.FIND_TIMEOUT);
    }
    return true;
  }

  /**
   * 切换数据库全流程：锁定 -> 关闭数据库 -> 首页 -> 最近打开 -> 选择目标文件 -> 解锁
   * @param verifyText 非空时解锁成功后额外等待该文本可见（如种子条目标题）
   */
  public static async openRecentDatabase(fileName: string, password: string,
    verifyText: string = ''): Promise<boolean> {
    if (!await UiTestHelper.clickId('btn_lock_database', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.waitForId('btn_close_database', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.clickId('btn_close_database', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.waitForId('btn_recent_files', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.clickId('btn_recent_files', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.waitForId('recent_file_item', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.clickText(fileName, UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    if (!await UiTestHelper.waitForId('input_password', UiTestHelper.FIND_TIMEOUT)) {
      return false;
    }
    return await UiTestHelper.unlockDatabase(password, verifyText);
  }
}
