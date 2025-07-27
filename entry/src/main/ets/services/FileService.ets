import { DbFileParam, FileParam } from './TypeDefined';


/**
 * 文件服务对象
 */
export class FileService {
  private static instance: FileService = new FileService();
  private fileParam: FileParam;
  private dbFileParam: DbFileParam;

  private constructor() {
    this.fileParam = {} as FileParam;
    this.dbFileParam = {} as DbFileParam;
  }

  public static getInstance(): FileService {
    return FileService.instance;
  }

  public setFileParam(fileParam: FileParam): void {
    this.fileParam = fileParam;
  }

  public static setFileParam(fileParam: FileParam): void {
    FileService.instance.setFileParam(fileParam);
  }

  public getFileParam(): FileParam {
    return this.fileParam;
  }

  public static getFileParam(): FileParam {
    return FileService.instance.getFileParam();
  }

  public init(): void {
    this.initDbFileParam();
    this.initFileParam();
  }

  public initDbFileParam(): void {
    this.dbFileParam = {} as DbFileParam;
  }

  public initFileParam(): void {
    this.fileParam = {} as FileParam;
  }

  public setDbFileParam(dbFileParam: DbFileParam): void {
    this.dbFileParam = dbFileParam;
  }

  public static setDbFileParam(dbFileParam: DbFileParam): void {
    FileService.instance.setDbFileParam(dbFileParam);
  }

  public getDbFileParam(): DbFileParam {
    return this.dbFileParam;
  }

  public static getDbFileParam(): DbFileParam {
    return FileService.instance.getDbFileParam();
  }
}