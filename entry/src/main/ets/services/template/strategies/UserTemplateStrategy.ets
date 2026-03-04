/**
 * 用户模板策略
 * 处理用户自定义模板（存储在数据库中）
 */
import { KdbxEntry, KdbxGroup, Kdbx, KdbxUuid, ProtectedValue, KdbxMeta } from 'kdbxweb';
import { ITemplateStrategy } from './ITemplateStrategy';
import { IUserTemplate, ITemplate, ITemplateField, DEFAULT_APPLY_OPTIONS, TemplateApplyOptions, isUserTemplate, StandardFieldsMap } from '../TemplateTypes';
import { KdbxUtils } from '../../../common/utils/KdbxUtils';
import { FileService } from '../../FileService';

/**
 * 用户模板策略实现
 */
export class UserTemplateStrategy implements ITemplateStrategy {
  // 模板条目标识字段
  private static readonly TEMPLATE_FLAG = 'KeePassHO_Template';
  private static readonly TEMPLATE_FLAG_VALUE = 'true';

  /**
   * 获取用户模板列表
   */
  getTemplates(kdbx: Kdbx): IUserTemplate[] {
    if (!kdbx) {
      return [];
    }

    const templates: IUserTemplate[] = [];
    const templateGroup = this.findTemplatesGroup(kdbx);

    if (!templateGroup) {
      return templates;
    }

    // 遍历模板分组下的所有条目
    this.collectTemplatesFromGroup(templateGroup, templates);

    return templates;
  }

  /**
   * 递归收集分组下的模板条目
   */
  private collectTemplatesFromGroup(group: KdbxGroup, templates: IUserTemplate[]): void {
    // 收集当前分组的条目
    for (let i = 0; i < group.entries.length; i++) {
      const entry = group.entries[i];
      if (this.isTemplateEntry(entry)) {
        const template = this.entryToTemplate(entry);
        if (template) {
          templates.push(template);
        }
      }
    }

    // 递归处理子分组
    for (let i = 0; i < group.groups.length; i++) {
      this.collectTemplatesFromGroup(group.groups[i], templates);
    }
  }

  /**
   * 查找模板分组
   */
  private findTemplatesGroup(kdbx: Kdbx): KdbxGroup | null {
    // 首先检查数据库元数据中的模板分组
    if (kdbx.meta && kdbx.meta.entryTemplatesGroup) {
      const templateUuid = kdbx.meta.entryTemplatesGroup;
      const group = this.findGroupByUuid(kdbx.getDefaultGroup(), templateUuid);
      if (group) {
        return group;
      }
    }

    // 其次查找名为"Templates"的分组
    return this.findGroupByName(kdbx.getDefaultGroup(), 'Templates');
  }

  /**
   * 根据UUID查找分组
   */
  private findGroupByUuid(group: KdbxGroup, uuid: KdbxUuid): KdbxGroup | null {
    if (group.uuid.equals(uuid)) {
      return group;
    }
    for (let i = 0; i < group.groups.length; i++) {
      const found = this.findGroupByUuid(group.groups[i], uuid);
      if (found) {
        return found;
      }
    }
    return null;
  }

  /**
   * 根据名称查找分组
   */
  private findGroupByName(group: KdbxGroup, name: string): KdbxGroup | null {
    if (group.name === name) {
      return group;
    }
    for (let i = 0; i < group.groups.length; i++) {
      const found = this.findGroupByName(group.groups[i], name);
      if (found) {
        return found;
      }
    }
    return null;
  }

  /**
   * 判断条目是否为模板条目
   */
  private isTemplateEntry(entry: KdbxEntry): boolean {
    const flag = entry.fields.get(UserTemplateStrategy.TEMPLATE_FLAG);
    const flagStr = KdbxUtils.getValueString(flag);
    return flagStr === UserTemplateStrategy.TEMPLATE_FLAG_VALUE;
  }

  /**
   * 将条目转换为用户模板对象
   */
  private entryToTemplate(entry: KdbxEntry): IUserTemplate | null {
    try {
      const title = KdbxUtils.getValueString(entry.fields.get('Title')) || '未命名模板';
      const customFields: ITemplateField[] = [];

      // 收集自定义字段（排除标准字段和模板标识字段）
      const standardFields = ['Title', 'UserName', 'Password', 'URL', 'Notes', 'Tags',
        UserTemplateStrategy.TEMPLATE_FLAG];

      entry.fields.forEach((value, key) => {
        let isStandard = false;
        for (let i = 0; i < standardFields.length; i++) {
          if (standardFields[i] === key) {
            isStandard = true;
            break;
          }
        }
        if (!isStandard) {
          const valueStr = KdbxUtils.getValueString(value);
          const isProtected = value instanceof ProtectedValue;
          customFields.push({
            key: key,
            value: valueStr,
            isProtected: isProtected
          });
        }
      });

      // 提取标准字段
      const standardFieldValues: StandardFieldsMap = {};
      
      const username = entry.fields.get('UserName');
      if (username) {
        standardFieldValues.username = KdbxUtils.getValueString(username);
      }
      
      const password = entry.fields.get('Password');
      if (password) {
        standardFieldValues.password = KdbxUtils.getValueString(password);
      }
      
      const url = entry.fields.get('URL');
      if (url) {
        standardFieldValues.url = KdbxUtils.getValueString(url);
      }
      
      const notes = entry.fields.get('Notes');
      if (notes) {
        standardFieldValues.notes = KdbxUtils.getValueString(notes);
      }

      // 提取标签
      const tagsStr = KdbxUtils.getValueString(entry.fields.get('Tags'));
      let tags: string[] | undefined = undefined;
      if (tagsStr && tagsStr.length > 0) {
        tags = tagsStr.split(',').map(t => t.trim()).filter(t => t.length > 0);
      }

      // 获取图标ID
      let iconId: number | string = 0;
      if (entry.customIcon) {
        iconId = entry.customIcon.toString();
      } else if (entry.icon !== undefined) {
        iconId = entry.icon;
      }

      return {
        uuid: entry.uuid,
        name: title,
        iconId: iconId,
        standardFields: standardFieldValues,
        customFields: customFields,
        tags: tags,
        createdAt: entry.times.creationTime || new Date(),
        updatedAt: entry.times.lastModTime || new Date()
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * 应用用户模板到条目
   */
  applyTemplate(entry: KdbxEntry, template: ITemplate, options?: TemplateApplyOptions): void {
    if (!this.supports(template)) {
      return;
    }

    const userTemplate = template as IUserTemplate;
    const opts: TemplateApplyOptions = {
      overwriteExisting: options?.overwriteExisting ?? DEFAULT_APPLY_OPTIONS.overwriteExisting,
      copyTags: options?.copyTags ?? DEFAULT_APPLY_OPTIONS.copyTags,
      copyIcon: options?.copyIcon ?? DEFAULT_APPLY_OPTIONS.copyIcon,
      copyExpiry: options?.copyExpiry ?? DEFAULT_APPLY_OPTIONS.copyExpiry
    };

    // 应用标准字段
    this.applyStandardFields(entry, userTemplate, opts);

    // 应用自定义字段
    this.applyCustomFields(entry, userTemplate, opts);

    // 应用图标
    if (opts.copyIcon && userTemplate.iconId !== undefined) {
      if (typeof userTemplate.iconId === 'number') {
        entry.icon = userTemplate.iconId;
      } else {
        entry.icon = parseInt(userTemplate.iconId) || 0;
      }
    }

    // 应用标签
    if (opts.copyTags && userTemplate.tags && userTemplate.tags.length > 0) {
      const existingTags = entry.fields.get('Tags');
      if (!existingTags || opts.overwriteExisting) {
        entry.fields.set('Tags', userTemplate.tags.join(','));
      }
    }
  }

  /**
   * 应用标准字段
   */
  private applyStandardFields(entry: KdbxEntry, template: IUserTemplate, opts: TemplateApplyOptions): void {
    const fields = template.standardFields;
    
    if (fields.title !== undefined && fields.title !== '') {
      const existingValue = entry.fields.get('Title');
      if (!existingValue || opts.overwriteExisting) {
        entry.fields.set('Title', fields.title);
      }
    }
    
    if (fields.username !== undefined && fields.username !== '') {
      const existingValue = entry.fields.get('UserName');
      if (!existingValue || opts.overwriteExisting) {
        entry.fields.set('UserName', fields.username);
      }
    }
    
    if (fields.password !== undefined && fields.password !== '') {
      const existingValue = entry.fields.get('Password');
      if (!existingValue || opts.overwriteExisting) {
        entry.fields.set('Password', ProtectedValue.fromString(fields.password));
      }
    }
    
    if (fields.url !== undefined && fields.url !== '') {
      const existingValue = entry.fields.get('URL');
      if (!existingValue || opts.overwriteExisting) {
        entry.fields.set('URL', fields.url);
      }
    }
    
    if (fields.notes !== undefined && fields.notes !== '') {
      const existingValue = entry.fields.get('Notes');
      if (!existingValue || opts.overwriteExisting) {
        entry.fields.set('Notes', fields.notes);
      }
    }
  }

  /**
   * 应用自定义字段
   */
  private applyCustomFields(entry: KdbxEntry, template: IUserTemplate, opts: TemplateApplyOptions): void {
    if (!template.customFields || template.customFields.length === 0) {
      return;
    }

    for (let i = 0; i < template.customFields.length; i++) {
      const field = template.customFields[i];
      const existingValue = entry.fields.get(field.key);
      if (!existingValue || opts.overwriteExisting) {
        if (field.isProtected) {
          entry.fields.set(field.key, ProtectedValue.fromString(field.value));
        } else {
          entry.fields.set(field.key, field.value);
        }
      }
    }
  }

  /**
   * 判断是否为用户模板
   */
  supports(template: ITemplate): boolean {
    return isUserTemplate(template);
  }

  /**
   * 获取模板名称
   */
  getTemplateName(template: ITemplate): string {
    if (this.supports(template)) {
      return (template as IUserTemplate).name;
    }
    return '';
  }

  /**
   * 获取模板图标ID
   */
  getTemplateIconId(template: ITemplate): number | string {
    if (this.supports(template)) {
      return (template as IUserTemplate).iconId;
    }
    return 0;
  }

  /**
   * 将普通条目转换为模板条目
   */
  createTemplateFromEntry(entry: KdbxEntry, templateGroup: KdbxGroup): KdbxEntry {
    // 创建新条目
    const meta = FileService.getInstance().getDbFileParam().database.meta;
    const templateEntry = KdbxEntry.create(meta, templateGroup);
    
    // 复制所有字段
    const self = this;
    entry.fields.forEach((value, key) => {
      const valueStr = KdbxUtils.getValueString(value);
      const isProtected = value instanceof ProtectedValue;
      if (isProtected) {
        templateEntry.fields.set(key, ProtectedValue.fromString(valueStr));
      } else {
        templateEntry.fields.set(key, valueStr);
      }
    });

    // 设置模板标识
    templateEntry.fields.set(UserTemplateStrategy.TEMPLATE_FLAG, UserTemplateStrategy.TEMPLATE_FLAG_VALUE);

    // 复制图标
    templateEntry.icon = entry.icon;

    // 更新时间
    templateEntry.times.creationTime = new Date();
    templateEntry.times.lastModTime = new Date();

    return templateEntry;
  }
}
