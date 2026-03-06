import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { common, contextConstant } from '@kit.AbilityKit';
import { fileIo, fileUri  } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'CrashLogService';
const LOG_DIR = 'crash_logs';
const LOG_PREFIX = 'crash_';
const LOG_EXT = '.log';
const MAX_LOG_FILES = 5;
const WATCHER_NAME = 'crashEventWatcher';

/**
 * 崩溃日志服务
 * 负责监听崩溃事件、写入日志文件、检测和处理崩溃日志
 * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-crash-events
 */
export class CrashLogService {
  private static instance: CrashLogService;
  private el1Context: common.Context | null = null;
  private watcher: hiAppEvent.Watcher | null = null;
  private appVersion: string = '';
  private logDirPath: string = '';

  public static getInstance(): CrashLogService {
    if (!CrashLogService.instance) {
      CrashLogService.instance = new CrashLogService();
    }
    return CrashLogService.instance;
  }

  /**
   * 初始化崩溃监听服务
   * @param context UIAbility上下文
   */
  public async init(context: common.UIAbilityContext): Promise<void> {
    try {
      // 创建 EL1 级别的上下文，用于存储可分享的崩溃日志文件
      this.el1Context = context.createAreaModeContext(contextConstant.AreaMode.EL1);
      this.logDirPath = `${this.el1Context.filesDir}/${LOG_DIR}`;
      hilog.info(DOMAIN, TAG, 'EL1 context created, logDirPath: %{public}s', this.logDirPath);
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to create EL1 context: %{public}s', err.message);
      // 回退到默认上下文
      this.logDirPath = `${context.filesDir}/${LOG_DIR}`;
    }
    await this.getAppVersion();
    await this.ensureLogDir();
    this.setCrashEventParams();
    this.subscribeCrashEvent();
    hilog.info(DOMAIN, TAG, 'CrashLogService initialized');
  }

  /**
   * 获取应用版本号
   */
  private async getAppVersion(): Promise<void> {
    try {
      const bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION;
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleFlags);
      this.appVersion = bundleInfo.versionName;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to get app version: %{public}s', err.message);
      this.appVersion = 'unknown';
    }
  }

  /**
   * 确保日志目录存在
   */
  private async ensureLogDir(): Promise<void> {
    try {
      if (!this.logDirPath) {
        return;
      }
      const isExist = await fileIo.access(this.logDirPath);
      if (!isExist) {
        await fileIo.mkdir(this.logDirPath);
        hilog.info(DOMAIN, TAG, 'Created crash log directory');
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to ensure log dir: %{public}s', err.message);
    }
  }

  /**
   * 设置崩溃事件自定义参数
   */
  private setCrashEventParams(): void {
    try {
      // 构建崩溃事件的自定义参数
      const crashParams: Record<string, hiAppEvent.ParamType> = {
        'app_name': 'KeePassHO',
        'app_version': this.appVersion
      };

      // 设置崩溃事件的自定义参数
      hiAppEvent.setEventParam(crashParams, hiAppEvent.domain.OS, hiAppEvent.event.APP_CRASH).then(() => {
        hilog.info(DOMAIN, TAG, 'HiAppEvent success to set event param');
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'HiAppEvent code: %{public}d, message: %{public}s', err.code, err.message);
      });
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to set crash event params: %{public}s', err.message);
    }
  }

  /**
   * 订阅崩溃事件
   */
  private subscribeCrashEvent(): void {
    try {
      // 创建崩溃事件观察者
      this.watcher = {
        name: WATCHER_NAME,
        appEventFilters: [
          {
            domain: hiAppEvent.domain.OS,
            names: [hiAppEvent.event.APP_CRASH]
          }
        ],
        onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>) => {
          this.handleCrashEvent(domain, appEventGroups);
        }
      };

      // 添加崩溃事件观察者
      hiAppEvent.addWatcher(this.watcher);
      hilog.info(DOMAIN, TAG, 'Crash event watcher added');
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to add crash event watcher: %{public}s', err.message);
    }
  }

  /**
   * 取消订阅崩溃事件
   */
  public unsubscribeCrashEvent(): void {
    if (this.watcher) {
      try {
        hiAppEvent.removeWatcher(this.watcher);
        hilog.info(DOMAIN, TAG, 'Crash event watcher removed');
      } catch (error) {
        const err = error as BusinessError;
        hilog.error(DOMAIN, TAG, 'Failed to remove crash event watcher: %{public}s', err.message);
      }
      this.watcher = null;
    }
  }

  /**
   * 处理崩溃事件
   */
  private handleCrashEvent(domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>): void {
    hilog.info(DOMAIN, TAG, 'HiAppEvent onReceive: domain=%{public}s', domain);

    for (const eventGroup of appEventGroups) {
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventName=%{public}s', eventGroup.name);
      for (const eventInfo of eventGroup.appEventInfos) {
        this.processCrashEventInfo(eventInfo);
      }
    }
  }

  /**
   * 处理崩溃事件信息
   */
  private processCrashEventInfo(eventInfo: hiAppEvent.AppEventInfo): void {
    hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.domain=%{public}s', eventInfo.domain);
    hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.name=%{public}s', eventInfo.name);
    hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.eventType=%{public}d', eventInfo.eventType);

    const params = eventInfo.params;
    if (params) {
      // 崩溃事件发生的时间戳
      const time = params['time'] as number;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.time=%{public}d', time);

      // 崩溃类型 (JsError 或 NativeCrash)
      const crashType = params['crash_type'] as string;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.crash_type=%{public}s', crashType);

      // 崩溃应用的前后台状态
      const foreground = params['foreground'] as boolean;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.foreground=%{public}s', String(foreground));

      // 崩溃应用的版本信息
      const bundleVersion = params['bundle_version'] as string;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.bundle_version=%{public}s', bundleVersion);

      // 崩溃应用的包名
      const bundleName = params['bundle_name'] as string;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.bundle_name=%{public}s', bundleName);

      // 崩溃应用的进程id
      const pid = params['pid'] as number;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.pid=%{public}d', pid);

      const uid = params['uid'] as number;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.uid=%{public}d', uid);

      // 异常类型、异常原因和异常调用栈
      const exception: hiAppEvent.ParamType | undefined = params['exception'];
      if (exception) {
        hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.exception=%{public}s', JSON.stringify(exception));
      }

      // 崩溃日志文件路径
      const externalLog: hiAppEvent.ParamType | undefined = params['external_log'];
      if (externalLog) {
        hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.external_log=%{public}s', JSON.stringify(externalLog));
      }

      const logOverLimit = params['log_over_limit'] as boolean;
      hilog.info(DOMAIN, TAG, 'HiAppEvent eventInfo.params.log_over_limit=%{public}s', String(logOverLimit));
    }

    // 写入崩溃日志文件
    this.writeCrashLog(eventInfo);
  }

  /**
   * 写入崩溃日志文件
   */
  private writeCrashLog(eventInfo: hiAppEvent.AppEventInfo): void {
    if (!this.logDirPath) {
      return;
    }

    try {
      const timestamp = Date.now();
      const dateStr = this.formatDate(new Date());
      const fileName = `${LOG_PREFIX}${timestamp}${LOG_EXT}`;
      const filePath = `${this.logDirPath}/${fileName}`;

      const logContent = this.buildLogContent(eventInfo, dateStr);

      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, logContent);
      fileIo.closeSync(file);

      hilog.info(DOMAIN, TAG, 'Crash log written to: %{public}s', filePath);

      // 清理旧日志文件
      this.cleanupOldLogs();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to write crash log: %{public}s', err.message);
    }
  }

  /**
   * 构建日志内容
   */
  private buildLogContent(eventInfo: hiAppEvent.AppEventInfo, dateStr: string): string {
    const lines: string[] = [];
    lines.push('==================== Crash Log ====================');
    lines.push(`App: KeePassHO`);
    lines.push(`Version: ${this.appVersion}`);
    lines.push(`Device: ${deviceInfo.productModel}`);
    lines.push(`OS: HarmonyOS ${deviceInfo.osFullName}`);
    lines.push(`SDK API: ${deviceInfo.sdkApiVersion}`);
    lines.push(`Crash Time: ${dateStr}`);
    lines.push('===================================================');
    lines.push('');

    const params = eventInfo.params;
    if (params) {
      // 基本信息
      lines.push('=== Basic Info ===');
      lines.push(`Domain: ${eventInfo.domain}`);
      lines.push(`Event Name: ${eventInfo.name}`);
      lines.push(`Event Type: ${eventInfo.eventType}`);
      lines.push('');

      // 崩溃信息
      lines.push('=== Crash Info ===');
      const crashType = params['crash_type'] as string;
      lines.push(`Crash Type: ${crashType}`);
      const time = params['time'] as number;
      lines.push(`Crash Timestamp: ${time}`);
      const foreground = params['foreground'] as boolean;
      lines.push(`Foreground: ${foreground}`);
      const pid = params['pid'] as number;
      lines.push(`PID: ${pid}`);
      const uid = params['uid'] as number;
      lines.push(`UID: ${uid}`);
      lines.push('');

      // 应用信息
      lines.push('=== App Info ===');
      const bundleName = params['bundle_name'] as string;
      lines.push(`Bundle Name: ${bundleName}`);
      const bundleVersion = params['bundle_version'] as string;
      lines.push(`Bundle Version: ${bundleVersion}`);
      lines.push('');

      // 异常信息
      lines.push('=== Exception ===');
      const exception: hiAppEvent.ParamType | undefined = params['exception'];
      if (exception) {
        lines.push(JSON.stringify(exception, null, 2));
      }
      lines.push('');

      // 内存信息
      lines.push('=== Memory ===');
      const memory: hiAppEvent.ParamType | undefined = params['memory'];
      if (memory) {
        lines.push(JSON.stringify(memory, null, 2));
      }
      lines.push('');

      // 进程存活时间
      const processLifeTime = params['process_life_time'] as number;
      if (processLifeTime !== undefined) {
        lines.push(`Process Life Time: ${processLifeTime} seconds`);
        lines.push('');
      }

      // 崩溃日志文件
      lines.push('=== External Log Files ===');
      const externalLog: hiAppEvent.ParamType | undefined = params['external_log'];
      if (externalLog) {
        try {
          const logFiles = externalLog as string[];
          for (const logFile of logFiles) {
            lines.push(`Log File: ${logFile}`);
          }
        } catch (e) {
          lines.push(String(externalLog));
        }
      }
      const logOverLimit = params['log_over_limit'] as boolean;
      lines.push(`Log Over Limit: ${logOverLimit}`);
      lines.push('');
    }

    lines.push('===================================================');
    lines.push('');

    return lines.join('\n');
  }

  /**
   * 格式化日期
   */
  private formatDate(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

  /**
   * 清理旧日志文件，保留最新的MAX_LOG_FILES个
   */
  private async cleanupOldLogs(): Promise<void> {
    try {
      if (!this.logDirPath) {
        return;
      }

      const files: string[] = [];
      const dir = fileIo.listFileSync(this.logDirPath);
      for (const fileName of dir) {
        if (fileName.startsWith(LOG_PREFIX) && fileName.endsWith(LOG_EXT)) {
          files.push(fileName);
        }
      }

      // 按文件名排序（文件名包含时间戳，所以排序即按时间排序）
      files.sort();

      // 删除旧文件
      while (files.length > MAX_LOG_FILES) {
        const oldFile = files.shift();
        if (oldFile) {
          const oldPath = `${this.logDirPath}/${oldFile}`;
          await fileIo.unlink(oldPath);
          hilog.info(DOMAIN, TAG, 'Deleted old crash log: %{public}s', oldFile);
        }
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to cleanup old logs: %{public}s', err.message);
    }
  }

  /**
   * 检查是否存在崩溃日志
   */
  public async hasCrashLog(): Promise<boolean> {
    try {
      if (!this.logDirPath) {
        return false;
      }
      const files = await this.getCrashLogFiles();
      return files.length > 0;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to check crash log: %{public}s', err.message);
      return false;
    }
  }

  /**
   * 获取崩溃日志文件列表
   */
  public async getCrashLogFiles(): Promise<string[]> {
    const files: string[] = [];
    try {
      if (!this.logDirPath) {
        return files;
      }
      const isExist = await fileIo.access(this.logDirPath);
      if (!isExist) {
        return files;
      }

      const dirFiles = fileIo.listFileSync(this.logDirPath);
      for (const fileName of dirFiles) {
        if (fileName.startsWith(LOG_PREFIX) && fileName.endsWith(LOG_EXT)) {
          files.push(fileName);
        }
      }

      // 按时间倒序排序（最新的在前）
      files.sort().reverse();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to get crash log files: %{public}s', err.message);
    }
    return files;
  }

  /**
   * 获取最新崩溃日志文件路径
   */
  public async getLatestCrashLogPath(): Promise<string | null> {
    try {
      const files = await this.getCrashLogFiles();
      if (files.length > 0 && this.logDirPath) {
        return `${this.logDirPath}/${files[0]}`;
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to get latest crash log: %{public}s', err.message);
    }
    return null;
  }

  /**
   * 读取崩溃日志内容
   */
  public async readCrashLog(filePath: string): Promise<string> {
    try {
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(filePath);
      const bufferSize = stat.size;
      const buffer = new ArrayBuffer(bufferSize);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to read crash log: %{public}s', err.message);
      return '';
    }
  }

  /**
   * 清除所有崩溃日志
   */
  public async clearCrashLog(): Promise<boolean> {
    try {
      if (!this.logDirPath) {
        return false;
      }
      const files = await this.getCrashLogFiles();
      for (const fileName of files) {
        const filePath = `${this.logDirPath}/${fileName}`;
        await fileIo.unlink(filePath);
        hilog.info(DOMAIN, TAG, 'Deleted crash log: %{public}s', fileName);
      }
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to clear crash logs: %{public}s', err.message);
      return false;
    }
  }

  /**
   * 删除指定的崩溃日志
   */
  public async deleteCrashLog(fileName: string): Promise<boolean> {
    try {
      if (!this.logDirPath) {
        return false;
      }
      const filePath = `${this.logDirPath}/${fileName}`;
      await fileIo.unlink(filePath);
      hilog.info(DOMAIN, TAG, 'Deleted crash log: %{public}s', fileName);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to delete crash log: %{public}s', err.message);
      return false;
    }
  }
}
