// services/importExport/catalog/ImportFormatCatalog.ets

import { CsvFamilyDispatcherImportHandler } from '../handlers/import/CsvFamilyDispatcherImportHandler';
import { JsonFamilyDispatcherImportHandler } from '../handlers/import/JsonFamilyDispatcherImportHandler';
import { XmlImportHandler } from '../handlers/import/XmlImportHandler';
import { FormatInfo } from '../common/FormatInfo';
import { ResourceManager } from '../../../common/utils';

/**
 * 导入子格式信息（清单展示用）
 */
export interface ImportSubFormatInfo {
  /** 格式唯一标识 */
  formatId: string;
  /** 格式显示名称（品牌名 + 扩展名，中英通用，不做本地化） */
  formatName: string;
  /** 补充说明（已本地化文本，无说明为空串） */
  note: string;
}

/**
 * 导入格式分组信息
 */
export interface ImportFormatGroupInfo {
  /** 分组标识（与顶层 handler formatId 一致：CSV / JSON / XML） */
  groupId: string;
  /** 分组标签（本地化） */
  groupLabel: string;
  /** 分组描述（本地化） */
  description: string;
  /** 组内支持的子格式列表 */
  formats: ImportSubFormatInfo[];
}

/**
 * 导入格式清单聚合（单一数据源，防漂移）
 * 从真实 handler 实例构建分组清单——与运行时注册表同源：
 * 新增格式 = 签名库追加一条数据行，本清单与帮助面板 UI 零改动。
 */
export class ImportFormatCatalog {
  /**
   * 构建导入格式分组清单（CSV / JSON / XML 三组）
   */
  static getCatalog(): ImportFormatGroupInfo[] {
    const groups: ImportFormatGroupInfo[] = [];

    // CSV 组：dispatcher 家族（12 已知来源）+ 通用兜底
    const csvHandler = new CsvFamilyDispatcherImportHandler();
    const csvFormats: ImportSubFormatInfo[] = [];
    for (const format of csvHandler.getSubFormats()) {
      const isGeneric = format.formatId === 'GENERIC_CSV';
      csvFormats.push({
        formatId: format.formatId,
        formatName: format.formatName,
        note: isGeneric
          ? ResourceManager.getString($r('app.string.import_format_generic_note'))
          : ''
      });
    }
    groups.push({
      groupId: csvHandler.formatId,
      groupLabel: csvHandler.formatId,
      description: ResourceManager.getString($r('app.string.import_format_group_csv_desc')),
      formats: csvFormats
    });

    // JSON 组：Bitwarden JSON + Proton Pass JSON
    const jsonHandler = new JsonFamilyDispatcherImportHandler();
    const jsonFormats: ImportSubFormatInfo[] = [];
    for (const format of jsonHandler.getSubFormats()) {
      jsonFormats.push({
        formatId: format.formatId,
        formatName: format.formatName,
        note: ''
      });
    }
    groups.push({
      groupId: jsonHandler.formatId,
      groupLabel: jsonHandler.formatId,
      description: ResourceManager.getString($r('app.string.import_format_group_json_desc')),
      formats: jsonFormats
    });

    // XML 组：KeePass 2.x XML（叶子 handler，直接包装）
    const xmlHandler = new XmlImportHandler();
    groups.push({
      groupId: xmlHandler.formatId,
      groupLabel: xmlHandler.formatId,
      description: ResourceManager.getString($r('app.string.import_format_group_xml_desc')),
      formats: [{
        formatId: xmlHandler.formatId,
        formatName: xmlHandler.formatName,
        note: ''
      }]
    });

    return groups;
  }

  /**
   * 统计指定分组的子格式数量（副标题摘要用）
   */
  static countFormats(groups: ImportFormatGroupInfo[], groupId: string): number {
    for (const group of groups) {
      if (group.groupId === groupId) {
        return group.formats.length;
      }
    }
    return 0;
  }

  /**
   * 指定分组内的格式名列表（JSON 失败引导文案用，不硬编码品牌名）
   */
  static getFormatNames(groups: ImportFormatGroupInfo[], groupId: string): string[] {
    for (const group of groups) {
      if (group.groupId === groupId) {
        const names: string[] = [];
        for (const format of group.formats) {
          names.push(format.formatName);
        }
        return names;
      }
    }
    return [];
  }
}
