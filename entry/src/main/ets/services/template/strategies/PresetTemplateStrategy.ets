/**
 * 预置模板策略
 * 处理系统内置的预置模板
 */
import { KdbxEntry, ProtectedValue } from 'kdbxweb';
import { ITemplateStrategy } from './ITemplateStrategy';
import { IPresetTemplate, ITemplate, DEFAULT_APPLY_OPTIONS, TemplateApplyOptions, isPresetTemplate } from '../TemplateTypes';
import { TemplateConstants } from '../TemplateConstants';
import { ResourceManager } from '../../../common/utils';

/**
 * 预置模板策略实现
 */
export class PresetTemplateStrategy implements ITemplateStrategy {
  /**
   * 获取所有预置模板
   */
  getTemplates(): IPresetTemplate[] {
    return TemplateConstants.getAllTemplates();
  }

  /**
   * 应用预置模板到条目
   */
  applyTemplate(entry: KdbxEntry, template: ITemplate, options?: TemplateApplyOptions): void {
    if (!this.supports(template)) {
      return;
    }

    const preset = template as IPresetTemplate;
    const opts: TemplateApplyOptions = {
      overwriteExisting: options?.overwriteExisting ?? DEFAULT_APPLY_OPTIONS.overwriteExisting,
      copyTags: options?.copyTags ?? DEFAULT_APPLY_OPTIONS.copyTags,
      copyIcon: options?.copyIcon ?? DEFAULT_APPLY_OPTIONS.copyIcon,
      copyExpiry: options?.copyExpiry ?? DEFAULT_APPLY_OPTIONS.copyExpiry
    };

    // 应用标准字段
    this.applyStandardFields(entry, preset, opts);

    // 应用自定义字段
    this.applyCustomFields(entry, preset, opts);

    // 应用图标
    if (opts.copyIcon && preset.iconId !== undefined) {
      entry.icon = preset.iconId;
    }

    // 应用标签
    if (opts.copyTags && preset.tags && preset.tags.length > 0) {
      const existingTags = entry.fields.get('Tags');
      if (!existingTags || opts.overwriteExisting) {
        entry.fields.set('Tags', preset.tags.join(','));
      }
    }
  }

  /**
   * 应用标准字段
   */
  private applyStandardFields(entry: KdbxEntry, preset: IPresetTemplate, opts: TemplateApplyOptions): void {
    const fields = preset.standardFields;
    
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
  private applyCustomFields(entry: KdbxEntry, preset: IPresetTemplate, opts: TemplateApplyOptions): void {
    if (!preset.customFields || preset.customFields.length === 0) {
      return;
    }

    for (let i = 0; i < preset.customFields.length; i++) {
      const field = preset.customFields[i];
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
   * 判断是否为预置模板
   */
  supports(template: ITemplate): boolean {
    return isPresetTemplate(template);
  }

  /**
   * 获取模板名称
   */
  getTemplateName(template: ITemplate): string {
    if (this.supports(template)) {
      return ResourceManager.getString((template as IPresetTemplate).name);
    }
    return '';
  }

  /**
   * 获取模板图标ID
   */
  getTemplateIconId(template: ITemplate): number {
    if (this.supports(template)) {
      return (template as IPresetTemplate).iconId;
    }
    return 0;
  }
}
