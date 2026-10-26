import { KdbxGroup, ByteUtils } from 'kdbxweb';
import { IImportHandler } from '../IImportHandler';
import { FileContentInfo } from '../../../../storage';
import { ImportError, ImportExportErrorCode } from '../../common/ImportExportError';
import { ResourceManager } from '../../../../common/utils';
import { BitwardenJsonImportHandler } from './BitwardenJsonImportHandler';
import { ProtonPassJsonImportHandler } from './ProtonPassJsonImportHandler';

/**
 * JSON 顶层键嗅探原始结构（报告 §4.5）
 */
interface JsonTopLevelRaw {
  encrypted?: boolean;
  folders?: Object[];
  items?: Object[];
  vaults?: Object;
}

/**
 * JSON 导入格式族调度器（M2-3，Bitwarden JSON 迁入）
 * 占据 '.json' 路由键，按顶层键嗅探分发：
 * vaults→Proton Pass JSON；items（folders 可选）→Bitwarden JSON；
 * 未知结构明确报 INVALID_FILE_FORMAT（JSON 无法启发式映射，无通用回落）
 */
export class JsonFamilyDispatcherImportHandler implements IImportHandler {
  readonly supportedExtensions: string[] = ['.json'];
  readonly formatId = 'JSON';
  readonly formatName = 'JSON';

  private readonly bitwardenHandler: BitwardenJsonImportHandler = new BitwardenJsonImportHandler();
  private readonly protonHandler: ProtonPassJsonImportHandler = new ProtonPassJsonImportHandler();

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  /**
   * 根据顶层键嗅探具体格式标识
   * @param content JSON 文本
   * @returns 具体格式 formatId（无法识别或非法 JSON 时返回空串）
   */
  detectFormatId(content: string): string {
    let raw: JsonTopLevelRaw;
    try {
      raw = JSON.parse(content);
    } catch {
      return '';
    }
    if (raw.vaults !== undefined && raw.vaults !== null) {
      return this.protonHandler.formatId;
    }
    // Bitwarden folders 为可选键，items 在顶层即认领（保持迁移前行为兼容）
    if (raw.items !== undefined && raw.items !== null) {
      return this.bitwardenHandler.formatId;
    }
    return '';
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const content = ByteUtils.bytesToString(fileContent.content);
    const formatId = this.detectFormatId(content);
    if (formatId === this.protonHandler.formatId) {
      return this.protonHandler.import(fileContent);
    }
    if (formatId === this.bitwardenHandler.formatId) {
      return this.bitwardenHandler.import(fileContent);
    }
    // 区分非法 JSON 与未知结构
    try {
      JSON.parse(content);
    } catch {
      throw new ImportError(
        ImportExportErrorCode.INVALID_JSON_FORMAT,
        ResourceManager.getString($r('app.string.import_export_invalid_format'))
      );
    }
    throw new ImportError(
      ImportExportErrorCode.INVALID_FILE_FORMAT,
      ResourceManager.getString($r('app.string.import_export_invalid_format'))
    );
  }
}
