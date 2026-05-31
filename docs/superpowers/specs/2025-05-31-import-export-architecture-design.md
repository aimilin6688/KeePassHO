# 导入导出架构重构设计文档

## 1. 背景

### 1.1 现有问题

当前 KeePassHO 项目的导入导出功能存在以下问题：

| 问题 | 描述 |
|------|------|
| **缺乏格式处理器抽象** | 导入导出格式判断硬编码在服务类中，违反开闭原则 |
| **静态方法滥用** | 所有服务都使用静态方法，难以测试和扩展 |
| **职责混合** | `KdbxCsvService` 同时负责导入和导出 |
| **扩展繁琐** | 新增格式需要修改 8+ 处代码 |
| **UI 层耦合** | UI 直接依赖具体服务实现，难以替换和测试 |

### 1.2 目标

- 高内聚、低耦合：各模块职责单一，通过接口依赖
- 易扩展：新增格式只需添加处理器类并注册，无需修改现有代码
- 可测试：支持依赖注入，便于单元测试
- 兼容性：保留现有功能，平滑迁移

## 2. 设计决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 重构范围 | 完整重构 | 全面优化架构，为未来扩展打好基础 |
| 依赖注入 | 混合方式 | 核心服务使用构造函数注入，处理器通过注册表管理 |
| 处理器组织 | 分离模式 | 导入/导出处理器独立，符合单一职责原则 |
| UI 解耦 | Facade + ViewModel | Facade 封装复杂性，ViewModel 管理 UI 状态 |
| 错误处理 | 混合模式 | 处理器抛异常，Facade 转 Result，ViewModel 处理 UI |
| 文件检测 | 纯扩展名判断 | 简单高效，符合用户导出文件的使用场景 |

## 3. 架构设计

### 3.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                 UI 层                                        │
│                    SettingDatabase.ets / ImportExportPage.ets               │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ 绑定
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ViewModel 层                                    │
│                        ImportExportViewModel.ets                            │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  - isLoading: boolean                - errorMessage: string         │   │
│   │  - importFormats: FormatInfo[]       - exportFormats: FormatInfo[]  │   │
│   │  + executeImport(location): Promise<boolean>                        │   │
│   │  + executeExport(format, location): Promise<boolean>                │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ 调用
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Facade 层                                       │
│                         ImportExportFacade.ets                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  + importToCurrentDatabase(location): Promise<Result<KdbxGroup>>    │   │
│   │  + exportCurrentDatabase(format, location): Promise<Result<void>>   │   │
│   │  + getSupportedImportFormats(): FormatInfo[]                        │   │
│   │  + getSupportedExportFormats(): FormatInfo[]                        │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ 调用
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              服务层                                          │
│   ┌───────────────────────────┐      ┌───────────────────────────┐         │
│   │     ImportService.ets     │      │     ExportService.ets     │         │
│   │  - registry: HandlerReg   │      │  - registry: HandlerReg   │         │
│   │  - fileManager: KdbxFile  │      │  - fileManager: KdbxFile  │         │
│   │  + import(): KdbxGroup    │      │  + export(): void         │         │
│   └───────────────────────────┘      └───────────────────────────┘         │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ 注册/获取
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           处理器注册表                                        │
│                      FormatHandlerRegistry.ets                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  - importHandlers: Map<string, IImportHandler>                      │   │
│   │  - exportHandlers: Map<string, IExportHandler>                      │   │
│   │  + registerImportHandler(handler)                                   │   │
│   │  + registerExportHandler(handler)                                   │   │
│   │  + getImportHandler(ext): IImportHandler                            │   │
│   │  + getExportHandler(ext): IExportHandler                            │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │ 管理
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           处理器层 (Handlers)                                │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                       Import Handlers                                │   │
│   │  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐    │   │
│   │  │XmlImportHandler │ │CsvImportHandler │ │BitwardenImportHandler│    │   │
│   │  └─────────────────┘ └─────────────────┘ └─────────────────────┘    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                       Export Handlers                                │   │
│   │  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐        │   │
│   │  │XmlExportHandler │ │CsvExportHandler │ │KdbxExportHandler│        │   │
│   │  └─────────────────┘ └─────────────────┘ └─────────────────┘        │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 调用链

```
导入: UI → ViewModel → Facade → ImportService → Handler
导出: UI → ViewModel → Facade → ExportService → Handler
```

## 4. 目录结构

```
entry/src/main/ets/services/importExport/
├── common/
│   ├── Result.ets                    # Result 类型定义
│   ├── ImportExportError.ets         # 错误类型定义
│   └── FormatInfo.ets                # 格式信息类型
│
├── interfaces/
│   ├── IImportHandler.ets            # 导入处理器接口
│   └── IExportHandler.ets            # 导出处理器接口
│
├── registry/
│   └── FormatHandlerRegistry.ets     # 处理器注册表
│
├── handlers/
│   ├── import/
│   │   ├── XmlImportHandler.ets      # XML 导入处理器
│   │   ├── CsvImportHandler.ets      # CSV 导入处理器
│   │   └── BitwardenJsonImportHandler.ets  # Bitwarden JSON 导入处理器
│   │
│   └── export/
│       ├── XmlExportHandler.ets      # XML 导出处理器
│       ├── CsvExportHandler.ets      # CSV 导出处理器
│       └── KdbxExportHandler.ets     # KDBX 导出处理器
│
├── service/
│   ├── ImportService.ets             # 导入服务
│   └── ExportService.ets             # 导出服务
│
├── facade/
│   └── ImportExportFacade.ets        # 统一外观服务
│
├── viewmodel/
│   └── ImportExportViewModel.ets     # 视图模型
│
└── index.ets                         # 统一导出
```

## 5. 核心接口定义

### 5.1 IImportHandler 接口

```typescript
// interfaces/IImportHandler.ets
import { KdbxGroup } from 'kdbxweb';
import { FileContentInfo } from '../../../storage';

export interface IImportHandler {
  /**
   * 支持的文件扩展名（含点，如 '.csv'）
   */
  readonly supportedExtensions: string[];

  /**
   * 格式显示名称（用于 UI）
   */
  readonly formatName: string;

  /**
   * 格式唯一标识
   */
  readonly formatId: string;

  /**
   * 判断是否能处理该文件
   * @param extension 文件扩展名
   */
  canHandle(extension: string): boolean;

  /**
   * 执行导入
   * @param fileContent 文件内容
   * @returns 解析后的 KdbxGroup
   * @throws ImportError 导入失败时抛出
   */
  import(fileContent: FileContentInfo): Promise<KdbxGroup>;
}
```

### 5.2 IExportHandler 接口

```typescript
// interfaces/IExportHandler.ets
import { Kdbx } from 'kdbxweb';

export interface IExportHandler {
  /**
   * 支持的文件扩展名
   */
  readonly supportedExtensions: string[];

  /**
   * 格式显示名称
   */
  readonly formatName: string;

  /**
   * 格式唯一标识
   */
  readonly formatId: string;

  /**
   * 默认文件名后缀
   */
  readonly defaultFileName: string;

  /**
   * 判断是否能处理该格式
   */
  canHandle(formatId: string): boolean;

  /**
   * 执行导出
   * @param database 数据库对象
   * @returns 导出的文件内容
   * @throws ExportError 导出失败时抛出
   */
  export(database: Kdbx): Promise<ArrayBuffer>;
}
```

### 5.3 Result 类型

```typescript
// common/Result.ets
export class Result<T> {
  readonly isSuccess: boolean;
  readonly value?: T;
  readonly errorCode?: string;
  readonly errorMessage?: string;

  private constructor(isSuccess: boolean, value?: T, errorCode?: string, errorMessage?: string) {
    this.isSuccess = isSuccess;
    this.value = value;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
  }

  static success<T>(value: T): Result<T> {
    return new Result(true, value);
  }

  static failure<T>(errorCode: string, errorMessage: string): Result<T> {
    return new Result(false, undefined, errorCode, errorMessage);
  }
}
```

### 5.4 错误类型定义

```typescript
// common/ImportExportError.ets
export enum ImportExportErrorCode {
  // 通用错误
  FILE_NOT_FOUND = 'FILE_NOT_FOUND',
  FILE_READ_ERROR = 'FILE_READ_ERROR',
  FILE_WRITE_ERROR = 'FILE_WRITE_ERROR',
  UNSUPPORTED_FORMAT = 'UNSUPPORTED_FORMAT',
  FILE_EMPTY = 'FILE_EMPTY',

  // 导入错误
  INVALID_FILE_FORMAT = 'INVALID_FILE_FORMAT',
  INVALID_CSV_HEADER = 'INVALID_CSV_HEADER',
  INVALID_JSON_FORMAT = 'INVALID_JSON_FORMAT',
  PARSE_ERROR = 'PARSE_ERROR',

  // 导出错误
  EXPORT_FAILED = 'EXPORT_FAILED',
  DATABASE_EMPTY = 'DATABASE_EMPTY',
}

export class ImportError extends Error {
  constructor(
    public readonly code: ImportExportErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'ImportError';
  }
}

export class ExportError extends Error {
  constructor(
    public readonly code: ImportExportErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'ExportError';
  }
}
```

## 6. 格式信息类型

```typescript
// common/FormatInfo.ets
export interface FormatInfo {
  /**
   * 格式唯一标识
   */
  formatId: string;

  /**
   * 格式显示名称（用于 UI 显示）
   */
  formatName: string;

  /**
   * 支持的文件扩展名列表
   */
  extensions: string[];
}
```

## 7. 处理器注册表

```typescript
// registry/FormatHandlerRegistry.ets
import { IImportHandler } from '../interfaces/IImportHandler';
import { IExportHandler } from '../interfaces/IExportHandler';
import { FormatInfo } from '../common/FormatInfo';

export class FormatHandlerRegistry {
  private importHandlers: Map<string, IImportHandler> = new Map();
  private exportHandlers: Map<string, IExportHandler> = new Map();

  // 单例
  private static instance: FormatHandlerRegistry;

  static getInstance(): FormatHandlerRegistry {
    if (!FormatHandlerRegistry.instance) {
      FormatHandlerRegistry.instance = new FormatHandlerRegistry();
    }
    return FormatHandlerRegistry.instance;
  }

  /**
   * 注册导入处理器
   * 同时注册扩展名和格式ID作为键
   */
  registerImportHandler(handler: IImportHandler): void {
    for (const ext of handler.supportedExtensions) {
      this.importHandlers.set(ext.toLowerCase(), handler);
    }
    this.importHandlers.set(handler.formatId, handler);
  }

  /**
   * 注册导出处理器
   */
  registerExportHandler(handler: IExportHandler): void {
    for (const ext of handler.supportedExtensions) {
      this.exportHandlers.set(ext.toLowerCase(), handler);
    }
    this.exportHandlers.set(handler.formatId, handler);
  }

  /**
   * 根据扩展名或格式ID获取导入处理器
   */
  getImportHandler(key: string): IImportHandler | undefined {
    return this.importHandlers.get(key.toLowerCase());
  }

  /**
   * 根据扩展名或格式ID获取导出处理器
   */
  getExportHandler(key: string): IExportHandler | undefined {
    return this.exportHandlers.get(key.toLowerCase());
  }

  /**
   * 获取所有支持的导入格式（去重）
   */
  getSupportedImportFormats(): FormatInfo[] {
    const seen = new Set<string>();
    const result: FormatInfo[] = [];

    for (const handler of this.importHandlers.values()) {
      if (!seen.has(handler.formatId)) {
        seen.add(handler.formatId);
        result.push({
          formatId: handler.formatId,
          formatName: handler.formatName,
          extensions: handler.supportedExtensions
        });
      }
    }
    return result;
  }

  /**
   * 获取所有支持的导出格式（去重）
   */
  getSupportedExportFormats(): FormatInfo[] {
    const seen = new Set<string>();
    const result: FormatInfo[] = [];

    for (const handler of this.exportHandlers.values()) {
      if (!seen.has(handler.formatId)) {
        seen.add(handler.formatId);
        result.push({
          formatId: handler.formatId,
          formatName: handler.formatName,
          extensions: handler.supportedExtensions
        });
      }
    }
    return result;
  }
}
```

## 8. 服务层实现

### 8.1 ImportService

```typescript
// service/ImportService.ets
import { KdbxGroup } from 'kdbxweb';
import { FormatHandlerRegistry } from '../registry/FormatHandlerRegistry';
import { KdbxFileManager } from '../../kdbx/KdbxFileManager';
import { FileContentInfo, StorageType, StorageConfig } from '../../../storage';
import { ImportError, ImportExportErrorCode } from '../common/ImportExportError';

export class ImportService {
  private registry: FormatHandlerRegistry;

  constructor(registry: FormatHandlerRegistry) {
    this.registry = registry;
  }

  /**
   * 导入文件
   * @param filePath 文件路径
   * @param storageType 存储类型
   * @param storageConfig 存储配置
   * @returns 解析后的 KdbxGroup
   */
  async import(
    filePath: string,
    storageType: StorageType,
    storageConfig?: StorageConfig
  ): Promise<KdbxGroup> {
    // 1. 获取文件扩展名
    const extension = this.getExtension(filePath);

    // 2. 查找处理器
    const handler = this.registry.getImportHandler(extension);
    if (!handler) {
      throw new ImportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        `不支持的文件格式: ${extension}`
      );
    }

    // 3. 检查文件是否存在
    const fileManager = new KdbxFileManager(storageType, storageConfig);
    const exists = await fileManager.exists(filePath);
    if (!exists) {
      throw new ImportError(
        ImportExportErrorCode.FILE_NOT_FOUND,
        '文件不存在'
      );
    }

    // 4. 读取文件内容
    const fileContent = await fileManager.read(filePath);

    // 5. 调用处理器解析
    return handler.import(fileContent);
  }

  /**
   * 获取文件扩展名
   */
  getExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    return lastDot !== -1 ? filePath.substring(lastDot).toLowerCase() : '';
  }
}
```

### 8.2 ExportService

```typescript
// service/ExportService.ets
import { Kdbx } from 'kdbxweb';
import { FormatHandlerRegistry } from '../registry/FormatHandlerRegistry';
import { KdbxFileManager } from '../../kdbx/KdbxFileManager';
import { ExportError, ImportExportErrorCode } from '../common/ImportExportError';
import { StorageType, StorageConfig } from '../../../storage';

export class ExportService {
  private registry: FormatHandlerRegistry;

  constructor(registry: FormatHandlerRegistry) {
    this.registry = registry;
  }

  /**
   * 导出数据库
   * @param database 数据库对象
   * @param formatId 导出格式ID
   * @param filePath 保存路径
   * @param storageType 存储类型
   * @param storageConfig 存储配置
   */
  async export(
    database: Kdbx,
    formatId: string,
    filePath: string,
    storageType: StorageType,
    storageConfig?: StorageConfig
  ): Promise<void> {
    // 1. 查找处理器
    const handler = this.registry.getExportHandler(formatId);
    if (!handler) {
      throw new ExportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        `不支持的导出格式: ${formatId}`
      );
    }

    // 2. 生成导出内容
    const content = await handler.export(database);

    // 3. 写入文件
    const fileManager = new KdbxFileManager(storageType, storageConfig);
    await fileManager.write(filePath, content);
  }

  /**
   * 获取导出文件名
   */
  getExportFileName(formatId: string, baseName: string): string {
    const handler = this.registry.getExportHandler(formatId);
    if (!handler || handler.supportedExtensions.length === 0) {
      return `${baseName}.kdbx`;
    }
    return `${baseName}${handler.supportedExtensions[0]}`;
  }
}
```

## 9. Facade 层实现

```typescript
// facade/ImportExportFacade.ets
import { KdbxGroup } from 'kdbxweb';
import { Result } from '../common/Result';
import { ImportExportErrorCode, ImportError, ExportError } from '../common/ImportExportError';
import { ImportService } from '../service/ImportService';
import { ExportService } from '../service/ExportService';
import { FormatHandlerRegistry, FormatInfo } from '../registry/FormatHandlerRegistry';
import { FileService } from '../../FileService';
import { KdbxUtils } from '../../../common/utils';
import { LocationInfo } from '../../beans/LocationParam';

export class ImportExportFacade {
  private importService: ImportService;
  private exportService: ExportService;
  private registry: FormatHandlerRegistry;

  constructor() {
    this.registry = FormatHandlerRegistry.getInstance();
    this.importService = new ImportService(this.registry);
    this.exportService = new ExportService(this.registry);
  }

  /**
   * 导入文件到当前数据库
   */
  async importToCurrentDatabase(location: LocationInfo): Promise<Result<KdbxGroup>> {
    try {
      // 1. 执行导入
      const importedGroup = await this.importService.import(
        location.filePath,
        location.storageType,
        location.storageConfig
      );

      // 2. 合并到当前数据库
      const database = FileService.getDatabase();
      const rootGroup = database.getDefaultGroup();

      // 合并分组
      if (importedGroup.groups && importedGroup.groups.length > 0) {
        for (const group of importedGroup.groups) {
          group.parentGroup = rootGroup;
          rootGroup.groups.push(group);
        }
      }

      // 合并条目
      if (importedGroup.entries && importedGroup.entries.length > 0) {
        for (const entry of importedGroup.entries) {
          entry.parentGroup = rootGroup;
          rootGroup.entries.push(entry);
        }
      }

      // 3. 保存数据库
      await KdbxUtils.saveDatabase();

      return Result.success(importedGroup);
    } catch (error) {
      return this.handleError(error);
    }
  }

  /**
   * 导出当前数据库
   */
  async exportCurrentDatabase(
    formatId: string,
    location: LocationInfo
  ): Promise<Result<void>> {
    try {
      const database = FileService.getDatabase();

      await this.exportService.export(
        database,
        formatId,
        location.filePath,
        location.storageType,
        location.storageConfig
      );

      return Result.success(undefined);
    } catch (error) {
      return this.handleError(error);
    }
  }

  /**
   * 获取支持的导入格式列表
   */
  getSupportedImportFormats(): FormatInfo[] {
    return this.registry.getSupportedImportFormats();
  }

  /**
   * 获取支持的导出格式列表
   */
  getSupportedExportFormats(): FormatInfo[] {
    return this.registry.getSupportedExportFormats();
  }

  /**
   * 获取导出文件名
   */
  getExportFileName(formatId: string, baseName: string): string {
    return this.exportService.getExportFileName(formatId, baseName);
  }

  /**
   * 统一错误处理
   */
  private handleError<T>(error: unknown): Result<T> {
    if (error instanceof ImportError || error instanceof ExportError) {
      return Result.failure(error.code, error.message);
    }
    if (error instanceof Error) {
      return Result.failure(ImportExportErrorCode.PARSE_ERROR, error.message);
    }
    return Result.failure(ImportExportErrorCode.PARSE_ERROR, '未知错误');
  }
}
```

## 10. ViewModel 层实现

```typescript
// viewmodel/ImportExportViewModel.ets
import { Result } from '../common/Result';
import { FormatInfo } from '../registry/FormatHandlerRegistry';
import { ImportExportFacade } from '../facade/ImportExportFacade';
import { LocationInfo } from '../../beans/LocationParam';
import { KdbxGroup } from 'kdbxweb';

export class ImportExportViewModel {
  private facade: ImportExportFacade;

  // UI 状态
  isLoading: boolean = false;
  errorMessage: string = '';
  lastImportedCount: number = 0;

  constructor() {
    this.facade = new ImportExportFacade();
  }

  /**
   * 获取支持的导入格式（用于 UI 下拉选项）
   */
  getImportFormatOptions(): FormatInfo[] {
    return this.facade.getSupportedImportFormats();
  }

  /**
   * 获取支持的导出格式
   */
  getExportFormatOptions(): FormatInfo[] {
    return this.facade.getSupportedExportFormats();
  }

  /**
   * 获取指定格式的文件扩展名
   */
  getFileExtensions(formatId: string): string[] {
    const formats = this.getImportFormatOptions();
    const format = formats.find(f => f.formatId === formatId);
    return format?.extensions || [];
  }

  /**
   * 执行导入
   */
  async executeImport(location: LocationInfo): Promise<boolean> {
    this.isLoading = true;
    this.errorMessage = '';

    const result = await this.facade.importToCurrentDatabase(location);

    this.isLoading = false;

    if (result.isSuccess && result.value) {
      this.lastImportedCount = this.countItems(result.value);
      return true;
    } else {
      this.errorMessage = result.errorMessage || '导入失败';
      return false;
    }
  }

  /**
   * 执行导出
   */
  async executeExport(formatId: string, location: LocationInfo): Promise<boolean> {
    this.isLoading = true;
    this.errorMessage = '';

    const result = await this.facade.exportCurrentDatabase(formatId, location);

    this.isLoading = false;

    if (result.isSuccess) {
      return true;
    } else {
      this.errorMessage = result.errorMessage || '导出失败';
      return false;
    }
  }

  /**
   * 统计导入的条目数量
   */
  private countItems(group: KdbxGroup): number {
    let count = group.entries?.length || 0;
    if (group.groups) {
      for (const subGroup of group.groups) {
        count += this.countItems(subGroup);
      }
    }
    return count;
  }
}
```

## 11. 处理器实现示例

### 11.1 CSV 导入处理器

```typescript
// handlers/import/CsvImportHandler.ets
import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../../interfaces/IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';

export class CsvImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.csv'];
  readonly formatName = 'CSV';
  readonly formatId = 'CSV';

  private static readonly CSV_HEADERS = [
    'Group', 'Title', 'UserName', 'Password', 'URL',
    'Notes', 'TOTP', 'Icon', 'Last Modified', 'Created'
  ];

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);
    const lines = content.split('\n');

    if (lines.length === 0) {
      throw new ImportError(ImportExportErrorCode.FILE_EMPTY, '文件为空');
    }

    const headerMap = this.parseHeader(lines[0]);
    const rootGroup = new KdbxGroup();

    for (let i = 1; i < lines.length; i++) {
      if (!lines[i].trim()) continue;
      const entry = this.parseEntry(lines[i], headerMap, rootGroup);
      rootGroup.entries.push(entry);
    }

    return rootGroup;
  }

  private parseHeader(headerLine: string): Map<string, number> {
    const headers = headerLine.split(',');
    const map = new Map<string, number>();

    for (let i = 0; i < headers.length; i++) {
      const header = headers[i].trim();
      map.set(header, i);
    }

    return map;
  }

  private parseEntry(
    line: string,
    headerMap: Map<string, number>,
    parentGroup: KdbxGroup
  ): KdbxEntry {
    const fields = line.split(',');
    const db = FileService.getDatabase();
    const entry = KdbxEntry.create(db.meta, parentGroup);

    this.setField(entry, headerMap, fields, 'Title');
    this.setField(entry, headerMap, fields, 'UserName');
    this.setField(entry, headerMap, fields, 'Password', true);
    this.setField(entry, headerMap, fields, 'URL');
    this.setField(entry, headerMap, fields, 'Notes');

    return entry;
  }

  private setField(
    entry: KdbxEntry,
    headerMap: Map<string, number>,
    fields: string[],
    fieldName: string,
    protected: boolean = false
  ): void {
    const idx = headerMap.get(fieldName);
    if (idx !== undefined && fields[idx]) {
      entry.setField(fieldName, fields[idx], protected);
    }
  }
}
```

### 11.2 Bitwarden JSON 导入处理器

```typescript
// handlers/import/BitwardenJsonImportHandler.ets
import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../../interfaces/IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';

// Bitwarden JSON 类型定义
interface BitwardenExport {
  encrypted?: boolean;
  folders?: Array<{ id: string; name: string }>;
  items: BitwardenItem[];
}

interface BitwardenItem {
  id: string;
  folderId?: string;
  type: number;
  name: string;
  notes?: string;
  favorite?: boolean;
  fields?: Array<{ name: string; value: string; type: number }>;
  login?: {
    username?: string;
    password?: string;
    uris?: Array<{ uri: string }>;
    totp?: string;
  };
  card?: {
    cardholderName?: string;
    brand?: string;
    number?: string;
    expMonth?: string;
    expYear?: string;
    code?: string;
  };
}

export class BitwardenJsonImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.json'];
  readonly formatName = 'Bitwarden JSON';
  readonly formatId = 'BITWARDEN_JSON';

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);

    let data: BitwardenExport;
    try {
      data = JSON.parse(content);
    } catch {
      throw new ImportError(ImportExportErrorCode.INVALID_JSON_FORMAT, 'JSON 格式无效');
    }

    if (data.encrypted) {
      throw new ImportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        '不支持加密的 Bitwarden 导出文件，请导出为未加密的 JSON'
      );
    }

    const rootGroup = new KdbxGroup();
    rootGroup.name = 'Bitwarden Import';

    // 构建文件夹映射
    const folderMap = new Map<string, string>();
    data.folders?.forEach(f => folderMap.set(f.id, f.name));

    // 按文件夹分组处理条目
    const groupCache = new Map<string, KdbxGroup>();

    for (const item of data.items) {
      const folderName = folderMap.get(item.folderId || '') || '';
      const targetGroup = this.getOrCreateGroup(rootGroup, folderName, groupCache);

      const entry = this.createEntry(item, targetGroup);
      targetGroup.entries.push(entry);
    }

    return rootGroup;
  }

  private getOrCreateGroup(
    root: KdbxGroup,
    path: string,
    cache: Map<string, KdbxGroup>
  ): KdbxGroup {
    if (!path) return root;
    if (cache.has(path)) return cache.get(path)!;

    const group = KdbxGroup.create(path, root);
    root.groups.push(group);
    cache.set(path, group);

    return group;
  }

  private createEntry(item: BitwardenItem, parent: KdbxGroup): KdbxEntry {
    const db = FileService.getDatabase();
    const entry = KdbxEntry.create(db.meta, parent);

    entry.setField('Title', item.name);
    if (item.notes) entry.setField('Notes', item.notes);

    // 登录类型 (type=1)
    if (item.type === 1 && item.login) {
      entry.setField('UserName', item.login.username || '');
      entry.setField('Password', item.login.password || '', true);

      if (item.login.uris?.length) {
        entry.setField('URL', item.login.uris.map(u => u.uri).join('\n'));
      }
      if (item.login.totp) {
        entry.setField('TOTP', item.login.totp, true);
      }
    }

    // 银行卡类型 (type=3)
    if (item.type === 3 && item.card) {
      entry.setField('Cardholder', item.card.cardholderName || '');
      entry.setField('Number', item.card.number || '', true);
      entry.setField('Expiry', `${item.card.expMonth || ''}/${item.card.expYear || ''}`);
      entry.setField('CVV', item.card.code || '', true);
    }

    // 自定义字段
    item.fields?.forEach(f => {
      const isProtected = f.type === 1;
      entry.setField(f.name, f.value, isProtected);
    });

    return entry;
  }
}
```

### 11.3 XML 导出处理器

```typescript
// handlers/export/XmlExportHandler.ets
import { Kdbx, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

export class XmlExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.xml'];
  readonly formatName = 'XML';
  readonly formatId = 'XML';
  readonly defaultFileName = 'export.xml';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      const xmlContent = await database.saveXml(true, true);
      return ByteUtils.stringToBuffer(xmlContent);
    } catch (error) {
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `XML 导出失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
```

## 12. 统一导出与注册

```typescript
// index.ets

// 公共类型
export { Result } from './common/Result';
export { ImportError, ExportError, ImportExportErrorCode } from './common/ImportExportError';
export type { FormatInfo } from './common/FormatInfo';

// 接口
export type { IImportHandler } from './interfaces/IImportHandler';
export type { IExportHandler } from './interfaces/IExportHandler';

// 注册表
export { FormatHandlerRegistry } from './registry/FormatHandlerRegistry';

// 服务
export { ImportService } from './service/ImportService';
export { ExportService } from './service/ExportService';

// Facade
export { ImportExportFacade } from './facade/ImportExportFacade';

// ViewModel
export { ImportExportViewModel } from './viewmodel/ImportExportViewModel';

// 导入处理器
export { CsvImportHandler } from './handlers/import/CsvImportHandler';
export { XmlImportHandler } from './handlers/import/XmlImportHandler';
export { BitwardenJsonImportHandler } from './handlers/import/BitwardenJsonImportHandler';

// 导出处理器
export { CsvExportHandler } from './handlers/export/CsvExportHandler';
export { XmlExportHandler } from './handlers/export/XmlExportHandler';
export { KdbxExportHandler } from './handlers/export/KdbxExportHandler';

/**
 * 注册默认处理器
 * 应在应用启动时调用一次
 */
export function registerDefaultHandlers(): void {
  const registry = FormatHandlerRegistry.getInstance();

  // 注册导入处理器
  registry.registerImportHandler(new CsvImportHandler());
  registry.registerImportHandler(new XmlImportHandler());
  registry.registerImportHandler(new BitwardenJsonImportHandler());

  // 注册导出处理器
  registry.registerExportHandler(new CsvExportHandler());
  registry.registerExportHandler(new XmlExportHandler());
  registry.registerExportHandler(new KdbxExportHandler());
}
```

## 13. UI 层使用示例

```typescript
// pages/setting/SettingDatabase.ets
import {
  ImportExportViewModel,
  registerDefaultHandlers,
  FormatInfo
} from '../../services/importExport';
import { LocationParam, LocationInfo, LocationMode } from '../../services/beans/LocationParam';
import { CommonUtils } from '../../common/utils';

@Entry
@Component
struct SettingDatabase {
  @State importFormats: FormatInfo[] = [];
  @State exportFormats: FormatInfo[] = [];
  @State isLoading: boolean = false;

  private viewModel: ImportExportViewModel = new ImportExportViewModel();

  aboutToAppear(): void {
    // 注册处理器（通常在应用启动时调用一次）
    registerDefaultHandlers();

    // 获取支持的格式
    this.importFormats = this.viewModel.getImportFormatOptions();
    this.exportFormats = this.viewModel.getExportFormatOptions();
  }

  private startImport(formatId: string): void {
    const extensions = this.viewModel.getFileExtensions(formatId);

    LocationParam.of({
      mode: LocationMode.SELECT,
      fileSuffix: extensions,
      onLocation: (location: LocationInfo) => this.doImport(location)
    });
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  private async doImport(location: LocationInfo): Promise<void> {
    this.isLoading = true;

    const success = await this.viewModel.executeImport(location);
    this.isLoading = false;

    if (success) {
      CommonUtils.showToast(`导入成功，共 ${this.viewModel.lastImportedCount} 条记录`);
      CommonUtils.back();
    } else {
      CommonUtils.showToast(this.viewModel.errorMessage);
    }
  }

  private startExport(formatId: string): void {
    LocationParam.of({
      mode: LocationMode.SAVE,
      fileName: this.viewModel.facade.getExportFileName(formatId, 'export'),
      onLocation: (location: LocationInfo) => this.doExport(formatId, location)
    });
    CommonUtils.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  private async doExport(formatId: string, location: LocationInfo): Promise<void> {
    this.isLoading = true;

    const success = await this.viewModel.executeExport(formatId, location);
    this.isLoading = false;

    if (success) {
      CommonUtils.showToast('导出成功');
      CommonUtils.back();
    } else {
      CommonUtils.showToast(this.viewModel.errorMessage);
    }
  }

  // ... build() 方法
}
```

## 14. 现有功能迁移计划

### 14.1 迁移步骤

1. **创建新目录结构**
   - 创建 `services/importExport/` 目录及子目录

2. **实现核心接口和类型**
   - `Result.ets`
   - `ImportExportError.ets`
   - `IImportHandler.ets`
   - `IExportHandler.ets`
   - `FormatHandlerRegistry.ets`

3. **迁移现有处理器**
   - 将 `KdbxCsvService` 拆分为 `CsvImportHandler` 和 `CsvExportHandler`
   - 创建 `XmlImportHandler` 和 `XmlExportHandler`
   - 创建 `KdbxExportHandler`

4. **实现服务层**
   - `ImportService.ets`
   - `ExportService.ets`

5. **实现 Facade 和 ViewModel**
   - `ImportExportFacade.ets`
   - `ImportExportViewModel.ets`

6. **更新 UI 层**
   - 修改 `SettingDatabase.ets` 使用新架构

7. **添加 Bitwarden 支持**
   - 创建 `BitwardenJsonImportHandler.ets`

8. **清理旧代码**
   - 标记 `KdbxImportService` 为废弃
   - 标记 `KdbxExportService` 为废弃
   - 标记 `KdbxCsvService` 为废弃

### 14.2 向后兼容性保证（重要）

**核心原则：现有导入导出功能必须完全不受影响**

#### 14.2.1 兼容性策略

采用**并行运行、逐步切换**的策略：

```
阶段1: 新旧并存
┌─────────────────────────────────────────────────────────┐
│  UI (SettingDatabase.ets)                               │
│     │                                                   │
│     ├──► 旧代码路径 (KdbxImportService/KdbxExportService)│
│     │    └──► 现有功能，保持不变                         │
│     │                                                   │
│     └──► 新代码路径 (ImportExportViewModel)              │
│          └──► 新功能，通过开关控制                        │
└─────────────────────────────────────────────────────────┘

阶段2: 功能验证通过后切换
┌─────────────────────────────────────────────────────────┐
│  UI (SettingDatabase.ets)                               │
│     │                                                   │
│     └──► 新代码路径 (ImportExportViewModel)              │
│          └──► 完全替代旧功能                             │
│                                                          │
│  旧代码保留但标记 @deprecated，供紧急回退                 │
└─────────────────────────────────────────────────────────┘
```

#### 14.2.2 旧代码处理方式

**保留原有类和方法，不做任何修改：**

```typescript
// services/kdbx/KdbxImportService.ets - 保持原样
export class KdbxImportService {
  private static readonly EXPORT_TYPES = ['.kdbx', '.xml', '.csv'];

  public static importDatabase(inputType?: ExportType) {
    // 原有实现完全保留
  }

  // ... 其他原有方法
}

// services/kdbx/KdbxExportService.ets - 保持原样
export class KdbxExportService {
  public static exportDatabase(exportType: ExportType) {
    // 原有实现完全保留
  }

  // ... 其他原有方法
}

// services/kdbx/KdbxCsvService.ets - 保持原样
export class KdbxCsvService {
  public static async import(csvFile: FileContentInfo): Promise<KdbxGroup> {
    // 原有实现完全保留
  }

  public static async export(database: Kdbx): Promise<ArrayBuffer> {
    // 原有实现完全保留
  }
}
```

#### 14.2.3 功能开关控制

通过 `SettingsService` 控制使用新旧架构：

```typescript
// services/SettingsService.ets 中添加
private static readonly KEY_USE_NEW_IMPORT_EXPORT = 'use_new_import_export';

public isUseNewImportExport(): boolean {
  return this.getSetting(SettingsService.KEY_USE_NEW_IMPORT_EXPORT, false);
}

public setUseNewImportExport(value: boolean): void {
  this.setSetting(SettingsService.KEY_USE_NEW_IMPORT_EXPORT, value);
}
```

#### 14.2.4 UI 层适配

```typescript
// pages/setting/SettingDatabase.ets
import { KdbxImportService } from '../../services/kdbx/KdbxImportService';
import { KdbxExportService } from '../../services/kdbx/KdbxExportService';
import { ImportExportViewModel, registerDefaultHandlers } from '../../services/importExport';

@Entry
@Component
struct SettingDatabase {
  private viewModel: ImportExportViewModel = new ImportExportViewModel();
  @State useNewArchitecture: boolean = false;

  aboutToAppear(): void {
    // 根据开关决定使用哪个架构
    this.useNewArchitecture = SettingsService.getInstance().isUseNewImportExport();

    if (this.useNewArchitecture) {
      registerDefaultHandlers();
    }
  }

  // 导入功能
  private importDatabase(formatId: string): void {
    if (this.useNewArchitecture) {
      // 新架构
      this.startImportNew(formatId);
    } else {
      // 旧架构 - 完全保持原有调用方式
      const exportType = this.convertToExportType(formatId);
      KdbxImportService.importDatabase(exportType);
    }
  }

  // 导出功能
  private exportDatabase(formatId: string): void {
    if (this.useNewArchitecture) {
      // 新架构
      this.startExportNew(formatId);
    } else {
      // 旧架构 - 完全保持原有调用方式
      const exportType = this.convertToExportType(formatId);
      KdbxExportService.exportDatabase(exportType);
    }
  }

  private convertToExportType(formatId: string): ExportType {
    switch (formatId) {
      case 'XML': return ExportType.XML;
      case 'CSV': return ExportType.CSV;
      case 'KDBX': return ExportType.KDBX;
      default: return ExportType.XML;
    }
  }

  // ... 其他方法
}
```

#### 14.2.5 验证清单

重构完成后必须验证以下功能正常工作：

| 功能 | 验证点 | 优先级 |
|------|--------|--------|
| CSV 导入 | 导入 KeePass 导出的 CSV 文件 | P0 |
| CSV 导出 | 导出为 CSV 格式 | P0 |
| XML 导入 | 导入 KeePass XML 格式文件 | P0 |
| XML 导出 | 导出为 XML 格式 | P0 |
| KDBX 导出 | 导出为 KDBX 格式 | P0 |
| 文件选择 | 本地文件选择功能 | P0 |
| 云存储 | WebDAV/OneDrive/FTP 导入导出 | P1 |
| 错误处理 | 文件不存在、格式错误等提示 | P1 |
| 进度显示 | Loading 对话框显示 | P2 |

#### 14.2.6 回滚方案

如果新架构出现问题，可以快速回滚：

1. 将 `SettingsService` 中的 `use_new_import_export` 设为 `false`
2. 用户立即恢复使用旧架构
3. 无需重新发布应用即可切换

#### 14.2.7 废弃计划

旧代码的废弃时间线：

| 阶段 | 时间 | 操作 |
|------|------|------|
| 阶段1 | 重构完成 | 保留旧代码，添加 `@deprecated` 注释 |
| 阶段2 | 1个月后 | 如果新架构稳定，在文档中标记旧代码计划移除 |
| 阶段3 | 3个月后 | 评估是否移除旧代码，或继续保留作为备用 |

```typescript
/**
 * @deprecated 请使用 ImportExportViewModel 替代
 * 该类将在未来版本中移除
 */
export class KdbxImportService {
  // ...
}
```

## 15. 扩展新格式指南

### 15.1 新增导入格式

1. 创建新的处理器类，实现 `IImportHandler` 接口：

```typescript
// handlers/import/NewFormatImportHandler.ets
export class NewFormatImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.newfmt'];
  readonly formatName = 'New Format';
  readonly formatId = 'NEW_FORMAT';

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    // 解析逻辑
  }
}
```

2. 在 `registerDefaultHandlers()` 中注册：

```typescript
registry.registerImportHandler(new NewFormatImportHandler());
```

### 15.2 新增导出格式

流程相同，实现 `IExportHandler` 接口并注册即可。

## 16. 测试策略

### 16.1 单元测试

| 测试对象 | 测试内容 |
|---------|---------|
| `FormatHandlerRegistry` | 注册、查找、去重 |
| `ImportService` | 格式匹配、文件读取、错误处理 |
| `ExportService` | 格式匹配、文件写入、错误处理 |
| `ImportExportFacade` | Result 转换、流程协调 |
| 各 Handler | 格式解析正确性、边界情况 |

### 16.2 集成测试

- 完整导入流程测试
- 完整导出流程测试
- UI 交互测试

## 17. 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 迁移过程中功能回归 | 保留旧代码，逐步迁移，对比测试 |
| 性能影响 | Handler 实例复用，避免重复创建 |
| UI 层改动影响用户体验 | 保持 UI 接口不变，仅替换内部实现 |

## 18. 时间估算

| 阶段 | 预估时间 |
|------|---------|
| 核心接口与类型 | 2-3 小时 |
| 注册表实现 | 1-2 小时 |
| 迁移现有处理器 | 3-4 小时 |
| 服务层实现 | 2-3 小时 |
| Facade 和 ViewModel | 2-3 小时 |
| 功能开关与兼容性适配 | 2-3 小时 |
| UI 层适配（双架构支持） | 3-4 小时 |
| Bitwarden 支持 | 2-3 小时 |
| 单元测试 | 3-4 小时 |
| 集成测试与兼容性验证 | 4-5 小时 |
| **总计** | **24-34 小时** |

## 19. 实施优先级

| 优先级 | 任务 | 说明 |
|--------|------|------|
| P0 | 核心接口与注册表 | 架构基础 |
| P0 | CSV/XML 导入导出处理器 | 迁移现有功能 |
| P0 | 功能开关实现 | 保证兼容性 |
| P0 | UI 双架构支持 | 现有功能不受影响 |
| P1 | 服务层和 Facade | 业务逻辑 |
| P1 | ViewModel | UI 状态管理 |
| P2 | Bitwarden 导入支持 | 新功能 |
| P2 | KDBX 导出处理器 | 迁移现有功能 |
| P3 | 旧代码废弃标记 | 稳定后执行 |
