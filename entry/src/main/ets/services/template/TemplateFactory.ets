/**
 * 模板工厂
 * 使用工厂模式创建模板条目
 */
import { KdbxEntry, KdbxGroup, Kdbx } from 'kdbxweb';
import { ITemplate, IPresetTemplate, IUserTemplate, TemplateApplyOptions, DEFAULT_APPLY_OPTIONS } from './TemplateTypes';
import { TemplateBuilder } from './TemplateBuilder';
import { ITemplateStrategy } from './strategies/ITemplateStrategy';
import { PresetTemplateStrategy } from './strategies/PresetTemplateStrategy';
import { UserTemplateStrategy } from './strategies/UserTemplateStrategy';

/**
 * 克隆选项接口
 */
interface CloneOptions {
  newUuid: boolean;
  resetTimeInfo: boolean;
  copyHistory: boolean;
  renameTitle: boolean;
}

/**
 * 模板工厂
 * 根据模板类型创建条目，支持策略模式
 */
export class TemplateFactory {
  private strategies: Map<string, ITemplateStrategy>;
  private presetStrategy: PresetTemplateStrategy;
  private userStrategy: UserTemplateStrategy;

  constructor() {
    this.strategies = new Map();
    this.presetStrategy = new PresetTemplateStrategy();
    this.userStrategy = new UserTemplateStrategy();

    // 注册默认策略
    this.registerStrategy('preset', this.presetStrategy);
    this.registerStrategy('user', this.userStrategy);
  }

  /**
   * 注册策略
   */
  registerStrategy(name: string, strategy: ITemplateStrategy): void {
    this.strategies.set(name, strategy);
  }

  /**
   * 获取适合的策略
   */
  private getStrategy(template: ITemplate): ITemplateStrategy | null {
    const strategyValues = this.strategies.values();
    let result = strategyValues.next();
    while (!result.done) {
      const strategy = result.value;
      if (strategy.supports(template)) {
        return strategy;
      }
      result = strategyValues.next();
    }
    return null;
  }

  /**
   * 根据模板创建新条目
   * @param template 模板对象
   * @param parentGroup 目标分组
   * @param options 应用选项
   * @returns 创建的条目
   */
  createEntry(template: ITemplate, parentGroup: KdbxGroup, options?: TemplateApplyOptions): KdbxEntry {
    const opts: TemplateApplyOptions = {
      overwriteExisting: options?.overwriteExisting ?? DEFAULT_APPLY_OPTIONS.overwriteExisting,
      copyTags: options?.copyTags ?? DEFAULT_APPLY_OPTIONS.copyTags,
      copyIcon: options?.copyIcon ?? DEFAULT_APPLY_OPTIONS.copyIcon,
      copyExpiry: options?.copyExpiry ?? DEFAULT_APPLY_OPTIONS.copyExpiry
    };
    const builder = TemplateBuilder.create(parentGroup);

    // 获取策略
    const strategy = this.getStrategy(template);
    if (strategy) {
      // 使用策略应用模板
      const entry = builder.build();
      strategy.applyTemplate(entry, template, opts);

      // 应用图标
      if (opts.copyIcon) {
        const iconId = strategy.getTemplateIconId(template);
        if (typeof iconId === 'number') {
          builder.withIcon(iconId);
        }
      }

      return entry;
    }

    // 回退：手动应用
    return this.applyTemplateManually(builder, template, opts);
  }

  /**
   * 手动应用模板（回退方案）
   */
  private applyTemplateManually(
    builder: TemplateBuilder,
    template: ITemplate,
    options: TemplateApplyOptions
  ): KdbxEntry {
    // 应用标准字段
    if (template.standardFields) {
      builder.withStandardFields(template.standardFields);
    }

    // 应用自定义字段
    if (template.customFields && template.customFields.length > 0) {
      builder.withCustomFields(template.customFields);
    }

    // 应用图标
    if (options.copyIcon) {
      const preset = template as IPresetTemplate;
      const user = template as IUserTemplate;
      const iconId = preset.id !== undefined ? preset.iconId : user.iconId;
      if (typeof iconId === 'number') {
        builder.withIcon(iconId);
      }
    }

    // 应用标签
    if (options.copyTags && template.tags) {
      builder.withTags(template.tags);
    }

    return builder.build();
  }

  /**
   * 批量创建条目
   */
  createEntries(
    templates: ITemplate[],
    parentGroup: KdbxGroup,
    options?: TemplateApplyOptions
  ): KdbxEntry[] {
    const result: KdbxEntry[] = [];
    for (let i = 0; i < templates.length; i++) {
      result.push(this.createEntry(templates[i], parentGroup, options));
    }
    return result;
  }

  /**
   * 从预置模板ID创建条目
   * @param templateId 预置模板ID
   * @param parentGroup 目标分组
   * @param options 应用选项
   * @returns 创建的条目，如果模板不存在则返回null
   */
  createEntryFromPresetId(
    templateId: string,
    parentGroup: KdbxGroup,
    options?: TemplateApplyOptions
  ): KdbxEntry | null {
    const templates = this.presetStrategy.getTemplates();
    let template: IPresetTemplate | undefined = undefined;
    for (let i = 0; i < templates.length; i++) {
      if (templates[i].id === templateId) {
        template = templates[i];
        break;
      }
    }
    if (!template) {
      return null;
    }
    return this.createEntry(template, parentGroup, options);
  }

  /**
   * 创建空条目（无模板）
   */
  createEmptyEntry(parentGroup: KdbxGroup): KdbxEntry {
    return TemplateBuilder.create(parentGroup).build();
  }

  /**
   * 从现有条目创建模板条目
   * @param sourceEntry 源条目
   * @param templateGroup 模板分组
   * @returns 模板条目
   */
  createTemplateFromEntry(sourceEntry: KdbxEntry, templateGroup: KdbxGroup): KdbxEntry {
    return this.userStrategy.createTemplateFromEntry(sourceEntry, templateGroup);
  }

  /**
   * 克隆条目
   * @param source 源条目
   * @param parentGroup 目标分组
   * @param options 克隆选项
   * @returns 克隆的条目
   */
  cloneEntry(
    source: KdbxEntry,
    parentGroup: KdbxGroup,
    options?: CloneOptions
  ): KdbxEntry {
    const opts: CloneOptions = {
      newUuid: options?.newUuid ?? true,
      resetTimeInfo: options?.resetTimeInfo ?? true,
      copyHistory: options?.copyHistory ?? false,
      renameTitle: options?.renameTitle ?? false
    };

    const builder = TemplateBuilder.create(parentGroup);

    // 复制字段
    builder.copyFrom(source, { overwriteExisting: true, copyTags: true, copyIcon: true });

    // 重命名标题
    if (opts.renameTitle) {
      const originalTitle = source.fields.get('Title');
      const titleStr = originalTitle ? String(originalTitle) : '';
      builder.withTitle(`${titleStr} - 副本`);
    }

    const entry = builder.build();

    return entry;
  }

  /**
   * 获取预置模板策略
   */
  getPresetStrategy(): PresetTemplateStrategy {
    return this.presetStrategy;
  }

  /**
   * 获取用户模板策略
   */
  getUserStrategy(): UserTemplateStrategy {
    return this.userStrategy;
  }
}
