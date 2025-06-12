import { KdbxDatabase } from './models/KdbxDatabase';
import { KdbxGroup } from './models/KdbxGroup';
import { KdbxEntry } from './models/KdbxEntry';
import { Binary, Field, TimeStamp, UUID, DeletedObject, Meta } from './models/KdbxTypes';
import { KdbxError, KdbxErrorCode } from './KdbxError';
import { InnerRandomStreamID } from './KdbxFormat';
import { ARC4 } from './crypto/ARC4';

import { xml, util } from '@kit.ArkTS';

/**
 * KDBX序列化器
 */
export class KdbxSerializer {
  /**
   * 保护流密钥
   */
  private protectedStreamKey?: Binary;
  /**
   * 内部随机流ID
   */
  private innerRandomStreamId?: InnerRandomStreamID;

  /**
   * 构造函数
   * @param protectedStreamKey 保护流密钥
   * @param innerRandomStreamId 内部随机流ID
   */
  constructor(
    protectedStreamKey?: Binary,
    innerRandomStreamId?: InnerRandomStreamID
  ) {
    this.protectedStreamKey = protectedStreamKey;
    this.innerRandomStreamId = innerRandomStreamId || InnerRandomStreamID.CHACHA20;
  }

  /**
   * 序列化数据库为XML
   * @param db 数据库
   * @returns XML字符串
   */
  serializeToXml(db: KdbxDatabase): string {
    try {
      // 创建XML文档
      const doc = this.createXmlDocument();
      xml.XmlSerializer()

      // 创建根元素
      const rootElement = doc.createElement('KeePassFile');
      doc.appendChild(rootElement);

      // 添加元数据
      this.serializeMeta(doc, rootElement, db.meta);

      // 添加根组
      const rootGroupElement = this.serializeGroup(doc, db.root);

      // 创建组元素
      const groupsElement = doc.createElement('Root');
      groupsElement.appendChild(rootGroupElement);
      rootElement.appendChild(groupsElement);

      // 添加已删除对象
      this.serializeDeletedObjects(doc, rootElement, db.deletedObjects);

      // 返回XML字符串
      return this.xmlToString(doc);
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.XML_WRITING_FAILED,
        '序列化数据库失败'
      );
    }
  }

  /**
   * 从XML反序列化数据库
   * @param xml XML字符串
   * @returns 数据库
   */
  deserializeFromXml(xml: string): KdbxDatabase {
    try {
      // 解析XML文档
      const doc = this.parseXmlDocument(xml);

      // 获取根元素
      const rootElement = doc.documentElement;
      if (!rootElement || rootElement.nodeName !== 'KeePassFile') {
        throw new KdbxError(
          KdbxErrorCode.INVALID_XML_STRUCTURE,
          '无效的KeePass XML结构'
        );
      }

      // 创建数据库
      const db = new KdbxDatabase();

      // 解析元数据
      const metaElement = rootElement.querySelector('Meta');
      if (metaElement) {
        db.meta = this.deserializeMeta(metaElement);
      }

      // 解析根组
      const rootGroupElement = rootElement.querySelector('Root > Group');
      if (rootGroupElement) {
        db.root = this.deserializeGroup(rootGroupElement);
      } else {
        throw new KdbxError(
          KdbxErrorCode.INVALID_XML_STRUCTURE,
          '未找到根组'
        );
      }

      // 解析已删除对象
      const deletedObjectsElement = rootElement.querySelector('DeletedObjects');
      if (deletedObjectsElement) {
        db.deletedObjects = this.deserializeDeletedObjects(deletedObjectsElement);
      }

      return db;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.XML_PARSING_FAILED,
        '反序列化数据库失败'
      );
    }
  }

  /**
   * 创建XML文档
   * @returns XML文档
   */
  private createXmlDocument(): Document {
    return new DOMParser().parseFromString('<?xml version="1.0" encoding="utf-8" standalone="yes"?>',
      'application/xml');
  }

  /**
   * 解析XML文档
   * @param xml XML字符串
   * @returns XML文档
   */
  private parseXmlDocument(xml: string): Document {
    const doc = new DOMParser().parseFromString(xml, 'application/xml');

    // 检查解析错误
    const parseError = doc.querySelector('parsererror');
    if (parseError) {
      throw new KdbxError(
        KdbxErrorCode.XML_PARSING_FAILED,
        `XML解析错误: ${parseError.textContent}`
      );
    }

    return doc;
  }

  /**
   * 将XML文档转换为字符串
   * @param doc XML文档
   * @returns XML字符串
   */
  private xmlToString(doc: Document): string {
    const serializer = new XMLSerializer();
    return serializer.serializeToString(doc);
  }

  /**
   * 序列化元数据
   * @param doc XML文档
   * @param parentElement 父元素
   * @param meta 元数据
   */
  private serializeMeta(doc: Document, parentElement: Element, meta: Meta): void {
    const metaElement = doc.createElement('Meta');

    // 添加基本元数据
    this.appendTextElement(doc, metaElement, 'DatabaseName', meta.databaseName);
    this.appendTextElement(doc, metaElement, 'DatabaseDescription', meta.databaseDescription);
    this.appendTextElement(doc, metaElement, 'DefaultUserName', meta.defaultUserName);
    this.appendTextElement(doc, metaElement, 'HistoryMaxItems', meta.historyMaxItems.toString());
    this.appendTextElement(doc, metaElement, 'HistoryMaxSize', meta.historyMaxSize.toString());

    // 添加回收站设置
    this.appendTextElement(doc, metaElement, 'RecycleBinEnabled', meta.recycleBinEnabled ? 'True' : 'False');
    if (meta.recycleBinUUID) {
      this.appendTextElement(doc, metaElement, 'RecycleBinUUID', this.uuidToString(meta.recycleBinUUID));
    }
    if (meta.recycleBinChanged) {
      this.appendTextElement(doc, metaElement, 'RecycleBinChanged', this.dateToString(meta.recycleBinChanged));
    }

    // 添加主密钥更改时间
    if (meta.masterKeyChanged) {
      this.appendTextElement(doc, metaElement, 'MasterKeyChanged', this.dateToString(meta.masterKeyChanged));
    }

    // 添加内存保护设置
    const memoryProtectionElement = doc.createElement('MemoryProtection');
    this.appendTextElement(doc, memoryProtectionElement, 'ProtectTitle',
      meta.memoryProtection.protectTitle ? 'True' : 'False');
    this.appendTextElement(doc, memoryProtectionElement, 'ProtectUserName',
      meta.memoryProtection.protectUserName ? 'True' : 'False');
    this.appendTextElement(doc, memoryProtectionElement, 'ProtectPassword',
      meta.memoryProtection.protectPassword ? 'True' : 'False');
    this.appendTextElement(doc, memoryProtectionElement, 'ProtectURL',
      meta.memoryProtection.protectUrl ? 'True' : 'False');
    this.appendTextElement(doc, memoryProtectionElement, 'ProtectNotes',
      meta.memoryProtection.protectNotes ? 'True' : 'False');
    metaElement.appendChild(memoryProtectionElement);

    // 添加自定义图标
    if (meta.customIcons.size > 0) {
      const customIconsElement = doc.createElement('CustomIcons');

      meta.customIcons.forEach((data, uuid) => {
        const iconElement = doc.createElement('Icon');
        this.appendTextElement(doc, iconElement, 'UUID', this.uuidToString(uuid));
        this.appendTextElement(doc, iconElement, 'Data', this.binaryToBase64(data));
        customIconsElement.appendChild(iconElement);
      });

      metaElement.appendChild(customIconsElement);
    }

    parentElement.appendChild(metaElement);
  }

  /**
   * 反序列化元数据
   * @param metaElement 元数据元素
   * @returns 元数据
   */
  private deserializeMeta(metaElement: Element): Meta {
    const meta: Meta = {
      databaseName: this.getElementText(metaElement, 'DatabaseName') || '新数据库',
      databaseDescription: this.getElementText(metaElement, 'DatabaseDescription') || '',
      defaultUserName: this.getElementText(metaElement, 'DefaultUserName') || '',
      historyMaxItems: parseInt(this.getElementText(metaElement, 'HistoryMaxItems') || '10', 10),
      historyMaxSize: parseInt(this.getElementText(metaElement, 'HistoryMaxSize') || '6291456', 10),
      recycleBinEnabled: this.getElementText(metaElement, 'RecycleBinEnabled') === 'True',
      recycleBinUUID: this.stringToUuid(this.getElementText(metaElement, 'RecycleBinUUID')),
      recycleBinChanged: this.stringToDate(this.getElementText(metaElement, 'RecycleBinChanged')),
      masterKeyChanged: this.stringToDate(this.getElementText(metaElement, 'MasterKeyChanged')),
      memoryProtection: {
        protectTitle: false,
        protectUserName: false,
        protectPassword: true,
        protectUrl: false,
        protectNotes: false
      },
      customIcons: new Map()
    };

    // 解析内存保护设置
    const memoryProtectionElement = metaElement.querySelector('MemoryProtection');
    if (memoryProtectionElement) {
      meta.memoryProtection = {
        protectTitle: this.getElementText(memoryProtectionElement, 'ProtectTitle') === 'True',
        protectUserName: this.getElementText(memoryProtectionElement, 'ProtectUserName') === 'True',
        protectPassword: this.getElementText(memoryProtectionElement, 'ProtectPassword') === 'True',
        protectUrl: this.getElementText(memoryProtectionElement, 'ProtectURL') === 'True',
        protectNotes: this.getElementText(memoryProtectionElement, 'ProtectNotes') === 'True'
      };
    }

    // 解析自定义图标
    const customIconsElement = metaElement.querySelector('CustomIcons');
    if (customIconsElement) {
      const iconElements = customIconsElement.querySelectorAll('Icon');
      iconElements.forEach(iconElement => {
        const uuid = this.stringToUuid(this.getElementText(iconElement, 'UUID'));
        const data = this.base64ToBinary(this.getElementText(iconElement, 'Data'));

        if (uuid && data) {
          meta.customIcons.set(uuid, data);
        }
      });
    }

    return meta;
  }

  /**
   * 序列化组
   * @param doc XML文档
   * @param group 组
   * @returns 组元素
   */
  private serializeGroup(doc: Document, group: KdbxGroup): Element {
    const groupElement = doc.createElement('Group');

    // 添加基本属性
    this.appendTextElement(doc, groupElement, 'UUID', this.uuidToString(group.uuid));
    this.appendTextElement(doc, groupElement, 'Name', group.name);
    this.appendTextElement(doc, groupElement, 'Notes', '');

    // 添加图标
    this.appendTextElement(doc, groupElement, 'IconID', group.icon.id.toString());
    if (group.icon.uuid) {
      this.appendTextElement(doc, groupElement, 'CustomIconUUID', this.uuidToString(group.icon.uuid));
    }

    // 添加时间信息
    const timesElement = doc.createElement('Times');
    this.appendTextElement(doc, timesElement, 'CreationTime', this.dateToString(group.creationTime));
    this.appendTextElement(doc, timesElement, 'LastModificationTime', this.dateToString(group.lastModifiedTime));
    this.appendTextElement(doc, timesElement, 'LastAccessTime', this.dateToString(group.lastAccessTime));
    this.appendTextElement(doc, timesElement, 'ExpiryTime', this.dateToString(group.expiryTime || new Date(0)));
    this.appendTextElement(doc, timesElement, 'Expires', group.expires ? 'True' : 'False');
    this.appendTextElement(doc, timesElement, 'UsageCount', '0');
    this.appendTextElement(doc, timesElement, 'LocationChanged', this.dateToString(group.lastModifiedTime));
    groupElement.appendChild(timesElement);

    // 添加是否展开
    this.appendTextElement(doc, groupElement, 'IsExpanded', group.isExpanded ? 'True' : 'False');

    // 添加子组
    for (const childGroup of group.groups) {
      groupElement.appendChild(this.serializeGroup(doc, childGroup));
    }

    // 添加条目
    for (const entry of group.entries) {
      groupElement.appendChild(this.serializeEntry(doc, entry));
    }

    return groupElement;
  }

  /**
   * 反序列化组
   * @param groupElement 组元素
   * @returns 组
   */
  private deserializeGroup(groupElement: Element): KdbxGroup {
    const uuid = this.stringToUuid(this.getElementText(groupElement, 'UUID'));
    const name = this.getElementText(groupElement, 'Name') || '未命名组';

    const group = new KdbxGroup(uuid, name);

    // 解析图标
    const iconId = parseInt(this.getElementText(groupElement, 'IconID') || '0', 10);
    const customIconUUID = this.stringToUuid(this.getElementText(groupElement, 'CustomIconUUID'));
    group.icon = { id: iconId, uuid: customIconUUID };

    // 解析时间信息
    const timesElement = groupElement.querySelector('Times');
    if (timesElement) {
      group.creationTime = this.stringToDate(this.getElementText(timesElement, 'CreationTime')) || new Date();
      group.lastModifiedTime =
        this.stringToDate(this.getElementText(timesElement, 'LastModificationTime')) || new Date();
      group.lastAccessTime = this.stringToDate(this.getElementText(timesElement, 'LastAccessTime')) || new Date();
      group.expiryTime = this.stringToDate(this.getElementText(timesElement, 'ExpiryTime'));
      group.expires = this.getElementText(timesElement, 'Expires') === 'True';
    }

    // 解析是否展开
    group.isExpanded = this.getElementText(groupElement, 'IsExpanded') === 'True';

    // 解析子组
    const childGroupElements = groupElement.querySelectorAll(':scope > Group');
    childGroupElements.forEach(childGroupElement => {
      const childGroup = this.deserializeGroup(childGroupElement);
      group.addGroup(childGroup);
    });

    // 解析条目
    const entryElements = groupElement.querySelectorAll(':scope > Entry');
    entryElements.forEach(entryElement => {
      const entry = this.deserializeEntry(entryElement);
      group.addEntry(entry);
    });

    return group;
  }

  /**
   * 序列化条目
   * @param doc XML文档
   * @param entry 条目
   * @returns 条目元素
   */
  private serializeEntry(doc: Document, entry: KdbxEntry): Element {
    const entryElement = doc.createElement('Entry');

    // 添加基本属性
    this.appendTextElement(doc, entryElement, 'UUID', this.uuidToString(entry.uuid));

    // 添加图标
    this.appendTextElement(doc, entryElement, 'IconID', entry.icon.id.toString());
    if (entry.icon.uuid) {
      this.appendTextElement(doc, entryElement, 'CustomIconUUID', this.uuidToString(entry.icon.uuid));
    }

    // 添加时间信息
    const timesElement = doc.createElement('Times');
    this.appendTextElement(doc, timesElement, 'CreationTime', this.dateToString(entry.creationTime));
    this.appendTextElement(doc, timesElement, 'LastModificationTime', this.dateToString(entry.lastModifiedTime));
    this.appendTextElement(doc, timesElement, 'LastAccessTime', this.dateToString(entry.lastAccessTime));
    this.appendTextElement(doc, timesElement, 'ExpiryTime', this.dateToString(entry.expiryTime || new Date(0)));
    this.appendTextElement(doc, timesElement, 'Expires', entry.expires ? 'True' : 'False');
    this.appendTextElement(doc, timesElement, 'UsageCount', '0');
    this.appendTextElement(doc, timesElement, 'LocationChanged', this.dateToString(entry.lastModifiedTime));
    entryElement.appendChild(timesElement);

    // 添加字段
    for (const field of entry.fields) {
      const stringElement = doc.createElement('String');

      const keyElement = doc.createElement('Key');
      keyElement.textContent = field.name;
      stringElement.appendChild(keyElement);

      const valueElement = doc.createElement('Value');
      if (field.protected) {
        valueElement.setAttribute('Protected', 'True');
        valueElement.textContent = this.protectValue(field.value);
      } else {
        valueElement.textContent = field.value;
      }
      stringElement.appendChild(valueElement);

      entryElement.appendChild(stringElement);
    }

    // 添加二进制附件
    for (const attachment of entry.attachments) {
      const binaryElement = doc.createElement('Binary');

      const keyElement = doc.createElement('Key');
      keyElement.textContent = attachment.name;
      binaryElement.appendChild(keyElement);

      const valueElement = doc.createElement('Value');
      valueElement.setAttribute('Ref', attachment.ref || '0');
      binaryElement.appendChild(valueElement);

      entryElement.appendChild(binaryElement);
    }

    // 添加自动类型
    if (entry.autoType && entry.autoType.enabled) {
      const autoTypeElement = doc.createElement('AutoType');
      this.appendTextElement(doc, autoTypeElement, 'Enabled', entry.autoType.enabled ? 'True' : 'False');
      this.appendTextElement(doc, autoTypeElement, 'DataTransferObfuscation', '0');
      this.appendTextElement(doc, autoTypeElement, 'DefaultSequence', entry.autoType.defaultSequence || '');

      // 添加自动类型关联
      if (entry.autoType.associations && entry.autoType.associations.length > 0) {
        const associationsElement = doc.createElement('Association');

        for (const assoc of entry.autoType.associations) {
          const associationElement = doc.createElement('Association');
          this.appendTextElement(doc, associationElement, 'Window', assoc.window || '');
          this.appendTextElement(doc, associationElement, 'KeystrokeSequence', assoc.keystrokeSequence || '');
          associationsElement.appendChild(associationElement);
        }

        autoTypeElement.appendChild(associationsElement);
      }

      entryElement.appendChild(autoTypeElement);
    }

    // 添加历史
    if (entry.history && entry.history.length > 0) {
      const historyElement = doc.createElement('History');

      for (const historyEntry of entry.history) {
        historyElement.appendChild(this.serializeEntry(doc, historyEntry));
      }

      entryElement.appendChild(historyElement);
    }

    return entryElement;
  }

  /**
   * 反序列化条目
   * @param entryElement 条目元素
   * @returns 条目
   */
  private deserializeEntry(entryElement: Element): KdbxEntry {
    const uuid = this.stringToUuid(this.getElementText(entryElement, 'UUID'));
    const entry = new KdbxEntry(uuid, new Uint8Array(16)); // 临时父组UUID，将在添加到组时更新

    // 解析图标
    const iconId = parseInt(this.getElementText(entryElement, 'IconID') || '0', 10);
    const customIconUUID = this.stringToUuid(this.getElementText(entryElement, 'CustomIconUUID'));
    entry.icon = { id: iconId, uuid: customIconUUID };

    // 解析时间信息
    const timesElement = entryElement.querySelector('Times');
    if (timesElement) {
      entry.creationTime = this.stringToDate(this.getElementText(timesElement, 'CreationTime')) || new Date();
      entry.lastModifiedTime =
        this.stringToDate(this.getElementText(timesElement, 'LastModificationTime')) || new Date();
      entry.lastAccessTime = this.stringToDate(this.getElementText(timesElement, 'LastAccessTime')) || new Date();
      entry.expiryTime = this.stringToDate(this.getElementText(timesElement, 'ExpiryTime'));
      entry.expires = this.getElementText(timesElement, 'Expires') === 'True';
    }

    // 解析字段
    const stringElements = entryElement.querySelectorAll('String');
    entry.fields = [];

    stringElements.forEach(stringElement => {
      const name = this.getElementText(stringElement, 'Key');
      const valueElement = stringElement.querySelector('Value');

      if (name && valueElement) {
        const protected = valueElement.getAttribute('Protected') === 'True';
        let value = valueElement.textContent || '';

        if (protected) {
          value = this.unprotectValue(value);
        }

        entry.fields.push({ name, value, protected });
      }
    });

    // 解析二进制附件
    const binaryElements = entryElement.querySelectorAll('Binary');
    entry.attachments = [];

    binaryElements.forEach(binaryElement => {
      const name = this.getElementText(binaryElement, 'Key');
      const valueElement = binaryElement.querySelector('Value');

      if (name && valueElement) {
        const ref = valueElement.getAttribute('Ref');
        const data = valueElement.textContent ? this.base64ToBinary(valueElement.textContent) : new Uint8Array(0);

        entry.attachments.push({ name, data, ref });
      }
    });

    // 解析自动类型
    const autoTypeElement = entryElement.querySelector('AutoType');
    if (autoTypeElement) {
      entry.autoType = {
        enabled: this.getElementText(autoTypeElement, 'Enabled') === 'True',
        defaultSequence: this.getElementText(autoTypeElement, 'DefaultSequence') || '',
        associations: []
      };

      // 解析自动类型关联
      const associationElements = autoTypeElement.querySelectorAll('Association');
      associationElements.forEach(associationElement => {
        const window = this.getElementText(associationElement, 'Window') || '';
        const keystrokeSequence = this.getElementText(associationElement, 'KeystrokeSequence') || '';

        entry.autoType.associations.push({ window, keystrokeSequence });
      });
    }

    // 解析历史
    const historyElement = entryElement.querySelector('History');
    if (historyElement) {
      const historyEntryElements = historyElement.querySelectorAll('Entry');
      entry.history = [];

      historyEntryElements.forEach(historyEntryElement => {
        const historyEntry = this.deserializeEntry(historyEntryElement);
        entry.history.push(historyEntry);
      });
    }

    return entry;
  }

  /**
   * 序列化已删除对象
   * @param doc XML文档
   * @param parentElement 父元素
   * @param deletedObjects 已删除对象
   */
  private serializeDeletedObjects(doc: Document, parentElement: Element, deletedObjects: DeletedObject[]): void {
    if (deletedObjects.length === 0) {
      return;
    }

    const deletedObjectsElement = doc.createElement('DeletedObjects');

    for (const obj of deletedObjects) {
      const deletedObjectElement = doc.createElement('DeletedObject');

      this.appendTextElement(doc, deletedObjectElement, 'UUID', this.uuidToString(obj.uuid));
      this.appendTextElement(doc, deletedObjectElement, 'DeletionTime', this.dateToString(obj.deletionTime));

      deletedObjectsElement.appendChild(deletedObjectElement);
    }

    parentElement.appendChild(deletedObjectsElement);
  }

  /**
   * 反序列化已删除对象
   * @param deletedObjectsElement 已删除对象元素
   * @returns 已删除对象列表
   */
  private deserializeDeletedObjects(deletedObjectsElement: Element): DeletedObject[] {
    const deletedObjects: DeletedObject[] = [];

    const deletedObjectElements = deletedObjectsElement.querySelectorAll('DeletedObject');
    deletedObjectElements.forEach(element => {
      const uuid = this.stringToUuid(this.getElementText(element, 'UUID'));
      const deletionTime = this.stringToDate(this.getElementText(element, 'DeletionTime')) || new Date();

      if (uuid) {
        deletedObjects.push({ uuid, deletionTime });
      }
    });

    return deletedObjects;
  }

  /**
   * 添加文本元素
   * @param doc XML文档
   * @param parentElement 父元素
   * @param name 元素名称
   * @param value 元素值
   */
  private appendTextElement(doc: Document, parentElement: Element, name: string, value: string): void {
    const element = doc.createElement(name);
    element.textContent = value;
    parentElement.appendChild(element);
  }

  /**
   * 获取元素文本
   * @param parentElement 父元素
   * @param name 元素名称
   * @returns 元素文本
   */
  private getElementText(parentElement: Element, name: string): string | null {
    const element = parentElement.querySelector(name);
    return element ? element.textContent : null;
  }

  /**
   * UUID转字符串
   * @param uuid UUID
   * @returns 字符串
   */
  private uuidToString(uuid: UUID): string {
    if (!uuid) {
      return '';
    }

    // 将UUID转换为Base64
    return btoa(String.fromCharCode(...uuid));
  }

  /**
   * 字符串转UUID
   * @param str 字符串
   * @returns UUID
   */
  private stringToUuid(str: string | null): UUID | undefined {
    if (!str) {
      return undefined;
    }

    try {
      // 从Base64解码
      const binaryString = atob(str);
      const uuid = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        uuid[i] = binaryString.charCodeAt(i);
      }
      return uuid;
    } catch (e) {
      return undefined;
    }
  }

  /**
   * 日期转字符串
   * @param date 日期
   * @returns 字符串
   */
  private dateToString(date?: TimeStamp): string {
    if (!date) {
      return '';
    }

    return date.toISOString();
  }

  /**
   * 字符串转日期
   * @param str 字符串
   * @returns 日期
   */
  private stringToDate(str: string | null): TimeStamp | undefined {
    if (!str) {
      return undefined;
    }

    try {
      return new Date(str);
    } catch (e) {
      return undefined;
    }
  }

  /**
   * 二进制数据转Base64
   * @param data 二进制数据
   * @returns Base64字符串
   */
  private binaryToBase64(data: Binary): string {
    return btoa(String.fromCharCode(...data));
  }

  /**
   * Base64转二进制数据
   * @param base64 Base64字符串
   * @returns 二进制数据
   */
  private base64ToBinary(base64: string | null): Binary {
    if (!base64) {
      return new Uint8Array(0);
    }

    try {
      const binaryString = atob(base64);
      const data = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        data[i] = binaryString.charCodeAt(i);
      }
      return data;
    } catch (e) {
      return new Uint8Array(0);
    }
  }

  /**
   * 保护字段值
   * @param value 原始值
   * @returns 加密后的值
   */
  private protectValue(value: string): string {
    if (!this.protectedStreamKey) {
      throw new KdbxError(
        KdbxErrorCode.ENCRYPTION_FAILED,
        '未设置保护流密钥'
      );
    }

    try {
      // 使用UTF-8编码字符串
      const encoder = new TextEncoder();
      const data = encoder.encode(value);

      // 根据内部随机流类型选择加密方法
      let encryptedData: Binary;
      switch (this.innerRandomStreamId) {
        case InnerRandomStreamID.CHACHA20:
          encryptedData = this.encryptChaCha20(data, this.protectedStreamKey);
          break;

        case InnerRandomStreamID.SALSA20:
          encryptedData = this.encryptSalsa20(data, this.protectedStreamKey);
          break;

        case InnerRandomStreamID.ARC4VARIANT:
          encryptedData = this.encryptArc4(data, this.protectedStreamKey);
          break;

        default:
          throw new KdbxError(
            KdbxErrorCode.ENCRYPTION_FAILED,
            '不支持的内部随机流类型'
          );
      }

      // 转换为Base64
      return this.binaryToBase64(encryptedData);
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.ENCRYPTION_FAILED,
        '保护字段加密失败'
      );
    }
  }

  /**
   * 解除字段保护
   * @param value 加密的值
   * @returns 原始值
   */
  private unprotectValue(value: string): string {
    if (!this.protectedStreamKey) {
      throw new KdbxError(
        KdbxErrorCode.DECRYPTION_FAILED,
        '未设置保护流密钥'
      );
    }

    try {
      // 从Base64解码
      const encryptedData = this.base64ToBinary(value);

      // 根据内部随机流类型选择解密方法
      let decryptedData: Binary;
      switch (this.innerRandomStreamId) {
        case InnerRandomStreamID.CHACHA20:
          decryptedData = this.decryptChaCha20(encryptedData, this.protectedStreamKey);
          break;

        case InnerRandomStreamID.SALSA20:
          decryptedData = this.decryptSalsa20(encryptedData, this.protectedStreamKey);
          break;

        case InnerRandomStreamID.ARC4VARIANT:
          decryptedData = this.decryptArc4(encryptedData, this.protectedStreamKey);
          break;

        default:
          throw new KdbxError(
            KdbxErrorCode.DECRYPTION_FAILED,
            '不支持的内部随机流类型'
          );
      }

      // 使用UTF-8解码
      const decoder = new TextDecoder();
      return decoder.decode(decryptedData);
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.DECRYPTION_FAILED,
        '解除字段保护失败'
      );
    }
  }

  /**
   * ChaCha20加密
   * @param data 原始数据
   * @param key 密钥
   * @returns 加密数据
   */
  private encryptChaCha20(data: Binary, key: Binary): Binary {
    try {
      // 使用crypto/ChaCha20模块实现
      const chacha = new ChaCha20(key);
      const nonce = new Uint8Array(12); // 12字节随机数
      KdbxUtils.generateRandom(nonce);

      const encrypted = new Uint8Array(data.length);
      chacha.process(nonce, data, encrypted);

      // 合并nonce和加密数据
      const result = new Uint8Array(nonce.length + encrypted.length);
      result.set(nonce);
      result.set(encrypted, nonce.length);

      return result;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.ENCRYPTION_FAILED,
        'ChaCha20加密失败'
      );
    }
  }

  /**
   * ChaCha20解密
   * @param data 加密数据
   * @param key 密钥
   * @returns 原始数据
   */
  private decryptChaCha20(data: Binary, key: Binary): Binary {
    try {
      // 验证输入数据长度(至少包含12字节nonce)
      if (data.length < 12) {
        throw new KdbxError(
          KdbxErrorCode.INVALID_DATA,
          '无效的加密数据长度'
        );
      }

      // 分离nonce和加密数据
      const nonce = data.slice(0, 12);
      const encrypted = data.slice(12);

      // 使用相同的密钥初始化
      const chacha = new ChaCha20(key);
      const decrypted = new Uint8Array(encrypted.length);

      // 解密过程(加密和解密使用相同方法)
      chacha.process(nonce, encrypted, decrypted);

      return decrypted;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.DECRYPTION_FAILED,
        'ChaCha20解密失败'
      );
    }
  }

  /**
   * Salsa20加密
   * @param data 原始数据
   * @param key 密钥
   * @returns 加密数据
   */
  private encryptSalsa20(data: Binary, key: Binary): Binary {
    try {
      // 使用crypto/Salsa20模块实现
      const salsa = new Salsa20(key);
      const nonce = new Uint8Array(8); // 8字节随机数
      KdbxUtils.generateRandom(nonce);

      const encrypted = new Uint8Array(data.length);
      salsa.process(nonce, data, encrypted);

      // 合并nonce和加密数据
      const result = new Uint8Array(nonce.length + encrypted.length);
      result.set(nonce);
      result.set(encrypted, nonce.length);

      return result;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.ENCRYPTION_FAILED,
        'Salsa20加密失败'
      );
    }
  }

  /**
   * Salsa20解密
   * @param data 加密数据
   * @param key 密钥
   * @returns 原始数据
   */
  private decryptSalsa20(data: Binary, key: Binary): Binary {
    try {
      // 验证输入数据长度(至少包含8字节nonce)
      if (data.length < 8) {
        throw new KdbxError(
          KdbxErrorCode.INVALID_DATA,
          '无效的加密数据长度'
        );
      }

      // 分离nonce和加密数据
      const nonce = data.slice(0, 8);
      const encrypted = data.slice(8);

      // 使用相同的密钥初始化
      const salsa = new Salsa20(key);
      const decrypted = new Uint8Array(encrypted.length);

      // 解密过程(加密和解密使用相同方法)
      salsa.process(nonce, encrypted, decrypted);

      return decrypted;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.DECRYPTION_FAILED,
        'Salsa20解密失败'
      );
    }
  }

  /**
   * ARC4变体加密
   * @param data 原始数据
   * @param key 密钥
   * @returns 加密数据
   */
  private encryptArc4(data: Binary, key: Binary): Binary {
    try {
      // 使用ARC4变体实现
      const arc4 = new ARC4(key);

      // 加密数据
      const encrypted = new Uint8Array(data.length);
      arc4.process(data, encrypted);

      // 清理敏感数据
      arc4.clear();

      return encrypted;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.ENCRYPTION_FAILED,
        'ARC4变体加密失败'
      );
    }
  }

  /**
   * ARC4变体解密
   * @param data 加密数据
   * @param key 密钥
   * @returns 原始数据
   */
  private decryptArc4(data: Binary, key: Binary): Binary {
    try {
      // 验证输入数据
      if (!data || data.length === 0) {
        throw new KdbxError(
          KdbxErrorCode.INVALID_DATA,
          '无效的加密数据'
        );
      }

      // 使用ARC4变体实现（解密过程与加密相同）
      const arc4 = new ARC4(key);

      // 解密数据
      const decrypted = new Uint8Array(data.length);
      arc4.process(data, decrypted);

      // 清理敏感数据
      arc4.clear();

      return decrypted;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.DECRYPTION_FAILED,
        'ARC4变体解密失败'
      );
    }
  }
}