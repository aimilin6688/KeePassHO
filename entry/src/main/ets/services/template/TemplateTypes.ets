/**
 * 模板类型定义
 * 定义模板功能的接口和类型
 */
import { KdbxUuid } from 'kdbxweb';

/**
 * 标准字段键名
 */
export type StandardFieldKey = 'title' | 'username' | 'password' | 'url' | 'notes';

/**
 * 标准字段映射类型
 */
export interface StandardFieldsMap {
  title?: string;
  username?: string;
  password?: string;
  url?: string;
  notes?: string;
}

/**
 * 模板字段定义
 */
export interface ITemplateField {
  /** 字段名 */
  key: string;
  /** 字段名国际化资源 */
  keyRes?: Resource;
  /** 默认值 */
  value: string;
  /** 是否保护字段（加密存储） */
  isProtected: boolean;
  /** 占位提示文本 */
  placeholder?: string;
  /** 占位提示文本国际化资源 */
  placeholderRes?: Resource;
  /** 是否必填 */
  required?: boolean;
}

/**
 * 预置模板接口（系统内置，不可修改）
 */
export interface IPresetTemplate {
  /** 模板唯一标识 */
  readonly id: string;
  /** 显示名称 */
  readonly name: string;
  /** 国际化名称资源 */
  readonly nameRes?: Resource;
  /** 图标ID */
  readonly iconId: number;
  /** 标准字段默认值 */
  readonly standardFields: StandardFieldsMap;
  /** 自定义字段定义 */
  readonly customFields: ITemplateField[];
  /** 默认标签 */
  readonly tags?: string[];
  /** 模板描述 */
  readonly description?: string;
  /** 模板描述国际化资源 */
  readonly descriptionRes?: Resource;
  /** 分类 */
  readonly category?: TemplateCategory;
}

/**
 * 用户模板接口（存储在数据库中，可修改删除）
 */
export interface IUserTemplate {
  /** 条目UUID */
  uuid: KdbxUuid;
  /** 模板名称 */
  name: string;
  /** 图标ID（数字或自定义图标UUID字符串） */
  iconId: number | string;
  /** 标准字段默认值 */
  standardFields: StandardFieldsMap;
  /** 自定义字段定义 */
  customFields: ITemplateField[];
  /** 标签 */
  tags?: string[];
  /** 创建时间 */
  createdAt: Date;
  /** 修改时间 */
  updatedAt: Date;
}

/**
 * 统一模板类型
 */
export type ITemplate = IPresetTemplate | IUserTemplate;

/**
 * 模板分类枚举
 */
export enum TemplateCategory {
  /** 通用 */
  GENERAL = 'general',
  /** 身份信息 */
  IDENTITY = 'identity',
  /** 金融 */
  FINANCE = 'finance',
  /** 网络 */
  NETWORK = 'network',
  /** 开发 */
  DEVELOPMENT = 'development',
  /** 其他 */
  OTHER = 'other'
}

/**
 * 模板类型守卫：判断是否为预置模板
 */
export function isPresetTemplate(template: ITemplate): boolean {
  const t = template as IPresetTemplate;
  return t.id !== undefined;
}

/**
 * 模板类型守卫：判断是否为用户模板
 */
export function isUserTemplate(template: ITemplate): boolean {
  const t = template as IUserTemplate;
  return t.uuid !== undefined;
}

/**
 * 模板应用选项
 */
export interface TemplateApplyOptions {
  /** 是否覆盖已有字段 */
  overwriteExisting?: boolean;
  /** 是否复制标签 */
  copyTags?: boolean;
  /** 是否复制图标 */
  copyIcon?: boolean;
  /** 是否复制过期时间 */
  copyExpiry?: boolean;
}

/**
 * 默认模板应用选项
 */
export const DEFAULT_APPLY_OPTIONS: TemplateApplyOptions = {
  overwriteExisting: false,
  copyTags: true,
  copyIcon: true,
  copyExpiry: false
};
