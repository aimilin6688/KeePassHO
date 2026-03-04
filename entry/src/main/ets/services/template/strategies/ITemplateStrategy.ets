/**
 * 模板策略接口
 * 定义模板操作的统一接口
 */
import { KdbxEntry, KdbxGroup, Kdbx } from 'kdbxweb';
import { ITemplate, IPresetTemplate, IUserTemplate, TemplateApplyOptions } from '../TemplateTypes';

/**
 * 模板策略接口
 * 使用策略模式分离预置模板和用户模板的处理逻辑
 */
export interface ITemplateStrategy {
  /**
   * 获取模板列表
   * @param kdbx 数据库对象（用户模板需要）
   * @returns 模板列表
   */
  getTemplates(kdbx?: Kdbx): ITemplate[];

  /**
   * 应用模板到条目
   * @param entry 目标条目
   * @param template 模板
   * @param options 应用选项
   */
  applyTemplate(entry: KdbxEntry, template: ITemplate, options?: TemplateApplyOptions): void;

  /**
   * 判断策略是否支持该模板
   * @param template 模板
   * @returns 是否支持
   */
  supports(template: ITemplate): boolean;

  /**
   * 获取模板名称
   * @param template 模板
   * @returns 显示名称
   */
  getTemplateName(template: ITemplate): string;

  /**
   * 获取模板图标ID
   * @param template 模板
   * @returns 图标ID
   */
  getTemplateIconId(template: ITemplate): number | string;
}
