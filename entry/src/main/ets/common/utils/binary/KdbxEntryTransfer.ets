import { KdbxContext, KdbxEntry, KdbxEntryAutoType, KdbxEntryEditState, KdbxEntryField, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { KdbxBaseTransfer } from './KdbxBaseTransfer';
import { KdbxBinaryStream } from './KdbxBinaryStream';

export class KdbxEntryTransfer implements KdbxBaseTransfer<KdbxEntry> {
  write(stream: KdbxBinaryStream, obj: KdbxEntry): void {
    // 写入基本属性
    stream.writeUuid(obj.uuid);
    stream.setUint32(obj.icon || 0, true);
    stream.writeUuid(obj.customIcon || new KdbxUuid());
    stream.writeString(obj.fgColor || '');
    stream.writeString(obj.bgColor || '');
    stream.writeString(obj.overrideUrl || '');

    // 写入tags数组
    stream.writeStrings(obj.tags);

    // 写入复杂对象
    stream.writeTimes(obj.times);
    this.writeFields(stream, obj.fields);

    // 写入二进制数据
    stream.writeBinaries(obj.binaries);

    this.writeAutoType(stream, obj.autoType);
    // 写入历史记录
    stream.setUint32(obj.history.length, true);
    for (const historyEntry of obj.history) {
      this.write(stream, historyEntry);
    }
    // 父组信息，只写入ID
    stream.writeUuid(obj.parentGroup?.uuid || new KdbxUuid());
    stream.writeUuid(obj.previousParentGroup || new KdbxUuid());
    stream.writeCustomData(obj.customData);

    // 写入其他属性
    stream.setUint8(obj.qualityCheck ? 1 : 0);
    // 编辑状态
    this.writeEditState(stream, obj._editState);
  }

  read(stream: KdbxBinaryStream, ctx: KdbxContext): KdbxEntry {
    const entry = new KdbxEntry();

    // 读取基本属性
    entry.uuid = stream.readUuid();
    entry.icon = stream.getUint32(true);
    const customIcon = stream.readUuid();
    entry.customIcon = customIcon.empty ? undefined : customIcon;
    entry.fgColor = stream.readString() || undefined;
    entry.bgColor = stream.readString() || undefined;
    entry.overrideUrl = stream.readString() || undefined;

    // 读取tags数组
    entry.tags = stream.readStrings();

    // 读取复杂对象
    entry.times = stream.readTimes();
    entry.fields = this.readFields(stream);

    // 读取二进制数据
    entry.binaries = stream.readBinaries();

    entry.autoType = this.readAutoType(stream);
    // 读取历史记录
    const historyCount = stream.getUint32(true);
    for (let i = 0; i < historyCount; i++) {
      entry.history.push(this.read(stream, ctx));
    }

    const parentGroup = new KdbxGroup();
    const parentGroupId = stream.readUuid();
    parentGroup.uuid = parentGroupId;
    entry.parentGroup = parentGroupId.empty ? undefined : parentGroup;
    const previousParentGroup = stream.readUuid();
    entry.previousParentGroup = previousParentGroup.empty ? undefined : previousParentGroup;

    entry.customData = stream.readCustomData();
    // 读取其他属性
    entry.qualityCheck = stream.getUint8() === 1 ? true : undefined;
    // 读取编辑状态
    entry._editState = this.readEditState(stream);
    return entry;
  }


  private writeFields(stream: KdbxBinaryStream, fields: Map<string, KdbxEntryField>): void {
    stream.setUint32(fields.size, true);
    for (const field of fields) {
      const key = field[0];
      const value = field[1];
      stream.writeString(key);
      if (value instanceof ProtectedValue) {
        stream.setUint8(1); // 标记为ProtectedValue
        stream.writeProtectedValue(value);
      } else {
        stream.setUint8(0); // 标记为普通字符串
        stream.writeString(value as string);
      }
    }
  }

  private readFields(stream: KdbxBinaryStream): Map<string, KdbxEntryField> {
    const fields = new Map<string, KdbxEntryField>();
    const count = stream.getUint32(true);
    for (let i = 0; i < count; i++) {
      const key = stream.readString();
      const type = stream.getUint8();
      if (type === 1) {
        fields.set(key, stream.readProtectedValue());
      } else {
        fields.set(key, stream.readString());
      }
    }
    return fields;
  }

  private writeAutoType(stream: KdbxBinaryStream, autoType: KdbxEntryAutoType): void {
    stream.setUint8(autoType.enabled ? 1 : 0);
    stream.setUint32(autoType.obfuscation, true);
    stream.writeString(autoType.defaultSequence || '');

    stream.setUint32(autoType.items.length, true);
    for (const item of autoType.items) {
      stream.writeString(item.window);
      stream.writeString(item.keystrokeSequence);
    }
  }

  private readAutoType(stream: KdbxBinaryStream): KdbxEntryAutoType {
    const autoType: KdbxEntryAutoType = {
      enabled: stream.getUint8() === 1,
      obfuscation: stream.getUint32(true),
      items: []
    };
    autoType.defaultSequence = stream.readString();

    const itemCount = stream.getUint32(true);
    for (let i = 0; i < itemCount; i++) {
      autoType.items.push({
        window: stream.readString(),
        keystrokeSequence: stream.readString()
      });
    }
    return autoType;
  }

  private writeEditState(stream: KdbxBinaryStream, editState: KdbxEntryEditState | undefined): void {
    stream.setUint8(editState ? 1 : 0);
    if (editState) {
      stream.setUint32(editState.added.length, true);
      for (const item of editState.added) {
        stream.setUint32(item || 0, true);
      }
      stream.setUint32(editState.deleted.length, true);
      for (const item of editState.deleted) {
        stream.setUint32(item || 0, true);
      }
    }
  }

  private readEditState(stream: KdbxBinaryStream): KdbxEntryEditState | undefined {
    if (stream.getUint8() === 0) {
      return undefined;
    }
    const addedCount = stream.getUint32(true);
    const added: number[] = [];
    for (let i = 0; i < addedCount; i++) {
      added.push(stream.getUint32(true));
    }

    const deletedCount = stream.getUint32(true);
    const deleted: number[] = [];
    for (let i = 0; i < deletedCount; i++) {
      deleted.push(stream.getUint32(true));
    }
    return { "added": added, "deleted": deleted };
  }
}