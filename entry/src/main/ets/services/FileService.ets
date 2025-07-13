import { DbFileParam, FileParam } from './TypeDefined';


/**
 * 文件服务对象
 */
export class FileService {
  private static instance: FileService;
  private fileParam: FileParam;
  private dbFileParam: DbFileParam;

  private constructor() {
    this.fileParam = {} as FileParam;
    this.dbFileParam = {} as DbFileParam;
  }

  public static getInstance(): FileService {
    if (!FileService.instance) {
      FileService.instance = new FileService();
    }
    return FileService.instance;
  }

  public setFileParam(fileParam: FileParam): void {
    this.fileParam = fileParam;
  }

  public getFileParam(): FileParam {
    return this.fileParam;
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

  public getDbFileParam(): DbFileParam {
    return this.dbFileParam;
  }
}