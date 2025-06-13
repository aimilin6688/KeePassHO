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
    return new KdbxDatabase();
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
    this.appendTextElement(serializer, 'HistoryMaxItems', meta.historyMaxItems?.toString());
    this.appendTextElement(serializer, 'HistoryMaxSize', meta.historyMaxSize?.toString());

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
    this.appendTextElement(serializer, 'ProtectTitle', meta.memoryProtection?.protectTitle ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectUserName', meta.memoryProtection?.protectUserName ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectPassword', meta.memoryProtection?.protectPassword ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectURL', meta.memoryProtection?.protectUrl ? 'True' : 'False');
    this.appendTextElement(serializer, 'ProtectNotes', meta.memoryProtection?.protectNotes ? 'True' : 'False');
    serializer.endElement(); // 结束MemoryProtection元素

    // 添加自定义图标
    if (meta.customIcons && meta.customIcons.size > 0) {
      serializer.startElement('CustomIcons');

      meta.customIcons.forEach((data, uuid) => {
        serializer.startElement('Icon');
        this.appendTextElement(serializer, 'UUID', this.uuidToString(uuid));
        this.appendTextElement(serializer, 'Data', this.binaryToBase64(data.data));
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
  private appendTextElement(serializer: xml.XmlSerializer, name: string, value: string | undefined): void {
    if (value !== undefined) {
      serializer.startElement(name);
      serializer.setText(value);
      serializer.endElement();
    }
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
    this.appendTextElement(serializer, 'IconID', entry.icon.uuid.toString());
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
        serializer.setAttributes('Protected', 'True');
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
      serializer.setAttributes('Ref', attachment.ref || '0');
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
   * UUID转字符串
   * @param uuid UUID
   * @returns 字符串
   */
  private uuidToString(uuid: UUID): string {
    return uuid;
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