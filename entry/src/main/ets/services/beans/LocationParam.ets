import DateUtils from '../../common/utils/DateUtils';
import { StorageConfig, StorageType } from '../kdbx/interfaces';

/**
 * 打开方式类型
 */
export enum LocationMode {
  /**
   * 保存模式，选择文件夹
   */
  SAVE = "SAVE",
  /**
   * 选择模式，选择文件
   */
  SELECT = "SELECT"
}

/**
 * 文件导入导出参数类
 */
export interface LocationInfo {
  /**
   * 模式
   */
  mode: LocationMode;

  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;
}

export interface LocationInterface {
  mode: LocationMode;
  fileName?: string;
  fileSuffix?: Array<string>;
  onLocation?: (param: LocationInfo) => void;
}

/**
 * 选择数据库位置参数定义
 */
export class LocationParam implements LocationInterface {
  mode: LocationMode;
  /**
   * 选择模式，文件后缀
   */
  fileSuffix: Array<string> = [];
  /**
   * 保存模式，文件名
   */
  fileName?: string;
  /**
   * 打开模式，选择文件
   */
  onLocation?: (param: LocationInfo) => void = () => {
  };

  /**
   * 如果是保存模式，需要设置文件名
   * @param mode 模式
   * @param fileName 文件名
   */
  private constructor(mode: LocationMode, fileSuffix?: Array<string>, fileName?: string, onLocation?: (param: LocationInfo) => void) {
    this.mode = mode;
    this.fileSuffix = fileSuffix || [];
    this.fileName = fileName;
    this.onLocation = onLocation || this.onLocation;
  }

  private static instance: LocationParam | undefined = undefined;

  /**
   * 选择模式
   * @param onLocation 选择回调
   * @return LocationParam
   */
  public static ofSelect(fileSuffix?: Array<string>, onLocation?: (param: LocationInfo) => void): LocationParam {
    LocationParam.instance = new LocationParam(LocationMode.SELECT, fileSuffix, undefined, onLocation);
    return LocationParam.instance;
  }

  /**
   * 保存模式
   * @param fileName 文件名
   * @return LocationParam
   */
  public static ofSave(fileName: string, onLocation?: (param: LocationInfo) => void): LocationParam {
    LocationParam.instance = new LocationParam(LocationMode.SAVE, undefined, fileName, onLocation);
    return LocationParam.instance;
  }

  /**
   * 保存模式
   * @param fileName 文件名
   * @return LocationParam
   */
  public static of(locationInterface: LocationInterface): LocationParam {
    LocationParam.instance = new LocationParam(locationInterface.mode, locationInterface.fileSuffix, locationInterface.fileName, locationInterface.onLocation);
    return LocationParam.instance;
  }

  public static clear() {
    LocationParam.instance = undefined;
  }

  /**
   * 获取实例, 未初始化则返回select模式
   * @return LocationParam
   */
  public static getInstance(): LocationParam {
    return LocationParam.instance || LocationParam.ofSelect();
  }

  /**
   * 是否是保存模式
   * @return boolean
   */
  public static isSaveMode(): boolean {
    return LocationMode.SAVE === LocationParam.getInstance().mode;
  }

  /**
   * 获取模式
   * @return LocationMode
   */
  public static getMode(): LocationMode {
    return LocationParam.getInstance().mode;
  }

  /**
   * 获取文件名
   * @return string
   */
  public static getFileName(): string {
    return LocationParam.getInstance().fileName || DateUtils.getCurrentDate();
  }

  /**
   * 获取文件名
   * @return string
   */
  public static getFileSuffix(): Array<string> {
    return LocationParam.getInstance().fileSuffix;
  }

  /**
   * 获取选择回调
   * @return (param: LocationInfo) => void
   */
  public static callOnLocation(param: LocationInfo): void {
    const instance = LocationParam.getInstance();
    if (instance && instance.onLocation !== undefined) {
      return instance.onLocation(param);
    }
  }
}
