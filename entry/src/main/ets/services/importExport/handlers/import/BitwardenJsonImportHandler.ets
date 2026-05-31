import { KdbxGroup, KdbxEntry, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { FileService } from '../../../FileService';

/**
 * Bitwarden URI 接口
 */
interface BitwardenUri {
  uri: string;
  match?: number;
}

/**
 * Bitwarden 密码历史接口
 */
interface BitwardenPasswordHistory {
  lastUsedDate: string;
  password: string;
}

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
  uris?: BitwardenUri[];
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

interface BitwardenSecureNote {
  type: number;
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
  secureNote?: BitwardenSecureNote;
  passwordHistory?: BitwardenPasswordHistory[];
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
