/**
 * 导入会话检测信息（单例）
 * 导入链路内 handler 嗅探到具体格式后旁路上报（不改 IImportHandler 接口签名），
 * ViewModel 在导入成功后读取 detectedFormatName 用于成功提示文案。
 * 生命周期与单次导入一致：Facade.importToCurrentDatabase 开头 reset。
 * 单线程 UI 导入流程内使用，无并发问题。
 */
export class ImportSessionInfo {
  private static instance: ImportSessionInfo | null = null;

  /** 本次导入嗅探到的具体格式标识（未检测到为空串） */
  detectedFormatId: string = '';
  /** 本次导入嗅探到的具体格式名（未检测到为空串） */
  detectedFormatName: string = '';

  static getInstance(): ImportSessionInfo {
    if (ImportSessionInfo.instance === null) {
      ImportSessionInfo.instance = new ImportSessionInfo();
    }
    return ImportSessionInfo.instance;
  }

  /** 重置会话（每次导入开始时调用） */
  reset(): void {
    this.detectedFormatId = '';
    this.detectedFormatName = '';
  }

  /** handler 上报嗅探检测结果（后报覆盖先报） */
  reportDetectedFormat(formatId: string, formatName: string): void {
    this.detectedFormatId = formatId;
    this.detectedFormatName = formatName;
  }
}
