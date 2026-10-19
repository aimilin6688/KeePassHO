import { DbFileParam } from '../TypeDefined';
import { EventBus } from '../EventBus';

/**
 * 多库注册表中单条打开记录：会话参数 + 来源标记（主库 / 子库）
 */
export class OpenDatabaseRecord {
  /** 库标识键（storageType::filePath） */
  readonly iocKey: string;
  /** 该库的内存会话参数（同一对象贯穿加载/保存/切换生命周期） */
  readonly dbFileParam: DbFileParam;
  /**
   * 是否为子库（由父库 AutoOpen/KeeAutoExec 触发打开）；主库为 false。
   * 子库不写入最近文件列表、不作为默认保存目标
   */
  isChild: boolean;

  constructor(iocKey: string, dbFileParam: DbFileParam, isChild: boolean) {
    this.iocKey = iocKey;
    this.dbFileParam = dbFileParam;
    this.isChild = isChild;
  }
}

/**
 * 注册表 put() 选项
 */
export class PutDatabaseOptions {
  /** 是否切换为当前库（默认 true）；false 时仅登记不切换，注册表为空时兜底成为当前库 */
  makeCurrent: boolean;
  /** 是否标记为子库（默认 false） */
  isChild: boolean;

  constructor(makeCurrent: boolean = true, isChild: boolean = false) {
    this.makeCurrent = makeCurrent;
    this.isChild = isChild;
  }
}

/**
 * 多库注册表（M2）：所有已打开数据库会话的唯一事实来源。
 *
 * - 记录键（iocKey）= storageType::filePath，同键 put 视为同一库的会话更新（保留 isChild 标记）
 * - currentKey 指向当前库；remove 当前库时自动切换到首个剩余库（插入序），最后一个库移除后回到空态
 * - attempted 集合记录本会话已尝试打开的库（含失败），用于 AutoOpen 触发循环防护
 *   （对齐 kp2a App._openAttempts：失败也计入，避免反复重试同一不可打开的子库）
 */
export class DatabaseRegistry {
  /**
   * 当前库变更事件：currentKey 实际发生变化时发射（数据为新 currentKey，可能为 null）
   * 数据库视图等监听方据此重载展示内容
   */
  static readonly EVENT_CURRENT_DATABASE_CHANGED: string = 'current_database_changed';

  private records: Map<string, OpenDatabaseRecord> = new Map<string, OpenDatabaseRecord>();
  /** 本会话内已尝试打开的库（AutoOpen 触发循环防护）：与记录独立，未成功登记记录的失败尝试也计入 */
  private attempted: Set<string> = new Set<string>();
  private currentKey: string | null = null;

  /**
   * 构造库标识键
   * @param storageType 存储类型（字符串枚举值）
   * @param filePath 文件路径
   */
  static buildIocKey(storageType: string | undefined, filePath: string | undefined): string {
    return `${storageType ?? ''}::${filePath ?? ''}`;
  }

  /**
   * 从会话参数构造库标识键
   */
  static iocKeyOf(dbFileParam: DbFileParam): string {
    return DatabaseRegistry.buildIocKey(dbFileParam.storageType, dbFileParam.filePath);
  }

  /**
   * 变更当前库指针；实际变化时广播 EVENT_CURRENT_DATABASE_CHANGED
   */
  private switchCurrentTo(newKey: string | null): void {
    if (this.currentKey === newKey) {
      return;
    }
    this.currentKey = newKey;
    EventBus.emit(DatabaseRegistry.EVENT_CURRENT_DATABASE_CHANGED, newKey);
  }

  /**
   * 登记一个已打开的数据库会话
   * - 同键重复 put：替换会话参数对象，保留原记录的 isChild 标记（子库身份不因会话更新丢失）
   * - makeCurrent 默认 true；显式 false 且注册表已有当前库时不切换；注册表为空时兜底成为当前库
   * @returns 创建/更新的记录
   */
  put(dbFileParam: DbFileParam, options?: PutDatabaseOptions): OpenDatabaseRecord {
    const key = DatabaseRegistry.iocKeyOf(dbFileParam);
    const existing = this.records.get(key);
    const isChild = existing !== undefined ? existing.isChild : (options?.isChild ?? false);
    const record = new OpenDatabaseRecord(key, dbFileParam, isChild);
    this.records.set(key, record);
    if (options?.makeCurrent ?? true) {
      this.switchCurrentTo(key);
    } else if (this.currentKey === null) {
      this.switchCurrentTo(key);
    }
    return record;
  }

  /**
   * 按键取会话参数
   */
  get(iocKey: string): DbFileParam | undefined {
    return this.records.get(iocKey)?.dbFileParam;
  }

  /**
   * 按键取完整记录（含 isChild 标记）
   */
  getRecord(iocKey: string): OpenDatabaseRecord | undefined {
    return this.records.get(iocKey);
  }

  /**
   * 当前库键；空注册表返回 null
   */
  getCurrentKey(): string | null {
    return this.currentKey;
  }

  /**
   * 当前库会话参数；空注册表返回 undefined
   */
  getCurrent(): DbFileParam | undefined {
    if (this.currentKey === null) {
      return undefined;
    }
    return this.records.get(this.currentKey)?.dbFileParam;
  }

  /**
   * 切换当前库
   * @returns 键存在返回 true；键不存在返回 false（当前库不变）
   */
  setCurrent(iocKey: string): boolean {
    if (!this.records.has(iocKey)) {
      return false;
    }
    this.switchCurrentTo(iocKey);
    return true;
  }

  /**
   * 是否已登记指定库
   */
  has(iocKey: string): boolean {
    return this.records.has(iocKey);
  }

  /**
   * 指定库是否为子库（未登记返回 false）
   */
  isChild(iocKey: string): boolean {
    return this.records.get(iocKey)?.isChild === true;
  }

  /**
   * 移除一个库记录
   * - 移除的是当前库时：自动切换到首个剩余库（插入序）；最后一个库移除后回到空态
   * @returns 被移除库的会话参数；键不存在返回 undefined
   */
  remove(iocKey: string): DbFileParam | undefined {
    const record = this.records.get(iocKey);
    if (record === undefined) {
      return undefined;
    }
    this.records.delete(iocKey);
    if (this.currentKey === iocKey) {
      let firstKey: string | null = null;
      for (const key of this.records.keys()) {
        firstKey = key;
        break;
      }
      this.switchCurrentTo(firstKey);
    }
    return record.dbFileParam;
  }

  /**
   * 全部记录（插入序）
   */
  all(): OpenDatabaseRecord[] {
    const list: OpenDatabaseRecord[] = [];
    for (const record of this.records.values()) {
      list.push(record);
    }
    return list;
  }

  /**
   * 已登记的库数量
   */
  size(): number {
    return this.records.size;
  }

  /**
   * 标记本会话已尝试打开指定库（AutoOpen 触发循环防护：成功或失败均应在发起尝试前标记）
   */
  markAttempted(iocKey: string): void {
    this.attempted.add(iocKey);
  }

  /**
   * 本会话是否已尝试打开过指定库
   */
  wasAttempted(iocKey: string): boolean {
    return this.attempted.has(iocKey);
  }

  /**
   * 清空尝试记录（不影响已打开的库记录）
   */
  clearAttempted(): void {
    this.attempted.clear();
  }

  /**
   * 移除单个库的尝试标记（手动打开前允许重试失败的子库）
   */
  removeAttempted(iocKey: string): void {
    this.attempted.delete(iocKey);
  }

  /**
   * 清空注册表：记录、尝试标记、当前库指针全部复位（锁库 / 关闭全部数据库）
   */
  clear(): void {
    this.records.clear();
    this.attempted.clear();
    this.switchCurrentTo(null);
  }
}
