# 导入导出架构重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构导入导出架构，实现高内聚、低耦合、易扩展的处理器模式，支持 CSV/XML/KDBX 格式和新增 Bitwarden JSON 导入。

**Architecture:** 4层架构 - UI → ViewModel → Facade → Service → Handler。使用处理器接口和注册表模式实现格式扩展。

**Tech Stack:** ArkTS, kdbxweb, HarmonyOS

---

## 文件结构

### 新建文件

| 文件路径 | 职责 |
|---------|------|
| `services/importExport/common/Result.ets` | Result 类型定义 |
| `services/importExport/common/ImportExportError.ets` | 错误类型定义 |
| `services/importExport/common/FormatInfo.ets` | 格式信息接口 |
| `services/importExport/interfaces/IImportHandler.ets` | 导入处理器接口 |
| `services/importExport/interfaces/IExportHandler.ets` | 导出处理器接口 |
| `services/importExport/registry/FormatHandlerRegistry.ets` | 处理器注册表 |
| `services/importExport/handlers/import/CsvImportHandler.ets` | CSV 导入处理器 |
| `services/importExport/handlers/import/XmlImportHandler.ets` | XML 导入处理器 |
| `services/importExport/handlers/import/BitwardenJsonImportHandler.ets` | Bitwarden 导入处理器 |
| `services/importExport/handlers/export/CsvExportHandler.ets` | CSV 导出处理器 |
| `services/importExport/handlers/export/XmlExportHandler.ets` | XML 导出处理器 |
| `services/importExport/handlers/export/KdbxExportHandler.ets` | KDBX 导出处理器 |
| `services/importExport/handlers/export/KeyFileExportHandler.ets` | 密钥文件导出处理器 |
| `services/importExport/service/ImportService.ets` | 导入服务 |
| `services/importExport/service/ExportService.ets` | 导出服务 |
| `services/importExport/facade/ImportExportFacade.ets` | 统一外观服务 |
| `services/importExport/viewmodel/ImportExportViewModel.ets` | 视图模型 |
| `services/importExport/index.ets` | 统一导出和注册函数 |

### 修改文件

| 文件路径 | 修改内容 |
|---------|---------|
| `pages/setting/SettingDatabase.ets` | 替换为使用新架构 |

### 删除文件

| 文件路径 | 说明 |
|---------|------|
| `services/kdbx/KdbxImportService.ets` | 被新架构替代 |
| `services/kdbx/KdbxExportService.ets` | 被新架构替代 |
| `services/kdbx/KdbxCsvService.ets` | 被新架构替代 |

---

## Task 1: 创建目录结构和基础类型

**Files:**
- Create: `services/importExport/common/Result.ets`
- Create: `services/importExport/common/ImportExportError.ets`
- Create: `services/importExport/common/FormatInfo.ets`

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p entry/src/main/ets/services/importExport/common
mkdir -p entry/src/main/ets/services/importExport/interfaces
mkdir -p entry/src/main/ets/services/importExport/registry
mkdir -p entry/src/main/ets/services/importExport/handlers/import
mkdir -p entry/src/main/ets/services/importExport/handlers/export
mkdir -p entry/src/main/ets/services/importExport/service
mkdir -p entry/src/main/ets/services/importExport/facade
mkdir -p entry/src/main/ets/services/importExport/viewmodel
```

- [ ] **Step 2: 创建 Result 类型**

```typescript
// services/importExport/common/Result.ets

/**
 * 操作结果封装类
 */
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

  /**
   * 创建成功结果
   */
  static success<T>(value: T): Result<T> {
    return new Result(true, value);
  }

  /**
   * 创建失败结果
   */
  static failure<T>(errorCode: string, errorMessage: string): Result<T> {
    return new Result(false, undefined, errorCode, errorMessage);
  }
}
```

- [ ] **Step 3: 创建错误类型定义**

```typescript
// services/importExport/common/ImportExportError.ets

/**
 * 导入导出错误码
 */
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

/**
 * 导入错误
 */
export class ImportError extends Error {
  constructor(
    public readonly code: ImportExportErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'ImportError';
  }
}

/**
 * 导出错误
 */
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

- [ ] **Step 4: 创建格式信息接口**

```typescript
// services/importExport/common/FormatInfo.ets

/**
 * 格式信息
 */
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

- [ ] **Step 5: 提交基础类型**

```bash
git add entry/src/main/ets/services/importExport/common/
git commit -m "feat(importExport): 添加基础类型 Result、ImportExportError、FormatInfo

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: 创建处理器接口

**Files:**
- Create: `services/importExport/interfaces/IImportHandler.ets`
- Create: `services/importExport/interfaces/IExportHandler.ets`

- [ ] **Step 1: 创建导入处理器接口**

```typescript
// services/importExport/interfaces/IImportHandler.ets

import { KdbxGroup } from 'kdbxweb';
import { FileContentInfo } from '../../../storage';

/**
 * 导入处理器接口
 */
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

- [ ] **Step 2: 创建导出处理器接口**

```typescript
// services/importExport/interfaces/IExportHandler.ets

import { Kdbx } from 'kdbxweb';

/**
 * 导出处理器接口
 */
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
   * 默认文件名
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

- [ ] **Step 3: 提交处理器接口**

```bash
git add entry/src/main/ets/services/importExport/interfaces/
git commit -m "feat(importExport): 添加导入导出处理器接口 IImportHandler、IExportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: 创建处理器注册表

**Files:**
- Create: `services/importExport/registry/FormatHandlerRegistry.ets`

- [ ] **Step 1: 创建处理器注册表**

```typescript
// services/importExport/registry/FormatHandlerRegistry.ets

import { IImportHandler } from '../interfaces/IImportHandler';
import { IExportHandler } from '../interfaces/IExportHandler';
import { FormatInfo } from '../common/FormatInfo';

/**
 * 格式处理器注册表
 */
export class FormatHandlerRegistry {
  private importHandlers: Map<string, IImportHandler> = new Map();
  private exportHandlers: Map<string, IExportHandler> = new Map();

  private static instance: FormatHandlerRegistry;

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): FormatHandlerRegistry {
    if (!FormatHandlerRegistry.instance) {
      FormatHandlerRegistry.instance = new FormatHandlerRegistry();
    }
    return FormatHandlerRegistry.instance;
  }

  /**
   * 注册导入处理器
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

- [ ] **Step 2: 提交注册表**

```bash
git add entry/src/main/ets/services/importExport/registry/
git commit -m "feat(importExport): 添加处理器注册表 FormatHandlerRegistry

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: 创建 CSV 导入处理器

**Files:**
- Create: `services/importExport/handlers/import/CsvImportHandler.ets`

- [ ] **Step 1: 创建 CSV 导入处理器**

```typescript
// services/importExport/handlers/import/CsvImportHandler.ets

import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../../interfaces/IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';

/**
 * CSV 标题枚举
 */
enum CsvTitle {
  Group = "Group",
  Title = "Title",
  Username = "UserName",
  Password = "Password",
  URL = "URL",
  Notes = "Notes",
  TOTP = "TOTP",
  Icon = "Icon",
  Last_Modified = "Last Modified",
  Created = "Created"
}

/**
 * CSV 导入处理器
 */
export class CsvImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.csv'];
  readonly formatName = 'CSV';
  readonly formatId = 'CSV';

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
    const groupCache = new Map<string, KdbxGroup>();

    // 获取字段保护设置
    const fieldProtection = this.createFieldProtection();

    for (let i = 1; i < lines.length; i++) {
      if (!lines[i].trim()) continue;

      const line = this.parseCsvLine(lines[i]);
      const entry = this.parseEntry(line, headerMap, rootGroup, groupCache, fieldProtection);
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

    // 验证必须的标题
    const requiredHeaders = [CsvTitle.Title];
    for (const required of requiredHeaders) {
      if (!map.has(required)) {
        throw new ImportError(
          ImportExportErrorCode.INVALID_CSV_HEADER,
          `缺少必须的列: ${required}`
        );
      }
    }

    return map;
  }

  private parseCsvLine(line: string): string[] {
    const result: string[] = [];
    let current = '';
    let inQuotes = false;

    for (let i = 0; i < line.length; i++) {
      const char = line[i];

      if (char === '"') {
        if (inQuotes && line[i + 1] === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char === ',' && !inQuotes) {
        result.push(current);
        current = '';
      } else {
        current += char;
      }
    }
    result.push(current);

    return result;
  }

  private createFieldProtection(): Map<string, boolean> {
    const db = FileService.getDatabase();
    const protection = db?.meta?.memoryProtection;

    return new Map<string, boolean>([
      [CsvTitle.Title, protection?.title || false],
      [CsvTitle.Username, protection?.userName || false],
      [CsvTitle.Password, protection?.password || true],
      [CsvTitle.URL, protection?.url || false],
      [CsvTitle.Notes, protection?.notes || false],
      [CsvTitle.TOTP, true]
    ]);
  }

  private parseEntry(
    fields: string[],
    headerMap: Map<string, number>,
    rootGroup: KdbxGroup,
    groupCache: Map<string, KdbxGroup>,
    fieldProtection: Map<string, boolean>
  ): KdbxEntry {
    // 获取或创建分组
    const groupIndex = headerMap.get(CsvTitle.Group);
    let parentGroup = rootGroup;

    if (groupIndex !== undefined && fields[groupIndex]) {
      parentGroup = this.getOrCreateGroup(rootGroup, fields[groupIndex], groupCache);
    }

    const db = FileService.getDatabase();
    const entry = KdbxEntry.create(db.meta, parentGroup);

    // 设置各字段
    this.setField(entry, headerMap, fields, CsvTitle.Title, false);
    this.setField(entry, headerMap, fields, CsvTitle.Username, fieldProtection.get(CsvTitle.Username));
    this.setField(entry, headerMap, fields, CsvTitle.Password, true);
    this.setField(entry, headerMap, fields, CsvTitle.URL, fieldProtection.get(CsvTitle.URL));
    this.setField(entry, headerMap, fields, CsvTitle.Notes, fieldProtection.get(CsvTitle.Notes));
    this.setField(entry, headerMap, fields, CsvTitle.TOTP, true);

    // 设置图标
    const iconIndex = headerMap.get(CsvTitle.Icon);
    if (iconIndex !== undefined && fields[iconIndex]) {
      const icon = parseInt(fields[iconIndex]);
      if (!isNaN(icon)) {
        entry.icon = icon;
      }
    }

    return entry;
  }

  private getOrCreateGroup(
    rootGroup: KdbxGroup,
    groupPath: string,
    cache: Map<string, KdbxGroup>
  ): KdbxGroup {
    if (!groupPath || groupPath === '') {
      return rootGroup;
    }

    if (cache.has(groupPath)) {
      return cache.get(groupPath)!;
    }

    let currentGroup = rootGroup;
    const parts = groupPath.split('/');

    for (const part of parts) {
      if (!part) continue;

      let found = currentGroup.groups.find(g => g.name === part);

      if (!found) {
        found = KdbxGroup.create(part, currentGroup);
        currentGroup.groups.push(found);
      }

      currentGroup = found;
    }

    cache.set(groupPath, currentGroup);
    return currentGroup;
  }

  private setField(
    entry: KdbxEntry,
    headerMap: Map<string, number>,
    fields: string[],
    fieldName: string,
    protected: boolean = false
  ): void {
    const idx = headerMap.get(fieldName);
    if (idx !== undefined && idx < fields.length && fields[idx]) {
      entry.setField(fieldName, fields[idx], protected);
    }
  }
}
```

- [ ] **Step 2: 提交 CSV 导入处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/import/CsvImportHandler.ets
git commit -m "feat(importExport): 添加 CSV 导入处理器 CsvImportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: 创建 XML 导入处理器

**Files:**
- Create: `services/importExport/handlers/import/XmlImportHandler.ets`

- [ ] **Step 1: 创建 XML 导入处理器**

```typescript
// services/importExport/handlers/import/XmlImportHandler.ets

import { KdbxGroup, Kdbx, KdbxCredentials, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../../interfaces/IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';

/**
 * XML 导入处理器
 */
export class XmlImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.xml'];
  readonly formatName = 'XML';
  readonly formatId = 'XML';

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);

    if (!content || content.trim().length === 0) {
      throw new ImportError(ImportExportErrorCode.FILE_EMPTY, '文件为空');
    }

    try {
      const kdbx = await Kdbx.loadXml(content, new KdbxCredentials(null));
      return kdbx.getDefaultGroup();
    } catch (error) {
      if (error instanceof ImportError) {
        throw error;
      }
      throw new ImportError(
        ImportExportErrorCode.INVALID_FILE_FORMAT,
        `XML 解析失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
```

- [ ] **Step 2: 提交 XML 导入处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/import/XmlImportHandler.ets
git commit -m "feat(importExport): 添加 XML 导入处理器 XmlImportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: 创建 Bitwarden JSON 导入处理器

**Files:**
- Create: `services/importExport/handlers/import/BitwardenJsonImportHandler.ets`

- [ ] **Step 1: 创建 Bitwarden JSON 导入处理器**

```typescript
// services/importExport/handlers/import/BitwardenJsonImportHandler.ets

import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../../interfaces/IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';

/**
 * Bitwarden JSON 类型定义
 */
interface BitwardenFolder {
  id: string;
  name: string;
}

interface BitwardenField {
  name: string;
  value: string;
  type: number;
}

interface BitwardenLogin {
  username?: string;
  password?: string;
  uris?: Array<{ uri: string; match?: number }>;
  totp?: string;
  fv2?: string;
}

interface BitwardenCard {
  cardholderName?: string;
  brand?: string;
  number?: string;
  expMonth?: string;
  expYear?: string;
  code?: string;
}

interface BitwardenIdentity {
  title?: string;
  firstName?: string;
  middleName?: string;
  lastName?: string;
  username?: string;
  company?: string;
  ssn?: string;
  passportNumber?: string;
  email?: string;
  phone?: string;
  address1?: string;
  address2?: string;
  address3?: string;
  city?: string;
  state?: string;
  postalCode?: string;
  country?: string;
}

interface BitwardenItem {
  id: string;
  organizationId?: string;
  folderId?: string;
  type: number;
  name: string;
  notes?: string;
  favorite?: boolean;
  fields?: BitwardenField[];
  login?: BitwardenLogin;
  card?: BitwardenCard;
  identity?: BitwardenIdentity;
  secureNote?: object;
  passwordHistory?: Array<{ lastUsedDate: string; password: string }>;
  collectionIds?: string[];
  revisionDate?: string;
  creationDate?: string;
}

interface BitwardenExport {
  encrypted?: boolean;
  folders?: BitwardenFolder[];
  items: BitwardenItem[];
}

/**
 * Bitwarden JSON 导入处理器
 */
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

    // 检查是否加密
    if (data.encrypted === true) {
      throw new ImportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        '不支持加密的 Bitwarden 导出文件，请导出为未加密的 JSON'
      );
    }

    // 检查是否有条目
    if (!data.items || data.items.length === 0) {
      throw new ImportError(ImportExportErrorCode.FILE_EMPTY, '导出文件中没有条目');
    }

    const rootGroup = new KdbxGroup();
    rootGroup.name = 'Bitwarden Import';

    // 构建文件夹映射
    const folderMap = new Map<string, string>();
    if (data.folders) {
      for (const folder of data.folders) {
        folderMap.set(folder.id, folder.name);
      }
    }

    // 分组缓存
    const groupCache = new Map<string, KdbxGroup>();

    // 处理所有条目
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
    if (!path || path === '') {
      return root;
    }

    if (cache.has(path)) {
      return cache.get(path)!;
    }

    let currentGroup = root;
    const parts = path.split('/');

    for (const part of parts) {
      if (!part) continue;

      let found = currentGroup.groups.find(g => g.name === part);

      if (!found) {
        found = KdbxGroup.create(part, currentGroup);
        currentGroup.groups.push(found);
      }

      currentGroup = found;
    }

    cache.set(path, currentGroup);
    return currentGroup;
  }

  private createEntry(item: BitwardenItem, parent: KdbxGroup): KdbxEntry {
    const db = FileService.getDatabase();
    const entry = KdbxEntry.create(db.meta, parent);

    // 设置标题
    entry.setField('Title', item.name || '');

    // 设置备注
    if (item.notes) {
      entry.setField('Notes', item.notes);
    }

    // 根据类型处理
    switch (item.type) {
      case 1: // Login
        this.fillLoginEntry(entry, item);
        break;
      case 2: // Secure Note
        entry.icon = 44; // Note icon
        break;
      case 3: // Card
        this.fillCardEntry(entry, item);
        break;
      case 4: // Identity
        this.fillIdentityEntry(entry, item);
        break;
    }

    // 处理自定义字段
    if (item.fields && item.fields.length > 0) {
      this.fillCustomFields(entry, item.fields);
    }

    // 处理收藏标记
    if (item.favorite) {
      entry.setField('Favorite', 'true');
    }

    return entry;
  }

  private fillLoginEntry(entry: KdbxEntry, item: BitwardenItem): void {
    if (!item.login) return;

    entry.setField('UserName', item.login.username || '');
    entry.setField('Password', item.login.password || '', true);

    // 处理多个 URL
    if (item.login.uris && item.login.uris.length > 0) {
      const urls = item.login.uris.map(u => u.uri).join('\n');
      entry.setField('URL', urls);
    }

    // TOTP
    if (item.login.totp) {
      entry.setField('TOTP', item.login.totp, true);
    }

    entry.icon = 0; // Key icon
  }

  private fillCardEntry(entry: KdbxEntry, item: BitwardenItem): void {
    if (!item.card) return;

    entry.setField('Title', `[Card] ${item.name}`);
    entry.setField('Cardholder Name', item.card.cardholderName || '');
    entry.setField('Brand', item.card.brand || '');
    entry.setField('Number', item.card.number || '', true);
    entry.setField('Exp Month', item.card.expMonth || '');
    entry.setField('Exp Year', item.card.expYear || '');
    entry.setField('CVV', item.card.code || '', true);

    entry.icon = 66; // Money icon
  }

  private fillIdentityEntry(entry: KdbxEntry, item: BitwardenItem): void {
    if (!item.identity) return;

    entry.setField('Title', `[Identity] ${item.name}`);

    const fullName = [
      item.identity.firstName,
      item.identity.middleName,
      item.identity.lastName
    ].filter(n => n).join(' ');
    entry.setField('Full Name', fullName);

    entry.setField('First Name', item.identity.firstName || '');
    entry.setField('Last Name', item.identity.lastName || '');
    entry.setField('Email', item.identity.email || '');
    entry.setField('Phone', item.identity.phone || '');
    entry.setField('Company', item.identity.company || '');

    const address = [
      item.identity.address1,
      item.identity.address2,
      item.identity.address3
    ].filter(a => a).join(', ');
    entry.setField('Address', address);

    entry.setField('City', item.identity.city || '');
    entry.setField('State', item.identity.state || '');
    entry.setField('Postal Code', item.identity.postalCode || '');
    entry.setField('Country', item.identity.country || '');
    entry.setField('SSN', item.identity.ssn || '', true);
    entry.setField('Passport Number', item.identity.passportNumber || '', true);

    entry.icon = 9; // Identity icon
  }

  private fillCustomFields(entry: KdbxEntry, fields: BitwardenField[]): void {
    for (const field of fields) {
      if (!field.name || !field.value) continue;

      const isProtected = field.type === 1; // Hidden type
      entry.setField(field.name, field.value, isProtected);
    }
  }
}
```

- [ ] **Step 2: 提交 Bitwarden 导入处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/import/BitwardenJsonImportHandler.ets
git commit -m "feat(importExport): 添加 Bitwarden JSON 导入处理器

支持导入:
- 登录条目 (用户名、密码、URL、TOTP)
- 银行卡条目
- 身份信息条目
- 自定义字段
- 分组结构

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: 创建 CSV 导出处理器

**Files:**
- Create: `services/importExport/handlers/export/CsvExportHandler.ets`

- [ ] **Step 1: 创建 CSV 导出处理器**

```typescript
// services/importExport/handlers/export/CsvExportHandler.ets

import { Kdbx, KdbxEntry, KdbxGroup, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { KdbxUtils } from '../../../common/utils';
import util from '@ohos.util';

/**
 * CSV 标题枚举
 */
enum CsvTitle {
  Group = "Group",
  Title = "Title",
  Username = "UserName",
  Password = "Password",
  URL = "URL",
  Notes = "Notes",
  TOTP = "TOTP",
  Icon = "Icon",
  Last_Modified = "Last Modified",
  Created = "Created"
}

/**
 * CSV 导出处理器
 */
export class CsvExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.csv'];
  readonly formatName = 'CSV';
  readonly formatId = 'CSV';
  readonly defaultFileName = 'export.csv';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      const rootGroup = database.getDefaultGroup();
      const entries = rootGroup.allEntries();

      if (entries.length === 0) {
        throw new ExportError(ImportExportErrorCode.DATABASE_EMPTY, '数据库为空，没有可导出的条目');
      }

      let csvContent = '';

      // 添加标题行
      const titles = Object.values(CsvTitle).join(',');
      csvContent += titles + '\n';

      // 遍历所有条目
      for (const entry of entries) {
        const groupPath = KdbxUtils.getGroupPath(entry.parentGroup);
        const row = this.createCsvRow(entry, groupPath);
        csvContent += row + '\n';
      }

      // 转换为 ArrayBuffer
      const encoder = new util.TextEncoder();
      return encoder.encodeInto(csvContent).buffer;
    } catch (error) {
      if (error instanceof ExportError) {
        throw error;
      }
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `CSV 导出失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }

  private createCsvRow(entry: KdbxEntry, groupPath: string): string {
    const title = this.getFieldValue(entry, 'Title');
    const username = this.getFieldValue(entry, 'UserName');
    const password = this.getFieldValue(entry, 'Password');
    const url = this.getFieldValue(entry, 'URL');
    const notes = this.getFieldValue(entry, 'Notes');
    const totp = this.getTotpFieldValue(entry);
    const icon = entry.icon !== undefined ? entry.icon.toString() : '0';
    const lastModified = entry.times.lastModTime?.toISOString() || '';
    const created = entry.times.creationTime?.toISOString() || '';

    const row = [
      this.escapeCsvField(groupPath),
      this.escapeCsvField(title),
      this.escapeCsvField(username),
      this.escapeCsvField(password),
      this.escapeCsvField(url),
      this.escapeCsvField(notes),
      this.escapeCsvField(totp),
      this.escapeCsvField(icon),
      this.escapeCsvField(lastModified),
      this.escapeCsvField(created)
    ];

    return row.join(',');
  }

  private getFieldValue(entry: KdbxEntry, fieldName: string): string {
    const field = entry.fields.get(fieldName);
    if (!field) {
      return '';
    }

    if (typeof field === 'string') {
      return field;
    } else {
      // ProtectedValue 类型
      return field.getText();
    }
  }

  private getTotpFieldValue(entry: KdbxEntry): string {
    for (const field of entry.fields) {
      const value = KdbxUtils.getValueString(field[1]);
      if (KdbxUtils.isTotpUrl(value)) {
        return value;
      }
    }
    return '';
  }

  private escapeCsvField(field: string): string {
    if (!field) {
      return '';
    }

    // 如果字段包含逗号、双引号或换行符，需要用双引号包围
    if (field.includes(',') || field.includes('"') || field.includes('\n')) {
      return '"' + field.replace(/"/g, '""') + '"';
    }

    return field;
  }
}
```

- [ ] **Step 2: 提交 CSV 导出处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/export/CsvExportHandler.ets
git commit -m "feat(importExport): 添加 CSV 导出处理器 CsvExportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: 创建 XML 导出处理器

**Files:**
- Create: `services/importExport/handlers/export/XmlExportHandler.ets`

- [ ] **Step 1: 创建 XML 导出处理器**

```typescript
// services/importExport/handlers/export/XmlExportHandler.ets

import { Kdbx, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

/**
 * XML 导出处理器
 */
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

- [ ] **Step 2: 提交 XML 导出处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/export/XmlExportHandler.ets
git commit -m "feat(importExport): 添加 XML 导出处理器 XmlExportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: 创建 KDBX 导出处理器

**Files:**
- Create: `services/importExport/handlers/export/KdbxExportHandler.ets`

- [ ] **Step 1: 创建 KDBX 导出处理器**

```typescript
// services/importExport/handlers/export/KdbxExportHandler.ets

import { Kdbx } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

/**
 * KDBX 导出处理器
 */
export class KdbxExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.kdbx'];
  readonly formatName = 'KDBX';
  readonly formatId = 'KDBX';
  readonly defaultFileName = 'export.kdbx';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      return await database.save();
    } catch (error) {
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `KDBX 导出失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
```

- [ ] **Step 2: 提交 KDBX 导出处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/export/KdbxExportHandler.ets
git commit -m "feat(importExport): 添加 KDBX 导出处理器 KdbxExportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: 创建密钥文件导出处理器

**Files:**
- Create: `services/importExport/handlers/export/KeyFileExportHandler.ets`

- [ ] **Step 1: 创建密钥文件导出处理器**

```typescript
// services/importExport/handlers/export/KeyFileExportHandler.ets

import { Kdbx, KdbxCredentials, ByteUtils } from 'kdbxweb';
import { IExportHandler } from '../../interfaces/IExportHandler';
import { ExportError, ImportExportErrorCode } from '../../common/ImportExportError';

/**
 * 密钥文件导出处理器
 */
export class KeyFileExportHandler implements IExportHandler {
  readonly supportedExtensions = ['.key', '.keyx'];
  readonly formatName = 'Key File';
  readonly formatId = 'KEY_FILE';
  readonly defaultFileName = 'keyfile.key';

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    try {
      const keyBytes = await KdbxCredentials.createRandomKeyFile();
      return ByteUtils.bytesToBuffer(keyBytes);
    } catch (error) {
      throw new ExportError(
        ImportExportErrorCode.EXPORT_FAILED,
        `密钥文件生成失败: ${error instanceof Error ? error.message : '未知错误'}`
      );
    }
  }
}
```

- [ ] **Step 2: 提交密钥文件导出处理器**

```bash
git add entry/src/main/ets/services/importExport/handlers/export/KeyFileExportHandler.ets
git commit -m "feat(importExport): 添加密钥文件导出处理器 KeyFileExportHandler

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 11: 创建导入服务

**Files:**
- Create: `services/importExport/service/ImportService.ets`

- [ ] **Step 1: 创建导入服务**

```typescript
// services/importExport/service/ImportService.ets

import { KdbxGroup } from 'kdbxweb';
import { FormatHandlerRegistry } from '../registry/FormatHandlerRegistry';
import { KdbxFileManager } from '../../kdbx/KdbxFileManager';
import { ImportError, ImportExportErrorCode } from '../common/ImportExportError';
import { StorageType, StorageConfig } from '../../../storage';

/**
 * 导入服务
 */
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

- [ ] **Step 2: 提交导入服务**

```bash
git add entry/src/main/ets/services/importExport/service/ImportService.ets
git commit -m "feat(importExport): 添加导入服务 ImportService

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 12: 创建导出服务

**Files:**
- Create: `services/importExport/service/ExportService.ets`

- [ ] **Step 1: 创建导出服务**

```typescript
// services/importExport/service/ExportService.ets

import { Kdbx } from 'kdbxweb';
import { FormatHandlerRegistry } from '../registry/FormatHandlerRegistry';
import { KdbxFileManager } from '../../kdbx/KdbxFileManager';
import { ExportError, ImportExportErrorCode } from '../common/ImportExportError';
import { StorageType, StorageConfig } from '../../../storage';
import { DateUtils, FilenameUtils } from '../../../common/utils';
import { FileService } from '../../FileService';

/**
 * 导出服务
 */
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
   * @param formatId 格式ID
   * @param baseName 基础文件名
   * @param appendDate 是否追加日期
   */
  getExportFileName(formatId: string, baseName: string, appendDate: boolean = true): string {
    const handler = this.registry.getExportHandler(formatId);
    const nowTime = DateUtils.getCurrentDate();
    let fileName = baseName || nowTime;

    if (handler && handler.supportedExtensions.length > 0) {
      fileName = FilenameUtils.replaceExt(fileName, handler.supportedExtensions[0]);
    } else {
      fileName = FilenameUtils.replaceExt(fileName, '.kdbx');
    }

    if (appendDate && fileName !== nowTime) {
      fileName = FilenameUtils.fileNameAppendDate(fileName);
    }

    return fileName;
  }
}
```

- [ ] **Step 2: 提交导出服务**

```bash
git add entry/src/main/ets/services/importExport/service/ExportService.ets
git commit -m "feat(importExport): 添加导出服务 ExportService

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 13: 创建 Facade 层

**Files:**
- Create: `services/importExport/facade/ImportExportFacade.ets`

- [ ] **Step 1: 创建 Facade 层**

```typescript
// services/importExport/facade/ImportExportFacade.ets

import { KdbxGroup } from 'kdbxweb';
import { Result } from '../common/Result';
import { ImportExportErrorCode, ImportError, ExportError } from '../common/ImportExportError';
import { ImportService } from '../service/ImportService';
import { ExportService } from '../service/ExportService';
import { FormatHandlerRegistry, FormatInfo } from '../registry/FormatHandlerRegistry';
import { FileService } from '../../FileService';
import { KdbxUtils } from '../../../common/utils';
import { LocationInfo } from '../../beans/LocationParam';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';

/**
 * 导入导出外观服务
 */
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
      await this.saveDatabase();

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
   * 保存数据库
   */
  private saveDatabase(): Promise<void> {
    return new Promise((resolve, reject) => {
      KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
        onSuccess: () => resolve(),
        onError: (message: string) => reject(new Error(message))
      }));
    });
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

- [ ] **Step 2: 提交 Facade 层**

```bash
git add entry/src/main/ets/services/importExport/facade/ImportExportFacade.ets
git commit -m "feat(importExport): 添加导入导出外观服务 ImportExportFacade

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 14: 创建 ViewModel 层

**Files:**
- Create: `services/importExport/viewmodel/ImportExportViewModel.ets`

- [ ] **Step 1: 创建 ViewModel 层**

```typescript
// services/importExport/viewmodel/ImportExportViewModel.ets

import { Result } from '../common/Result';
import { FormatInfo } from '../common/FormatInfo';
import { ImportExportFacade } from '../facade/ImportExportFacade';
import { LocationInfo } from '../../beans/LocationParam';
import { KdbxGroup } from 'kdbxweb';
import { FileService } from '../../FileService';
import { DateUtils } from '../../../common/utils';

/**
 * 导入导出视图模型
 */
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
   * 获取导出文件名
   */
  getExportFileName(formatId: string): string {
    const dbFileParam = FileService.getDbFileParam();
    const baseName = dbFileParam?.fileName || DateUtils.getCurrentDate();
    return this.facade.getExportFileName(formatId, baseName);
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

- [ ] **Step 2: 提交 ViewModel 层**

```bash
git add entry/src/main/ets/services/importExport/viewmodel/ImportExportViewModel.ets
git commit -m "feat(importExport): 添加导入导出视图模型 ImportExportViewModel

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 15: 创建统一导出和注册函数

**Files:**
- Create: `services/importExport/index.ets`

- [ ] **Step 1: 创建统一导出文件**

```typescript
// services/importExport/index.ets

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
export { KeyFileExportHandler } from './handlers/export/KeyFileExportHandler';

import { FormatHandlerRegistry } from './registry/FormatHandlerRegistry';
import { CsvImportHandler } from './handlers/import/CsvImportHandler';
import { XmlImportHandler } from './handlers/import/XmlImportHandler';
import { BitwardenJsonImportHandler } from './handlers/import/BitwardenJsonImportHandler';
import { CsvExportHandler } from './handlers/export/CsvExportHandler';
import { XmlExportHandler } from './handlers/export/XmlExportHandler';
import { KdbxExportHandler } from './handlers/export/KdbxExportHandler';
import { KeyFileExportHandler } from './handlers/export/KeyFileExportHandler';

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
  registry.registerExportHandler(new KeyFileExportHandler());
}
```

- [ ] **Step 2: 提交统一导出文件**

```bash
git add entry/src/main/ets/services/importExport/index.ets
git commit -m "feat(importExport): 添加统一导出和注册函数

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 16: 修改 UI 层使用新架构

**Files:**
- Modify: `pages/setting/SettingDatabase.ets`

- [ ] **Step 1: 读取当前 UI 文件**

读取文件以了解当前实现。

- [ ] **Step 2: 修改导入部分**

将原来的导入替换为新架构：

```typescript
// 删除旧的导入
// import { KdbxExportService } from '../../services/kdbx/KdbxExportService';
// import { KdbxImportService } from '../../services/kdbx/KdbxImportService';

// 使用新架构
import {
  ImportExportViewModel,
  registerDefaultHandlers,
  FormatInfo
} from '../../services/importExport';
import { LocationParam, LocationInfo, LocationMode } from '../../services/beans/LocationParam';
import { CommonUtils } from '../../common/utils';
```

- [ ] **Step 3: 修改类成员**

```typescript
@Entry
@Component
struct SettingsDatabase {
  @State isDatabaseValid: boolean = false;
  @State algorithmType: ResourceStr = ResourceManager.getString($r("app.string.please_select"));

  // 新架构
  @State importFormats: FormatInfo[] = [];
  @State exportFormats: FormatInfo[] = [];
  @State isLoading: boolean = false;

  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
  private viewModel: ImportExportViewModel = new ImportExportViewModel();
```

- [ ] **Step 4: 修改 aboutToAppear 方法**

```typescript
aboutToAppear(): void {
  // 注册处理器
  registerDefaultHandlers();

  // 获取支持的格式
  this.importFormats = this.viewModel.getImportFormatOptions();
  this.exportFormats = this.viewModel.getExportFormatOptions();
}
```

- [ ] **Step 5: 修改导入导出方法**

```typescript
// 导入数据库
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
    CommonUtils.back({ url: "pages/setting/SettingDatabase" });
  } else {
    CommonUtils.showToast(this.viewModel.errorMessage);
  }
}

// 导出数据库
private startExport(formatId: string): void {
  const fileName = this.viewModel.getExportFileName(formatId);

  LocationParam.of({
    mode: LocationMode.SAVE,
    fileName: fileName,
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
    CommonUtils.back({ url: "pages/setting/SettingDatabase" });
  } else {
    CommonUtils.showToast(this.viewModel.errorMessage);
  }
}
```

- [ ] **Step 6: 修改 build 方法中的导入导出 UI**

更新导入导出选项的下拉框，使用新的格式列表：

```typescript
// 数据库导入
ListItem() {
  Row() {
    Text($r("app.string.Settings_database_import"))
      .fontSize(16)
      .flexGrow(1)
    Blank()
    Column() {
      Select(this.importFormats.map(f => ({ value: f.formatName, formatId: f.formatId })))
        .value($r("app.string.please_select"))
        .font({ size: 16 })
        .selectedOptionFont({ size: 16 })
        .optionFont({ size: 16 })
        .backgroundColor($r("app.color.card_bg"))
        .onSelect(async (index: number) => {
          this.startImport(this.importFormats[index].formatId);
        })
        .padding({ right: 0 })
    }
    .width('70%')
    .alignItems(HorizontalAlign.End)
  }
  .width('100%')
  .padding({
    left: 16,
    right: 16,
    top: 9,
    bottom: 9
  })
}

// 数据库导出
ListItem() {
  Row() {
    Text($r("app.string.Settings_database_export"))
      .fontSize(16)
      .flexGrow(1)
    Blank()
    Column() {
      Select(this.exportFormats.map(f => ({ value: f.formatName, formatId: f.formatId })))
        .value($r("app.string.please_select"))
        .font({ size: 16 })
        .selectedOptionFont({ size: 16 })
        .optionFont({ size: 16 })
        .backgroundColor($r("app.color.card_bg"))
        .onSelect(async (index: number) => {
          this.startExport(this.exportFormats[index].formatId);
        })
        .padding({ right: 0 })
    }
    .width('70%')
    .alignItems(HorizontalAlign.End)
  }
  .width('100%')
  .padding({
    left: 16,
    right: 16,
    top: 9,
    bottom: 9
  })
}
```

- [ ] **Step 7: 提交 UI 层修改**

```bash
git add entry/src/main/ets/pages/setting/SettingDatabase.ets
git commit -m "refactor(setting): 使用新的导入导出架构替换旧实现

- 使用 ImportExportViewModel 管理 UI 状态
- 支持动态获取导入导出格式列表
- 新增 Bitwarden JSON 导入支持

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 17: 删除旧代码

**Files:**
- Delete: `services/kdbx/KdbxImportService.ets`
- Delete: `services/kdbx/KdbxExportService.ets`
- Delete: `services/kdbx/KdbxCsvService.ets`

- [ ] **Step 1: 删除旧的导入服务**

```bash
rm entry/src/main/ets/services/kdbx/KdbxImportService.ets
```

- [ ] **Step 2: 删除旧的导出服务**

```bash
rm entry/src/main/ets/services/kdbx/KdbxExportService.ets
```

- [ ] **Step 3: 删除旧的 CSV 服务**

```bash
rm entry/src/main/ets/services/kdbx/KdbxCsvService.ets
```

- [ ] **Step 4: 检查是否有其他文件引用这些旧服务**

```bash
grep -r "KdbxImportService\|KdbxExportService\|KdbxCsvService" entry/src/main/ets/ --include="*.ets"
```

如果有引用，需要更新这些文件。

- [ ] **Step 5: 提交删除旧代码**

```bash
git add -A
git commit -m "refactor: 删除旧的导入导出服务类

删除的文件:
- KdbxImportService.ets
- KdbxExportService.ets
- KdbxCsvService.ets

被新架构 importExport 模块替代

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 18: 编译验证

**Files:**
- None

- [ ] **Step 1: 执行编译**

```bash
cd /Users/liujunguang1/workspace/code/other/harmony/KeePassHO/kee-pass-ho
hvigorw --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```

- [ ] **Step 2: 检查编译错误**

如果编译失败，检查并修复错误。

- [ ] **Step 3: 提交最终状态**

```bash
git add -A
git commit -m "fix: 修复编译错误

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 19: 功能验证清单

**Files:**
- None

- [ ] **验证 CSV 导入**
  - 导出数据库为 CSV 格式
  - 重新导入 CSV 文件
  - 检查条目和分组是否正确

- [ ] **验证 CSV 导出**
  - 导出数据库为 CSV 格式
  - 用文本编辑器打开检查内容

- [ ] **验证 XML 导入**
  - 导出数据库为 XML 格式
  - 重新导入 XML 文件
  - 检查条目是否完整

- [ ] **验证 XML 导出**
  - 导出数据库为 XML 格式
  - 用文本编辑器打开检查内容

- [ ] **验证 KDBX 导出**
  - 导出数据库为 KDBX 格式
  - 用其他 KeePass 客户端打开验证

- [ ] **验证 Bitwarden JSON 导入**
  - 从 Bitwarden 导出 JSON 文件
  - 导入到当前数据库
  - 检查条目和分组是否正确

- [ ] **验证错误处理**
  - 尝试导入不存在的文件
  - 尝试导入格式错误的文件
  - 检查错误提示是否正确

---

## 自检清单

**1. Spec 覆盖检查:**

| 规格要求 | 对应任务 |
|---------|---------|
| IImportHandler 接口 | Task 2 |
| IExportHandler 接口 | Task 2 |
| FormatHandlerRegistry | Task 3 |
| CsvImportHandler | Task 4 |
| XmlImportHandler | Task 5 |
| BitwardenJsonImportHandler | Task 6 |
| CsvExportHandler | Task 7 |
| XmlExportHandler | Task 8 |
| KdbxExportHandler | Task 9 |
| KeyFileExportHandler | Task 10 |
| ImportService | Task 11 |
| ExportService | Task 12 |
| ImportExportFacade | Task 13 |
| ImportExportViewModel | Task 14 |
| UI 层替换 | Task 16 |
| 删除旧代码 | Task 17 |

**2. 占位符检查:** 无 TBD、TODO 等占位符

**3. 类型一致性检查:**
- `FormatInfo` 接口在 `common/FormatInfo.ets` 定义，在各处使用一致
- `IImportHandler.import()` 返回 `Promise<KdbxGroup>`
- `IExportHandler.export()` 返回 `Promise<ArrayBuffer>`
- `Result<T>` 类的静态方法签名一致
