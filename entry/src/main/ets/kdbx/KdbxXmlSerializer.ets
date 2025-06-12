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
export class KdbxXmlSerializer {
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
      // 创建XML序列化器
      const buffer = new ArrayBuffer(1024 * 1024); // 1MB初始大小
      const serializer = new xml.XmlSerializer(buffer, 'utf-8');

      // 写入XML声明
      serializer.setDeclaration();

      // 创建根元素
      serializer.startElement('KeePassFile');
      
      // 添加XML命名空间
      serializer.setNamespace('', 'http://www.keepassdx.com/ns/kdbx');

      // 添加元数据
      this.serializeMeta(serializer, db.meta);

      // 添加根组
      serializer.startElement('Root');
      this.serializeGroup(serializer, db.root);
      serializer.endElement(); // 结束Root元素

      // 添加已删除对象
      this.serializeDeletedObjects(serializer, db.deletedObjects);

      // 结束根元素
      serializer.endElement(); // 结束KeePassFile元素

      // 返回XML字符串
      return buffer.toString();
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
   * @param xmlString XML字符串
   * @returns 数据库
   */
  deserializeFromXml(xmlString: string): KdbxDatabase {
    try {
      // 创建数据库
      const db = new KdbxDatabase();
      
      // 创建XML解析器
      const buffer = new ArrayBuffer(xmlString.length * 2); // 确保足够大的缓冲区
      const dataView = new DataView(buffer);
      
      // 将字符串写入缓冲区
      const encoder = new util.TextEncoder();
      const encodedData = encoder.encodeInto(xmlString);
      
      // 创建解析器
      const parser = new xml.XmlPullParser(encodedData.buffer);
      
      // 解析XML
      let inMeta = false;
      let inRoot = false;
      let inDeletedObjects = false;
      
      parser.parseXml({
        supportDoctype: true,
        ignoreNameSpace: false,
        tokenValueCallbackFunction: (eventType, value) => {
          if (eventType === xml.EventType.START_TAG) {
            const tagName = value.getName();
            
            if (tagName === 'KeePassFile') {
              // 开始解析数据库
              return true;
            } else if (tagName === 'Meta') {
              inMeta = true;
              db.meta = this.deserializeMeta(parser);
              inMeta = false;
              return true;
            } else if (tagName === 'Root') {
              inRoot = true;
              return true;
            } else if (inRoot && tagName === 'Group') {
              db.root = this.deserializeGroup(parser);
              return true;
            } else if (tagName === 'DeletedObjects') {
              inDeletedObjects = true;
              db.deletedObjects = this.deserializeDeletedObjects(parser);
              inDeletedObjects = false;
              return true;
            }
          } else if (eventType === xml.EventType.END_TAG) {
            const tagName = value.getName();
            
            if (tagName === 'Root') {
              inRoot = false;
              return true;
            } else if (tagName === 'KeePassFile') {
              // 结束解析数据库
              return true;
            }
          }
          
          return true;
        }
      });
      
      // 验证数据库结构
      if (!db.root) {
        throw new KdbxError(
          KdbxErrorCode.INVALID_XML_STRUCTURE,
          '未找到根组'
        );
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
   * 解析XML文档
   * @param xmlString XML字符串
   * @returns XML解析器
   */
  private parseXmlDocument(xmlString: string): xml.XmlPullParser {
    try {
      // 创建XML解析器
      const parser = new xml.XmlPullParser();
      
      // 设置输入
      parser.parse(xmlString);
      
      return parser;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.XML_PARSING_FAILED,
        'XML解析错误'
      );
    }
  }

  /**
   * 序列化元数据
   * @param doc XML文档
   * @param parentElement 父元素
   * @param meta 元数据
   */
  private serializeMeta(serializer: xml.XmlSerializer, meta: Meta): void {
    // 开始Meta元素
    serializer.startElement('Meta');

    // 添加基本元数据
    this.appendTextElement(serializer, 'DatabaseName', meta.databaseName);
    this.appendTextElement(serializer, 'DatabaseDescription', meta.databaseDescription);
    this.appendTextElement(serializer, 'DefaultUserName', meta.defaultUserName);
    this.appendTextElement(serializer, 'HistoryMaxItems', meta.historyMaxItems.toString());
    this.appendTextElement(serializer, 'HistoryMaxSize', meta.historyMaxSize.toString());

    // 添加回收站设置
    this.appendTextElement(serializer, 'RecycleBinEnabled', meta.recycleBinEnabled ? 'True' : 'False');
    if (meta.recycleBinUUID) {
      this.appendTextElement(serializer, 'RecycleBinUUID', this.uuidToString(meta.recycleBinUUID));
    }
    if (meta.recycleBinChanged) {
      this.appendTextElement(serializer, 'RecycleBinChanged', this.dateToString(meta.recycleBinChanged));
    }

    // 添加主密钥更改时间
    if (meta.masterKeyChanged) {
      this.appendTextElement(serializer, 'MasterKeyChanged', this.dateToString(meta.masterKeyChanged));
    }

    // 添加内存保护设置
    serializer.startElement('MemoryProtection');
    this.appendTextElement(serializer, 'ProtectTitle', meta.memoryProtection.protectTitle ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectUserName', meta.memoryProtection.protectUserName ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectPassword', meta.memoryProtection.protectPassword ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectURL', meta.memoryProtection.protectUrl ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectNotes', meta.memoryProtection.protectNotes ? 'True' : 'False');
    serializer.endElement(); // 结束MemoryProtection元素

    // 添加自定义图标
    if (meta.customIcons.size > 0) {
      serializer.startElement('CustomIcons');

      meta.customIcons.forEach((data, uuid) => {
        serializer.startElement('Icon');
        this.appendTextElement(serializer, 'UUID', this.uuidToString(uuid));
        this.appendTextElement(serializer, 'Data', this.binaryToBase64(data));
        serializer.endElement(); // 结束Icon元素
      });

      serializer.endElement(); // 结束CustomIcons元素
    }

    serializer.endElement(); // 结束Meta元素
  }

  /**
   * 添加文本元素
   * @param serializer XML序列化器
   * @param name 元素名称
   * @param value 元素值
   */
  private appendTextElement(serializer: xml.XmlSerializer, name: string, value: string): void {
    serializer.startElement(name);
    serializer.setText(value);
    serializer.endElement();
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
   * @param serializer XML序列化器
   * @param group 组
   */
  private serializeGroup(serializer: xml.XmlSerializer, group: KdbxGroup): void {
    // 开始Group元素
    serializer.startElement('Group');

    // 添加基本属性
    this.appendTextElement(serializer, 'UUID', this.uuidToString(group.uuid));
    this.appendTextElement(serializer, 'Name', group.name);
    this.appendTextElement(serializer, 'Notes', '');

    // 添加图标
    this.appendTextElement(serializer, 'IconID', group.icon.id.toString());
    if (group.icon.uuid) {
      this.appendTextElement(serializer, 'CustomIconUUID', this.uuidToString(group.icon.uuid));
    }

    // 添加时间信息
    serializer.startElement('Times');
    this.appendTextElement(serializer, 'CreationTime', this.dateToString(group.creationTime));
    this.appendTextElement(serializer, 'LastModificationTime', this.dateToString(group.lastModifiedTime));
    this.appendTextElement(serializer, 'LastAccessTime', this.dateToString(group.lastAccessTime));
    this.appendTextElement(serializer, 'ExpiryTime', this.dateToString(group.expiryTime || new Date(0)));
    this.appendTextElement(serializer, 'Expires', group.expires ? 'True' : 'False');
    this.appendTextElement(serializer, 'UsageCount', '0');
    this.appendTextElement(serializer, 'LocationChanged', this.dateToString(group.lastModifiedTime));
    serializer.endElement(); // 结束Times元素

    // 添加是否展开
    this.appendTextElement(serializer, 'IsExpanded', group.isExpanded ? 'True' : 'False');

    // 添加子组
    for (const childGroup of group.groups) {
      this.serializeGroup(serializer, childGroup);
    }

    // 添加条目
    for (const entry of group.entries) {
      this.serializeEntry(serializer, entry);
    }

    serializer.endElement(); // 结束Group元素
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
   * @param serializer XML序列化器
   * @param entry 条目
   */
  private serializeEntry(serializer: xml.XmlSerializer, entry: KdbxEntry): void {
    // 开始Entry元素
    serializer.startElement('Entry');

    // 添加基本属性
    this.appendTextElement(serializer, 'UUID', this.uuidToString(entry.uuid));

    // 添加图标
    this.appendTextElement(serializer, 'IconID', entry.icon.id.toString());
    if (entry.icon.uuid) {
      this.appendTextElement(serializer, 'CustomIconUUID', this.uuidToString(entry.icon.uuid));
    }

    // 添加时间信息
    serializer.startElement('Times');
    this.appendTextElement(serializer, 'CreationTime', this.dateToString(entry.creationTime));
    this.appendTextElement(serializer, 'LastModificationTime', this.dateToString(entry.lastModifiedTime));
    this.appendTextElement(serializer, 'LastAccessTime', this.dateToString(entry.lastAccessTime));
    this.appendTextElement(serializer, 'ExpiryTime', this.dateToString(entry.expiryTime || new Date(0)));
    this.appendTextElement(serializer, 'Expires', entry.expires ? 'True' : 'False');
    this.appendTextElement(serializer, 'UsageCount', '0');
    this.appendTextElement(serializer, 'LocationChanged', this.dateToString(entry.lastModifiedTime));
    serializer.endElement(); // 结束Times元素

    // 添加字段
    for (const field of entry.fields) {
      serializer.startElement('String');
      
      this.appendTextElement(serializer, 'Key', field.name);
      
      serializer.startElement('Value');
      if (field.protected) {
        serializer.setAttributes([{ name: 'Protected', value: 'True' }]);
        serializer.setText(this.protectValue(field.value));
      } else {
        serializer.setText(field.value);
      }
      serializer.endElement(); // 结束Value元素
      
      serializer.endElement(); // 结束String元素
    }

    // 添加二进制附件
    for (const attachment of entry.attachments) {
      serializer.startElement('Binary');
      
      this.appendTextElement(serializer, 'Key', attachment.name);
      
      serializer.startElement('Value');
      serializer.setAttributes([{ name: 'Ref', value: attachment.ref || '0' }]);
      serializer.endElement(); // 结束Value元素
      
      serializer.endElement(); // 结束Binary元素
    }

    // 添加自动类型
    if (entry.autoType && entry.autoType.enabled) {
      serializer.startElement('AutoType');
      this.appendTextElement(serializer, 'Enabled', entry.autoType.enabled ? 'True' : 'False');
      this.appendTextElement(serializer, 'DataTransferObfuscation', '0');
      this.appendTextElement(serializer, 'DefaultSequence', entry.autoType.defaultSequence || '');

      // 添加自动类型关联
      if (entry.autoType.associations && entry.autoType.associations.length > 0) {
        serializer.startElement('Association');

        for (const assoc of entry.autoType.associations) {
          serializer.startElement('Association');
          this.appendTextElement(serializer, 'Window', assoc.window || '');
          this.appendTextElement(serializer, 'KeystrokeSequence', assoc.keystrokeSequence || '');
          serializer.endElement(); // 结束Association元素
        }

        serializer.endElement(); // 结束Association元素
      }

      serializer.endElement(); // 结束AutoType元素
    }

    // 添加历史
    if (entry.history && entry.history.length > 0) {
      serializer.startElement('History');

      for (const historyEntry of entry.history) {
        this.serializeEntry(serializer, historyEntry);
      }

      serializer.endElement(); // 结束History元素
    }

    serializer.endElement(); // 结束Entry元素
  }

  /**
   * 反序列化条目
   * @param parser XML解析器
   * @returns 条目
   */
  private deserializeEntry(parser: xml.XmlPullParser): KdbxEntry {
    let uuid: UUID | undefined;
    let iconId = 0;
    let customIconUUID: UUID | undefined;
    let entry: KdbxEntry | undefined;

    // 读取基本属性
    while (parser.next() !== xml.EventType.END_DOCUMENT) {
      if (parser.getEventType() === xml.EventType.START_TAG) {
        const tagName = parser.getName();
        
        switch (tagName) {
          case 'UUID':
            parser.next();
            if (parser.getEventType() === xml.EventType.TEXT) {
              uuid = this.stringToUuid(parser.getText());
            }
            break;
            
          case 'IconID':
            parser.next();
            if (parser.getEventType() === xml.EventType.TEXT) {
              iconId = parseInt(parser.getText() || '0', 10);
            }
            break;
            
          case 'CustomIconUUID':
            parser.next();
            if (parser.getEventType() === xml.EventType.TEXT) {
              customIconUUID = this.stringToUuid(parser.getText());
            }
            break;

          case 'Times':
            // 创建条目（如果还没有创建）
            if (!entry) {
              entry = new KdbxEntry(uuid, new Uint8Array(16)); // 临时父组UUID
              entry.icon = { id: iconId, uuid: customIconUUID };
            }
            this.deserializeEntryTimes(parser, entry);
            break;
            
          case 'String':
            // 创建条目（如果还没有创建）
            if (!entry) {
              entry = new KdbxEntry(uuid, new Uint8Array(16));
              entry.icon = { id: iconId, uuid: customIconUUID };
              entry.fields = [];
            } else if (!entry.fields) {
              entry.fields = [];
            }
            this.deserializeEntryString(parser, entry);
            break;

          case 'Binary':
            // 创建条目（如果还没有创建）
            if (!entry) {
              entry = new KdbxEntry(uuid, new Uint8Array(16));
              entry.icon = { id: iconId, uuid: customIconUUID };
              entry.attachments = [];
            } else if (!entry.attachments) {
              entry.attachments = [];
            }
            this.deserializeEntryBinary(parser, entry);
            break;
            
          case 'AutoType':
            // 创建条目（如果还没有创建）
            if (!entry) {
              entry = new KdbxEntry(uuid, new Uint8Array(16));
              entry.icon = { id: iconId, uuid: customIconUUID };
            }
            this.deserializeEntryAutoType(parser, entry);
            break;

          case 'History':
            // 创建条目（如果还没有创建）
            if (!entry) {
              entry = new KdbxEntry(uuid, new Uint8Array(16));
              entry.icon = { id: iconId, uuid: customIconUUID };
              entry.history = [];
            } else if (!entry.history) {
              entry.history = [];
            }
            this.deserializeEntryHistory(parser, entry);
            break;
        }
      } else if (parser.getEventType() === xml.EventType.END_TAG && parser.getName() === 'Entry') {
        break;
      }
    }

    // 如果没有创建条目（没有任何子元素），创建一个基本条目
    if (!entry) {
      entry = new KdbxEntry(uuid, new Uint8Array(16));
      entry.icon = { id: iconId, uuid: customIconUUID };
    }

    return entry;
  }
  
  /**
   * 反序列化条目时间信息
   * @param parser XML解析器
   * @param entry 条目
   */
  private deserializeEntryTimes(parser: xml.XmlPullParser, entry: KdbxEntry): void {
    while (parser.next() !== xml.EventType.END_DOCUMENT) {
      if (parser.getEventType() === xml.EventType.START_TAG) {
        const tagName = parser.getName();
        parser.next(); // 移动到文本内容
        
        if (parser.getEventType() === xml.EventType.TEXT) {
          const text = parser.getText();
          switch (tagName) {
            case 'CreationTime':
              entry.creationTime = this.stringToDate(text) || new Date();
              break;
            case 'LastModificationTime':
              entry.lastModifiedTime = this.stringToDate(text) || new Date();
              break;
            case 'LastAccessTime':
              entry.lastAccessTime = this.stringToDate(text) || new Date();
              break;
            case 'ExpiryTime':
              entry.expiryTime = this.stringToDate(text);
              break;
            case 'Expires':
              entry.expires = text === 'True';
              break;
          }
        }
      } else if (parser.getEventType() === xml.EventType.END_TAG && parser.getName() === 'Times') {
        break;
      }
    }
  }
  
  /**
   * 反序列化条目字符串字段
   * @param parser XML解析器
   * @param entry 条目
   */
  private deserializeEntryString(parser: xml.XmlPullParser, entry: KdbxEntry): void {
    let key = '';
    let value = '';
    let protected = false;
    
    while (parser.next() !== xml.EventType.END_DOCUMENT) {
      if (parser.getEventType() === xml.EventType.START_TAG) {
        const tagName = parser.getName();
        
        if (tagName === 'Key') {
          parser.next(); // 移动到文本内容
          if (parser.getEventType() === xml.EventType.TEXT) {
            key = parser.getText();
          }
        } else if (tagName === 'Value') {
          // 检查是否有Protected属性
          for (let i = 0; i < parser.getAttributeCount(); i++) {
            if (parser.getAttributeName(i) === 'Protected' && 
                parser.getAttributeValue(i) === 'True') {
              protected = true;
            }
          }
          
          parser.next(); // 移动到文本内容
          if (parser.getEventType() === xml.EventType.TEXT) {
            value = parser.getText();
            
            // 如果是受保护的字段，解密它
            if (protected && this.protectedStreamKey) {
              try {
                value = this.unprotectValue(value);
              } catch (error) {
                console.error('解密受保护字段失败:', error);
              }
            }
          }
        }
      } else if (parser.getEventType() === xml.EventType.END_TAG && parser.getName() === 'String') {
        // 添加字段到条目
        if (key) {
          entry.fields.push({
            name: key,
            value: value,
            protected: protected
          });
        }
        break;
      }
    }
  }

  /**
   * 序列化已删除对象
   * @param serializer XML序列化器
   * @param deletedObjects 已删除对象列表
   */
  private serializeDeletedObjects(serializer: xml.XmlSerializer, deletedObjects: DeletedObject[]): void {
    if (deletedObjects.length === 0) {
      return;
    }

    serializer.startElement('DeletedObjects');

    for (const obj of deletedObjects) {
      serializer.startElement('DeletedObject');
      this.appendTextElement(serializer, 'UUID', this.uuidToString(obj.uuid));
      this.appendTextElement(serializer, 'DeletionTime', this.dateToString(obj.deletionTime));
      serializer.endElement(); // 结束DeletedObject元素
    }

    serializer.endElement(); // 结束DeletedObjects元素
  }

  /**
   * 反序列化已删除对象
   * @param parser XML解析器
   * @returns 已删除对象列表
   */
  private deserializeDeletedObjects(parser: xml.XmlPullParser): DeletedObject[] {
    const deletedObjects: DeletedObject[] = [];
    
    // 解析DeletedObjects元素下的所有DeletedObject元素
    while (parser.next() !== xml.EventType.END_DOCUMENT) {
      if (parser.getEventType() === xml.EventType.START_TAG && parser.getName() === 'DeletedObject') {
        let uuid: UUID | undefined;
        let deletionTime: Date = new Date();
        
        // 解析DeletedObject的子元素
        while (parser.next() !== xml.EventType.END_DOCUMENT) {
          if (parser.getEventType() === xml.EventType.START_TAG) {
            const tagName = parser.getName();
            
            if (tagName === 'UUID') {
              parser.next(); // 移动到文本内容
              if (parser.getEventType() === xml.EventType.TEXT) {
                uuid = this.stringToUuid(parser.getText());
              }
            } else if (tagName === 'DeletionTime') {
              parser.next(); // 移动到文本内容
              if (parser.getEventType() === xml.EventType.TEXT) {
                deletionTime = this.stringToDate(parser.getText()) || new Date();
              }
            }
          } else if (parser.getEventType() === xml.EventType.END_TAG && parser.getName() === 'DeletedObject') {
            break; // 结束当前DeletedObject元素的解析
          }
        }
        
        if (uuid) {
          deletedObjects.push({ uuid, deletionTime });
        }
      } else if (parser.getEventType() === xml.EventType.END_TAG && parser.getName() === 'DeletedObjects') {
        break; // 结束DeletedObjects元素的解析
      }
    }
    
    return deletedObjects;
  }

  /**
   * 添加文本元素
   * @param serializer XML序列化器
   * @param name 元素名称
   * @param value 元素值
   */
  private appendTextElement(serializer: xml.XmlSerializer, name: string, value: string): void {
    serializer.startElement(name);
    serializer.setText(value);
    serializer.endElement();
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