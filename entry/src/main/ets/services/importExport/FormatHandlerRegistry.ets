import { IImportHandler } from './handlers/IImportHandler';
import { IExportHandler } from './handlers/IExportHandler';
import { FormatInfo } from './common/FormatInfo';

/**
 * 格式处理器注册表
 */
export class FormatHandlerRegistry {
  private importHandlers: Map<string, IImportHandler> = new Map();
  private exportHandlers: Map<string, IExportHandler> = new Map();

  private static instance: FormatHandlerRegistry;

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): FormatHandlerRegistry {
    if (!FormatHandlerRegistry.instance) {
      FormatHandlerRegistry.instance = new FormatHandlerRegistry();
    }
    return FormatHandlerRegistry.instance;
  }

  /**
   * 注册导入处理器
   */
  registerImportHandler(handler: IImportHandler): void {
    for (const ext of handler.supportedExtensions) {
      this.importHandlers.set(ext.toLowerCase(), handler);
    }
    this.importHandlers.set(handler.formatId, handler);
  }

  /**
   * 注册导出处理器
   */
  registerExportHandler(handler: IExportHandler): void {
    for (const ext of handler.supportedExtensions) {
      this.exportHandlers.set(ext.toLowerCase(), handler);
    }
    this.exportHandlers.set(handler.formatId, handler);
  }

  /**
   * 根据扩展名或格式ID获取导入处理器
   */
  getImportHandler(key: string): IImportHandler | undefined {
    return this.importHandlers.get(key.toLowerCase());
  }

  /**
   * 根据扩展名或格式ID获取导出处理器
   */
  getExportHandler(key: string): IExportHandler | undefined {
    return this.exportHandlers.get(key.toLowerCase());
  }

  /**
   * 获取所有支持的导入格式（去重）
   */
  getSupportedImportFormats(): FormatInfo[] {
    const seen = new Set<string>();
    const result: FormatInfo[] = [];

    for (const handler of this.importHandlers.values()) {
      if (!seen.has(handler.formatId)) {
        seen.add(handler.formatId);
        result.push({
          formatId: handler.formatId,
          formatName: handler.formatName,
          extensions: handler.supportedExtensions
        });
      }
    }
    return result;
  }

  /**
   * 获取所有支持的导出格式（去重）
   */
  getSupportedExportFormats(): FormatInfo[] {
    const seen = new Set<string>();
    const result: FormatInfo[] = [];

    for (const handler of this.exportHandlers.values()) {
      if (!seen.has(handler.formatId)) {
        seen.add(handler.formatId);
        result.push({
          formatId: handler.formatId,
          formatName: handler.formatName,
          extensions: handler.supportedExtensions
        });
      }
    }
    return result;
  }
}
