/**
 * 模板条目构建器
 * 使用构建器模式分步骤构建复杂条目对象
 */
import { KdbxEntry, KdbxGroup, ProtectedValue, KdbxMeta, KdbxUuid } from 'kdbxweb';
import { ITemplateField, StandardFieldKey, TemplateApplyOptions, DEFAULT_APPLY_OPTIONS, StandardFieldsMap } from './TemplateTypes';
import { KdbxUtils } from '../../common/utils/KdbxUtils';
import { FileService } from '../FileService';

/**
 * 条目构建器
 * 提供流畅的API来构建KdbxEntry
 */
export class TemplateBuilder {
  private entry: KdbxEntry;
  private parentGroup: KdbxGroup;
  private options: TemplateApplyOptions;
  private meta: KdbxMeta;

  /**
   * 私有构造函数，使用静态工厂方法创建实例
   */
  private constructor(group: KdbxGroup, meta: KdbxMeta) {
    this.parentGroup = group;
    this.meta = meta;
    this.entry = KdbxEntry.create(meta, group);
    this.options = {
      overwriteExisting: DEFAULT_APPLY_OPTIONS.overwriteExisting,
      copyTags: DEFAULT_APPLY_OPTIONS.copyTags,
      copyIcon: DEFAULT_APPLY_OPTIONS.copyIcon,
      copyExpiry: DEFAULT_APPLY_OPTIONS.copyExpiry
    };
  }

  /**
   * 创建构建器实例
   * @param group 目标分组
   * @returns 构建器实例
   */
  static create(group: KdbxGroup): TemplateBuilder {
    const meta = FileService.getInstance().getDbFileParam().database.meta;
    return new TemplateBuilder(group, meta);
  }

  /**
   * 设置标题
   */
  withTitle(title: string): TemplateBuilder {
    this.entry.fields.set('Title', title);
    return this;
  }

  /**
   * 设置用户名
   */
  withUsername(username: string): TemplateBuilder {
    this.entry.fields.set('UserName', username);
    return this;
  }

  /**
   * 设置密码
   */
  withPassword(password: string): TemplateBuilder {
    this.entry.fields.set('Password', ProtectedValue.fromString(password));
    return this;
  }

  /**
   * 设置URL
   */
  withUrl(url: string): TemplateBuilder {
    this.entry.fields.set('URL', url);
    return this;
  }

  /**
   * 设置备注
   */
  withNotes(notes: string): TemplateBuilder {
    this.entry.fields.set('Notes', notes);
    return this;
  }

  /**
   * 设置标准字段（通用方法）
   */
  withStandardField(key: StandardFieldKey, value: string): TemplateBuilder {
    if (key === 'title') {
      this.withTitle(value);
    } else if (key === 'username') {
      this.withUsername(value);
    } else if (key === 'password') {
      this.withPassword(value);
    } else if (key === 'url') {
      this.withUrl(value);
    } else if (key === 'notes') {
      this.withNotes(value);
    }
    return this;
  }

  /**
   * 批量设置标准字段
   */
  withStandardFields(fields: StandardFieldsMap): TemplateBuilder {
    if (fields.title !== undefined && fields.title !== '') {
      this.withTitle(fields.title);
    }
    if (fields.username !== undefined && fields.username !== '') {
      this.withUsername(fields.username);
    }
    if (fields.password !== undefined && fields.password !== '') {
      this.withPassword(fields.password);
    }
    if (fields.url !== undefined && fields.url !== '') {
      this.withUrl(fields.url);
    }
    if (fields.notes !== undefined && fields.notes !== '') {
      this.withNotes(fields.notes);
    }
    return this;
  }

  /**
   * 添加自定义字段
   */
  withCustomField(field: ITemplateField): TemplateBuilder {
    if (field.isProtected) {
      this.entry.fields.set(field.key, ProtectedValue.fromString(field.value));
    } else {
      this.entry.fields.set(field.key, field.value);
    }
    return this;
  }

  /**
   * 批量添加自定义字段
   */
  withCustomFields(fields: ITemplateField[]): TemplateBuilder {
    for (let i = 0; i < fields.length; i++) {
      this.withCustomField(fields[i]);
    }
    return this;
  }

  /**
   * 设置图标
   */
  withIcon(iconId: number): TemplateBuilder {
    this.entry.icon = iconId;
    return this;
  }

  /**
   * 设置自定义图标UUID
   */
  withCustomIcon(iconUuid: string): TemplateBuilder {
    this.entry.customIcon = new KdbxUuid(iconUuid);
    return this;
  }

  /**
   * 设置标签
   */
  withTags(tags: string[]): TemplateBuilder {
    if (tags && tags.length > 0) {
      this.entry.fields.set('Tags', tags.join(','));
    }
    return this;
  }

  /**
   * 设置过期时间
   */
  withExpiryTime(expiryTime: Date): TemplateBuilder {
    this.entry.times.expiryTime = expiryTime;
    this.entry.times.expires = true;
    return this;
  }

  /**
   * 设置不过期
   */
  withNoExpiry(): TemplateBuilder {
    this.entry.times.expires = false;
    return this;
  }

  /**
   * 设置构建选项
   */
  withOptions(options: TemplateApplyOptions): TemplateBuilder {
    this.options = {
      overwriteExisting: options.overwriteExisting ?? this.options.overwriteExisting,
      copyTags: options.copyTags ?? this.options.copyTags,
      copyIcon: options.copyIcon ?? this.options.copyIcon,
      copyExpiry: options.copyExpiry ?? this.options.copyExpiry
    };
    return this;
  }

  /**
   * 从现有条目复制属性
   */
  copyFrom(source: KdbxEntry, options?: TemplateApplyOptions): TemplateBuilder {
    const opts: TemplateApplyOptions = {
      overwriteExisting: options?.overwriteExisting ?? this.options.overwriteExisting,
      copyTags: options?.copyTags ?? this.options.copyTags,
      copyIcon: options?.copyIcon ?? this.options.copyIcon,
      copyExpiry: options?.copyExpiry ?? this.options.copyExpiry
    };

    // 复制标准字段
    const standardFields = ['Title', 'UserName', 'Password', 'URL', 'Notes'];
    for (let i = 0; i < standardFields.length; i++) {
      const fieldName = standardFields[i];
      const value = source.fields.get(fieldName);
      if (value) {
        const existing = this.entry.fields.get(fieldName);
        if (!existing || opts.overwriteExisting) {
          const valueStr = KdbxUtils.getValueString(value);
          if (fieldName === 'Password') {
            this.entry.fields.set(fieldName, ProtectedValue.fromString(valueStr));
          } else {
            this.entry.fields.set(fieldName, valueStr);
          }
        }
      }
    }

    // 复制自定义字段
    const self = this;
    source.fields.forEach((value, key) => {
      let isStandard = false;
      for (let i = 0; i < standardFields.length; i++) {
        if (standardFields[i] === key) {
          isStandard = true;
          break;
        }
      }
      if (!isStandard && key !== 'Tags') {
        const existing = self.entry.fields.get(key);
        if (!existing || opts.overwriteExisting) {
          const valueStr = KdbxUtils.getValueString(value);
          const isProtected = value instanceof ProtectedValue;
          if (isProtected) {
            self.entry.fields.set(key, ProtectedValue.fromString(valueStr));
          } else {
            self.entry.fields.set(key, valueStr);
          }
        }
      }
    });

    // 复制标签
    if (opts.copyTags) {
      const tags = source.fields.get('Tags');
      if (tags) {
        this.entry.fields.set('Tags', KdbxUtils.getValueString(tags));
      }
    }

    // 复制图标
    if (opts.copyIcon) {
      this.entry.icon = source.icon;
      if (source.customIcon) {
        this.entry.customIcon = source.customIcon;
      }
    }

    return this;
  }

  /**
   * 构建最终条目
   * @returns 构建完成的KdbxEntry
   */
  build(): KdbxEntry {
    // 更新创建时间
    this.entry.times.creationTime = new Date();
    this.entry.times.lastModTime = new Date();
    this.entry.times.lastAccessTime = new Date();

    return this.entry;
  }

  /**
   * 构建并添加到分组
   * @returns 构建完成并添加到分组的KdbxEntry
   */
  buildAndAdd(): KdbxEntry {
    const entry = this.build();
    // KdbxEntry.create已经将条目添加到分组，所以这里不需要再次添加
    return entry;
  }

  /**
   * 重置构建器，准备构建新条目
   */
  reset(): TemplateBuilder {
    this.entry = KdbxEntry.create(this.meta, this.parentGroup);
    this.options = {
      overwriteExisting: DEFAULT_APPLY_OPTIONS.overwriteExisting,
      copyTags: DEFAULT_APPLY_OPTIONS.copyTags,
      copyIcon: DEFAULT_APPLY_OPTIONS.copyIcon,
      copyExpiry: DEFAULT_APPLY_OPTIONS.copyExpiry
    };
    return this;
  }

  /**
   * 获取当前正在构建的条目（不完成构建）
   */
  peek(): KdbxEntry {
    return this.entry;
  }
}
