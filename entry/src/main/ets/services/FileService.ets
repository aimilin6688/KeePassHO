import { Kdbx } from 'kdbxweb';
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

  public static init(): void {
    FileService.instance.init();
  }

  public static close():void{
    FileService.instance.init();
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