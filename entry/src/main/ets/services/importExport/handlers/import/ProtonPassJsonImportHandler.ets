import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';
import { ResourceManager, KdbxUtils } from '../../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'ProtonPassJsonImportHandler';
const DOMAIN = 0xFF00;

/**
 * Proton Pass JSON 导出原始结构（明文 PPMv1）
 */
interface ProtonPassExportRaw {
  encrypted?: boolean;
  vaults?: Record<string, ProtonVaultRaw>;
  items?: ProtonItemRaw[];
}

interface ProtonVaultRaw {
  name?: string;
  description?: string;
  items?: ProtonItemRaw[];
}

interface ProtonItemRaw {
  uuid?: string;
  shareId?: string;
  vaultId?: string;
  pinned?: boolean;
  state?: number;
  createTime?: number;
  modifyTime?: number;
  data?: ProtonItemDataRaw;
}

interface ProtonItemDataRaw {
  type?: string;
  metadata?: ProtonMetadataRaw;
  content?: Record<string, Object>;
  extraFields?: ProtonExtraFieldRaw[];
}

interface ProtonMetadataRaw {
  name?: string;
  note?: string;
}

interface ProtonExtraFieldRaw {
  fieldName?: string;
  type?: string;
  data?: ProtonExtraFieldDataRaw;
}

interface ProtonExtraFieldDataRaw {
  content?: string;
  totpUri?: string;
}

/**
 * Proton Pass JSON 导入处理器（报告 §三/§六 规格，语义对齐 KeePassXC ProtonPassReader）
 * 两种条目载体：vaults（vaultId→{name,items[]}）内嵌条目（KeePassXC 路径，优先）；
 * 顶层 items[] + shareId 解析 vault 分组（vaults 无内嵌条目时回落，防重复导入）。
 * data.type 分派：login/creditCard/wifi/sshKey；custom/note 仅元数据；
 * 未知类型备注加前缀并把 content 标量字段转自定义字段（content_*）。
 */
export class ProtonPassJsonImportHandler implements IImportHandler {
  readonly supportedExtensions = ['.json'];
  readonly formatId = 'PROTONPASS_JSON';
  readonly formatName = 'Proton Pass JSON';

  /** 未知类型 content_* 收集的标量字段（数组字段 urls 无法无损转字符串，跳过） */
  private static readonly CONTENT_FIELD_NAMES: string[] = [
    'itemUsername', 'itemEmail', 'password', 'totpUri',
    'number', 'verificationNumber', 'cardholderName', 'pin', 'expirationDate',
    'ssid', 'security', 'publicKey', 'privateKey'
  ];

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);

    let data: ProtonPassExportRaw;
    try {
      data = JSON.parse(content);
    } catch {
      throw new ImportError(
        ImportExportErrorCode.INVALID_JSON_FORMAT,
        ResourceManager.getString($r('app.string.import_export_invalid_format'))
      );
    }

    if (data.encrypted === true) {
      hilog.error(DOMAIN, TAG, 'Encrypted Proton Pass export not supported');
      throw new ImportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        ResourceManager.getString($r('app.string.import_export_encrypted_not_supported'))
      );
    }

    const rootGroup = new KdbxGroup();
    const groupCache = new Map<string, KdbxGroup>();
    const vaultNameMap = new Map<string, string>();
    let vaultItemCount = 0;
    let topLevelItemCount = 0;

    // 1) vaults 内嵌条目（KeePassXC 路径）
    if (data.vaults !== undefined && data.vaults !== null) {
      const vaultIds = Object.keys(data.vaults);
      for (const vaultId of vaultIds) {
        const vault = data.vaults[vaultId];
        if (vault === undefined || vault === null) {
          continue;
        }
        const vaultName = vault.name ?? '';
        vaultNameMap.set(vaultId, vaultName);
        const vaultGroup = ProtonPassJsonImportHandler.getOrCreateGroup(
          rootGroup, vaultName, vault.description ?? '', groupCache);
        const items = vault.items;
        if (items === undefined || items === null) {
          continue;
        }
        for (const item of items) {
          vaultGroup.entries.push(ProtonPassJsonImportHandler.createEntry(item, vaultGroup));
          vaultItemCount++;
        }
      }
    }

    // 2) 顶层 items（vaults 无内嵌条目时回落，按 shareId 解析 vault 分组）
    if (vaultItemCount === 0 && data.items !== undefined && data.items !== null) {
      for (const item of data.items) {
        const vaultId = item.shareId ?? item.vaultId ?? '';
        const vaultName = vaultNameMap.get(vaultId) ?? '';
        const targetGroup = ProtonPassJsonImportHandler.getOrCreateGroup(
          rootGroup, vaultName, '', groupCache);
        targetGroup.entries.push(ProtonPassJsonImportHandler.createEntry(item, targetGroup));
        topLevelItemCount++;
      }
    }

    if (vaultItemCount + topLevelItemCount === 0) {
      throw new ImportError(
        ImportExportErrorCode.FILE_EMPTY,
        ResourceManager.getString($r('app.string.import_export_no_entries'))
      );
    }

    return rootGroup;
  }

  /**
   * 按名取或建子分组（空名返回根组）
   */
  private static getOrCreateGroup(
    root: KdbxGroup,
    name: string,
    notes: string,
    cache: Map<string, KdbxGroup>
  ): KdbxGroup {
    if (name === '') {
      return root;
    }
    const cached = cache.get(name);
    if (cached !== undefined) {
      return cached;
    }
    const group = KdbxGroup.create(name, root);
    if (notes !== '') {
      group.notes = notes;
    }
    root.groups.push(group);
    cache.set(name, group);
    return group;
  }

  /**
   * 单条目导入（KeePassXC readItem 语义）
   */
  private static createEntry(item: ProtonItemRaw, parent: KdbxGroup): KdbxEntry {
    const db = FileService.getDatabase();
    if (!db) {
      hilog.error(DOMAIN, TAG, 'database is not loaded');
      throw new ImportError(ImportExportErrorCode.PARSE_ERROR, 'database is not loaded');
    }
    const entry = KdbxEntry.create(db.meta, parent);

    const metadata = item.data?.metadata;
    entry.setField('Title', metadata?.name ?? '');
    const note = metadata?.note ?? '';
    if (note !== '') {
      entry.setField('Notes', note);
    }

    if (item.pinned === true) {
      entry.tags.push(KdbxUtils.FAVORITE_TAG);
    }

    const rawType = item.data?.type ?? '';
    const type = rawType.toLowerCase();
    const content = item.data?.content;
    if (type === 'login') {
      ProtonPassJsonImportHandler.fillLogin(entry, content);
    } else if (type === 'creditcard') {
      ProtonPassJsonImportHandler.fillCreditCard(entry, content);
    } else if (type === 'wifi') {
      ProtonPassJsonImportHandler.fillWifi(entry, content);
    } else if (type === 'sshkey') {
      ProtonPassJsonImportHandler.fillSshKey(entry, content);
    } else if (type !== 'custom' && type !== 'note' && type !== '') {
      ProtonPassJsonImportHandler.fillUnknown(entry, rawType, content);
    }

    ProtonPassJsonImportHandler.fillExtraFields(entry, item.data?.extraFields);

    if (item.state === 2) {
      entry.times.expires = true;
      entry.times.expiryTime = new Date();
    }

    if (item.createTime !== undefined && item.createTime > 0) {
      entry.times.creationTime = new Date(item.createTime * 1000);
    }
    if (item.modifyTime !== undefined && item.modifyTime > 0) {
      const modified = new Date(item.modifyTime * 1000);
      entry.times.lastModTime = modified;
      entry.times.lastAccessTime = modified;
    }

    return entry;
  }

  private static fillLogin(entry: KdbxEntry, content: Record<string, Object> | undefined): void {
    if (content === undefined || content === null) {
      return;
    }
    const username = ProtonPassJsonImportHandler.readString(content, 'itemUsername');
    entry.setField('UserName', username);
    entry.setField('Password', ProtonPassJsonImportHandler.readString(content, 'password'), true);

    const totp = ProtonPassJsonImportHandler.readString(content, 'totpUri');
    if (totp.trim() !== '') {
      ProtonPassJsonImportHandler.applyTotp(entry, totp);
    }

    // email 兜底与 Proton Pass CSV 共享映射：UserName 空时作 UserName，否则存自定义字段 Email
    const email = ProtonPassJsonImportHandler.readString(content, 'itemEmail');
    if (email !== '') {
      if (username === '') {
        entry.setField('UserName', email);
      } else {
        entry.setField('Email', email, false);
      }
    }

    const urls = ProtonPassJsonImportHandler.readStringArray(content, 'urls');
    let urlIndex = 0;
    for (const url of urls) {
      if (urlIndex === 0) {
        entry.setField('URL', url);
      } else {
        // KeePassXC AdditionalUrlAttribute 语义：次级 URL 存 KP2A_URL_N
        entry.setField(`KP2A_URL_${urlIndex}`, url);
      }
      urlIndex++;
    }
  }

  private static fillCreditCard(entry: KdbxEntry, content: Record<string, Object> | undefined): void {
    if (content === undefined || content === null) {
      return;
    }
    entry.setField('UserName', ProtonPassJsonImportHandler.readString(content, 'number'));
    entry.setField('Password', ProtonPassJsonImportHandler.readString(content, 'verificationNumber'), true);
    const cardholder = ProtonPassJsonImportHandler.readString(content, 'cardholderName');
    if (cardholder !== '') {
      entry.setField('card_cardholderName', cardholder, false);
    }
    const pin = ProtonPassJsonImportHandler.readString(content, 'pin');
    if (pin !== '') {
      entry.setField('card_pin', pin, true);
    }
    const expiration = ProtonPassJsonImportHandler.readString(content, 'expirationDate');
    if (expiration !== '') {
      entry.setField('card_expirationDate', expiration, false);
    }
  }

  private static fillWifi(entry: KdbxEntry, content: Record<string, Object> | undefined): void {
    if (content === undefined || content === null) {
      return;
    }
    entry.setField('UserName', ProtonPassJsonImportHandler.readString(content, 'ssid'));
    entry.setField('Password', ProtonPassJsonImportHandler.readString(content, 'password'), true);
    const security = ProtonPassJsonImportHandler.readString(content, 'security');
    if (security !== '') {
      entry.setField('wifi_security', security, false);
    }
  }

  private static fillSshKey(entry: KdbxEntry, content: Record<string, Object> | undefined): void {
    if (content === undefined || content === null) {
      return;
    }
    entry.setField('ssh_public_key', ProtonPassJsonImportHandler.readString(content, 'publicKey'), false);
    entry.setField('ssh_private_key', ProtonPassJsonImportHandler.readString(content, 'privateKey'), true);
  }

  /**
   * 未知类型：备注加前缀，content 标量字段转自定义字段（KeePassXC 语义，均不加密）
   */
  private static fillUnknown(entry: KdbxEntry, type: string, content: Record<string, Object> | undefined): void {
    const prefix = `Unknown entry type '${type}'. Content data fields have been added as attributes.`;
    const existing = KdbxUtils.getFieldValueString(entry.fields, 'Notes');
    entry.setField('Notes', `${prefix}\n\n${existing}`, false);
    if (content === undefined || content === null) {
      return;
    }
    for (const fieldName of ProtonPassJsonImportHandler.CONTENT_FIELD_NAMES) {
      const value = ProtonPassJsonImportHandler.readString(content, fieldName);
      if (value !== '') {
        entry.setField(`content_${fieldName}`, value, false);
      }
    }
  }

  /**
   * extraFields：text/plain 原样、hidden 受保护、totp 读 data.totpUri（KeePassXC 语义）
   * 字段名与既有字段冲突时追加序号后缀，避免覆盖标准字段
   */
  private static fillExtraFields(entry: KdbxEntry, extraFields: ProtonExtraFieldRaw[] | undefined): void {
    if (extraFields === undefined || extraFields === null) {
      return;
    }
    let conflictCounter = 1;
    for (const field of extraFields) {
      const name = field.fieldName ?? '';
      if (name === '') {
        continue;
      }
      const fieldType = (field.type ?? '').toLowerCase();
      let value = '';
      if (fieldType === 'totp') {
        value = field.data?.totpUri ?? '';
      } else {
        value = field.data?.content ?? '';
      }
      if (value === '') {
        continue;
      }
      let targetName = name;
      if (entry.fields.has(targetName)) {
        targetName = `${name}_${conflictCounter}`;
        conflictCounter++;
      }
      entry.setField(targetName, value, fieldType === 'hidden');
    }
  }

  /**
   * TOTP 规范化与 CSV 族一致：otpauth:// 原文（受保护）；裸密钥转 key=（KeeOtp 兼容）
   */
  private static applyTotp(entry: KdbxEntry, value: string): void {
    const trimmed = value.trim();
    if (trimmed.startsWith('otpauth://')) {
      entry.setField('otp', trimmed, true);
    } else {
      entry.setField('otp', `key=${trimmed}`, true);
    }
  }

  private static readString(record: Record<string, Object>, key: string): string {
    const value: Object | undefined = record[key];
    if (typeof value === 'string') {
      return value;
    }
    return '';
  }

  private static readStringArray(record: Record<string, Object>, key: string): string[] {
    const value: Object | undefined = record[key];
    const result: string[] = [];
    if (value instanceof Array) {
      const arr: Array<Object> = value;
      for (const element of arr) {
        if (typeof element === 'string') {
          result.push(element);
        }
      }
    }
    return result;
  }
}
