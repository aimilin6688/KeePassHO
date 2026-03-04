/**
 * 模板服务门面
 * 提供统一的模板管理接口，使用单例模式
 */
import { Kdbx, KdbxGroup, KdbxEntry, KdbxUuid } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ITemplate,
  IPresetTemplate,
  IUserTemplate,
  TemplateApplyOptions,
  TemplateCategory,
  isPresetTemplate,
  isUserTemplate
} from './TemplateTypes';
import { TemplateConstants } from './TemplateConstants';
import { TemplateFactory } from './TemplateFactory';
import { PresetTemplateStrategy } from './strategies/PresetTemplateStrategy';
import { UserTemplateStrategy } from './strategies/UserTemplateStrategy';

const DOMAIN = 0xFF00;
const TAG = 'TemplateService';

/**
 * 模板服务
 * 门面模式：统一管理模板相关操作
 */
export class TemplateService {
  private static instance: TemplateService | undefined = undefined;

  private factory: TemplateFactory;
  private presetStrategy: PresetTemplateStrategy;
  private userStrategy: UserTemplateStrategy;

  // 模板分组名称常量
  public static readonly TEMPLATES_GROUP_NAME = 'Templates';

  /**
   * 私有构造函数
   */
  private constructor() {
    this.factory = new TemplateFactory();
    this.presetStrategy = this.factory.getPresetStrategy();
    this.userStrategy = this.factory.getUserStrategy();
    hilog.info(DOMAIN, TAG, 'TemplateService initialized');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): TemplateService {
    if (!TemplateService.instance) {
      TemplateService.instance = new TemplateService();
    }
    return TemplateService.instance;
  }

  // ==================== 模板获取 ====================

  /**
   * 获取所有可用模板（预置 + 用户）
   */
  getAllTemplates(kdbx: Kdbx): ITemplate[] {
    const templates: ITemplate[] = [];

    // 添加预置模板
    const presetTemplates = this.getPresetTemplates();
    for (let i = 0; i < presetTemplates.length; i++) {
      templates.push(presetTemplates[i]);
    }

    // 添加用户模板
    if (kdbx) {
      const userTemplates = this.getUserTemplates(kdbx);
      for (let i = 0; i < userTemplates.length; i++) {
        templates.push(userTemplates[i]);
      }
    }

    return templates;
  }

  /**
   * 获取预置模板列表
   */
  getPresetTemplates(): IPresetTemplate[] {
    return this.presetStrategy.getTemplates();
  }

  /**
   * 根据分类获取预置模板
   */
  getPresetTemplatesByCategory(category: TemplateCategory): IPresetTemplate[] {
    return TemplateConstants.getTemplatesByCategory(category);
  }

  /**
   * 根据ID获取预置模板
   */
  getPresetTemplateById(id: string): IPresetTemplate | undefined {
    return TemplateConstants.getTemplateById(id);
  }

  /**
   * 获取所有模板分类
   */
  getAllCategories(): TemplateCategory[] {
    return TemplateConstants.getAllCategories();
  }

  /**
   * 获取用户自定义模板
   */
  getUserTemplates(kdbx: Kdbx): IUserTemplate[] {
    if (!kdbx) {
      return [];
    }
    return this.userStrategy.getTemplates(kdbx);
  }

  /**
   * 根据ID获取用户模板
   */
  getUserTemplateById(kdbx: Kdbx, templateId: string): IUserTemplate | null {
    const userTemplates = this.getUserTemplates(kdbx);
    for (let i = 0; i < userTemplates.length; i++) {
      if (userTemplates[i].uuid.id === templateId) {
        return userTemplates[i];
      }
    }
    return null;
  }

  // ==================== 条目创建 ====================

  /**
   * 从模板创建新条目
   * @param template 模板对象
   * @param parentGroup 目标分组
   * @param options 应用选项
   * @returns 创建的条目
   */
  createEntryFromTemplate(
    template: ITemplate,
    parentGroup: KdbxGroup,
    options?: TemplateApplyOptions
  ): KdbxEntry {
    hilog.info(DOMAIN, TAG, `Creating entry from template: ${this.getTemplateName(template)}`);
    return this.factory.createEntry(template, parentGroup, options);
  }

  /**
   * 从预置模板ID创建条目
   */
  createEntryFromPresetId(
    templateId: string,
    parentGroup: KdbxGroup,
    options?: TemplateApplyOptions
  ): KdbxEntry | null {
    const template = this.getPresetTemplateById(templateId);
    if (!template) {
      hilog.warn(DOMAIN, TAG, `Template not found: ${templateId}`);
      return null;
    }
    return this.createEntryFromTemplate(template, parentGroup, options);
  }

  /**
   * 创建空条目
   */
  createEmptyEntry(parentGroup: KdbxGroup): KdbxEntry {
    return this.factory.createEmptyEntry(parentGroup);
  }

  // ==================== 模板管理 ====================

  /**
   * 将条目保存为模板
   * @param entry 源条目
   * @param kdbx 数据库对象
   * @param templateName 模板名称（可选，默认使用条目标题）
   * @returns 创建的用户模板对象
   */
  saveAsTemplate(entry: KdbxEntry, kdbx: Kdbx, templateName?: string): IUserTemplate | null {
    try {
      // 获取或创建模板分组
      const templateGroup = this.getOrCreateTemplatesGroup(kdbx);

      // 创建模板条目
      const templateEntry = this.factory.createTemplateFromEntry(entry, templateGroup, kdbx.meta);

      // 设置模板名称
      if (templateName) {
        templateEntry.fields.set('Title', templateName);
      }

      // 更新数据库元数据
      if (!kdbx.meta.entryTemplatesGroup) {
        kdbx.meta.entryTemplatesGroup = templateGroup.uuid;
      }

      hilog.info(DOMAIN, TAG, `Saved entry as template: ${templateEntry.fields.get('Title')}`);

      // 直接从创建的模板条目构建用户模板对象
      return this.userStrategy.entryToTemplate(templateEntry);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to save as template: ${error}`);
      return null;
    }
  }

  /**
   * 删除用户模板
   */
  deleteUserTemplate(template: IUserTemplate, kdbx: Kdbx): boolean {
    try {
      const templateGroup = this.getTemplatesGroup(kdbx);
      if (!templateGroup) {
        return false;
      }

      // 查找模板条目
      const entry = this.findEntryByUuid(templateGroup, template.uuid);
      if (entry) {
        // 从分组中移除
        const index = templateGroup.entries.indexOf(entry);
        if (index > -1) {
          templateGroup.entries.splice(index, 1);
        }
        hilog.info(DOMAIN, TAG, `Deleted template: ${template.name}`);
        return true;
      }
      return false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to delete template: ${error}`);
      return false;
    }
  }

  /**
   * 更新用户模板
   */
  updateUserTemplate(
    template: IUserTemplate,
    sourceEntry: KdbxEntry,
    kdbx: Kdbx
  ): IUserTemplate | null {
    try {
      const templateGroup = this.getTemplatesGroup(kdbx);
      if (!templateGroup) {
        return null;
      }

      // 查找现有模板条目
      const existingEntry = this.findEntryByUuid(templateGroup, template.uuid);
      if (!existingEntry) {
        return null;
      }

      // 更新字段
      sourceEntry.fields.forEach((value, key) => {
        const valueStr = String(value);
        existingEntry.fields.set(key, valueStr);
      });

      // 更新时间
      existingEntry.times.lastModTime = new Date();

      hilog.info(DOMAIN, TAG, `Updated template: ${template.name}`);
      const userTemplates = this.userStrategy.getTemplates(kdbx);
      for (let i = 0; i < userTemplates.length; i++) {
        if (userTemplates[i].uuid.equals(template.uuid)) {
          return userTemplates[i];
        }
      }
      return null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update template: ${error}`);
      return null;
    }
  }

  // ==================== 模板分组管理 ====================

  /**
   * 获取模板分组
   */
  getTemplatesGroup(kdbx: Kdbx): KdbxGroup | null {
    // 首先检查数据库元数据
    if (kdbx.meta && kdbx.meta.entryTemplatesGroup) {
      const group = this.findGroupByUuid(kdbx.getDefaultGroup(), kdbx.meta.entryTemplatesGroup);
      if (group) {
        return group;
      }
    }

    // 查找名为Templates的分组
    return this.findGroupByName(kdbx.getDefaultGroup(), TemplateService.TEMPLATES_GROUP_NAME);
  }

  /**
   * 获取或创建模板分组
   */
  getOrCreateTemplatesGroup(kdbx: Kdbx): KdbxGroup {
    let templateGroup = this.getTemplatesGroup(kdbx);

    if (!templateGroup) {
      // 创建新的模板分组
      const defaultGroup = kdbx.getDefaultGroup();
      templateGroup = KdbxGroup.create(TemplateService.TEMPLATES_GROUP_NAME, defaultGroup);
      templateGroup.icon = 48; // Folder图标

      // 将新分组添加到父分组的groups数组中
      defaultGroup.groups.push(templateGroup);

      // 更新数据库元数据
      kdbx.meta.entryTemplatesGroup = templateGroup.uuid;

      hilog.info(DOMAIN, TAG, 'Created Templates group');
    }

    return templateGroup;
  }

  /**
   * 判断分组是否为模板分组
   */
  isTemplatesGroup(group: KdbxGroup, kdbx: Kdbx): boolean {
    // 检查UUID匹配
    if (kdbx.meta && kdbx.meta.entryTemplatesGroup) {
      if (group.uuid.equals(kdbx.meta.entryTemplatesGroup)) {
        return true;
      }
    }

    // 检查名称匹配
    return group.name === TemplateService.TEMPLATES_GROUP_NAME;
  }

  // ==================== 辅助方法 ====================

  /**
   * 获取模板名称
   */
  getTemplateName(template: ITemplate): string {
    if (isPresetTemplate(template)) {
      return this.presetStrategy.getTemplateName(template);
    }
    return this.userStrategy.getTemplateName(template);
  }

  /**
   * 获取模板图标ID
   */
  getTemplateIconId(template: ITemplate): number | string {
    if (isPresetTemplate(template)) {
      return this.presetStrategy.getTemplateIconId(template);
    }
    return this.userStrategy.getTemplateIconId(template);
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
   * 根据UUID查找条目
   */
  private findEntryByUuid(group: KdbxGroup, uuid: KdbxUuid): KdbxEntry | null {
    for (let i = 0; i < group.entries.length; i++) {
      if (group.entries[i].uuid.equals(uuid)) {
        return group.entries[i];
      }
    }
    for (let i = 0; i < group.groups.length; i++) {
      const found = this.findEntryByUuid(group.groups[i], uuid);
      if (found) {
        return found;
      }
    }
    return null;
  }

  /**
   * 克隆条目到目标分组
   */
  cloneEntry(entry: KdbxEntry, targetGroup: KdbxGroup, renameTitle: boolean = false): KdbxEntry {
    return this.factory.cloneEntry(entry, targetGroup, { 
      newUuid: true, 
      resetTimeInfo: true, 
      copyHistory: false, 
      renameTitle: renameTitle 
    });
  }

  /**
   * 应用模板到现有条目
   */
  applyTemplateToEntry(
    entry: KdbxEntry,
    template: ITemplate,
    options?: TemplateApplyOptions
  ): void {
    if (isPresetTemplate(template)) {
      this.presetStrategy.applyTemplate(entry, template, options);
    } else if (isUserTemplate(template)) {
      this.userStrategy.applyTemplate(entry, template, options);
    }
  }
}
