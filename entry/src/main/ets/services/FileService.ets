import { Kdbx } from 'kdbxweb';
import { DbFileParam, ExportDataParam } from './TypeDefined';


/**
 * 文件服务对象
 */
export class FileService {
  private static instance: FileService = new FileService();
  private dbFileParam: DbFileParam;
  private exportDataParam: ExportDataParam;

  private constructor() {
    this.dbFileParam = {} as DbFileParam;
    this.exportDataParam = {} as ExportDataParam;
  }

  public static getInstance(): FileService {
    return FileService.instance;
  }

  public init(): void {
    this.initDbFileParam();
    this.initExportDataParam();
  }

  public static init(): void {
    FileService.instance.init();
  }

  public static close(): void {
    FileService.instance.init();
  }

  public initDbFileParam(): void {
    this.dbFileParam = {} as DbFileParam;
  }

  public initExportDataParam(): void {
    this.exportDataParam = {} as ExportDataParam;
  }

  public setDbFileParam(dbFileParam: DbFileParam): void {
    this.dbFileParam = dbFileParam;
  }

  public static setDbFileParam(dbFileParam: DbFileParam): void {
    FileService.instance.setDbFileParam(dbFileParam);
  }

  public static setExportDataParam(param: ExportDataParam): void {
    FileService.instance.exportDataParam = param;
  }

  public getDbFileParam(): DbFileParam {
    return this.dbFileParam;
  }

  public static getDbFileParam(): DbFileParam {
    return FileService.instance.getDbFileParam();
  }

  public static getExportDataParam(): ExportDataParam {
    return FileService.instance.exportDataParam;
  }

  /**
   * 重置数据库文件参数
   * @param kdbx 数据库
   * @param modifiedTime 修改时间
   * @returns 结果
   */
  public static resetDbFileParam(kdbx: Kdbx, modifiedTime: number): DbFileParam {
    FileService.getDbFileParam().database = kdbx;
    FileService.getDbFileParam().modifiedTime = modifiedTime;
    return FileService.getDbFileParam();
  }
}