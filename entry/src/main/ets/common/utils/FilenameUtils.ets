import DateUtils from './DateUtils';
import { StringUtils } from './StringUtils';

/**
 * 文件名工具类
 */
export class FilenameUtils {
  /**
   * 获取文件名
   * @param filePath 文件路径
   */
  public static getFileName(filePath: string): string {
    if (!filePath) {
      return "";
    }
    const fileNameMatch = filePath.match(/[^/]+$/);
    return fileNameMatch ? decodeURIComponent(fileNameMatch[0]) : '';
  }

  /**
   * 替换文件名
   * @param url 文件路径
   * @param fileName 文件名
   * @returns 文件路径
   */
  public static replaceFileName(url: string, fileName: string): string {
    return url.replace(/[^/]+$/, fileName);
  }

  /**
   * 替换文件名后缀
   * @param fileName 文件名
   * @param ext 后缀
   * @returns 文件名
   */
  public static replaceExt(fileName: string, ext: string): string {
    if (!fileName) {
      return "";
    }
    // 如果文件名中没有后缀，或者最后一个字符是点，则去掉最后一个点并添加新后缀
    if (!fileName.includes('.') || fileName.endsWith('.')) {
      const trimmedFileName = fileName.endsWith('.') ? fileName.slice(0, -1) : fileName;
      return `${trimmedFileName}${ext}`;
    }
    // 替换文件名后缀为指定的后缀
    return fileName.replace(/\.[^.]+$/, ext);
  }

  /**
   * 文件名追加日期
   * @param fileName 文件名
   * @returns 添加日期后的文件名
   */
  public static fileNameAppendDate(fileName: string): string {
    if (!fileName) {
      return DateUtils.getCurrentDate();
    }
    const currentDate = DateUtils.getCurrentDate();
    const lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex === -1) {
      return `${fileName}_${currentDate}`;
    }
    const namePart = fileName.substring(0, lastDotIndex);
    const extPart = fileName.substring(lastDotIndex);
    return `${namePart}_${currentDate}${extPart}`;
  }

  /**
   * 文件名是否有指定后缀
   * @param fileName 文件名
   * @param suffixArray 后缀数组
   * @returns 是否有指定后缀
   */
  public static hasSuffix(fileName: string, suffixArray: Array<string> | undefined) {
    if (!suffixArray || suffixArray.length === 0 || !fileName) {
      return true;
    }
    for (const suffix of suffixArray) {
      if (fileName.endsWith(suffix)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 获取文件后缀
   * @param fileName 文件名
   * @returns 文件后缀
   */
  public static getFileExt(fileName: string): string {
    if (!fileName) {
      return '';
    }
    const lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex === -1) {
      return '';
    }
    return fileName.substring(lastDotIndex + 1);
  }

  /**
   * 获取文件路径，将给定的多个字符串组合成路径
   */
  public static getFilePath(...paths: string[]): string {
    // 如果是空字符串，则返回空字符串
    if (paths.length === 0) {
      return '';
    }
    // 如果字符串 以 / 开头需要去掉
    paths = paths.map(path => {
      if (!path) {
        return '';
      }
      path = path.startsWith('/') ? path.substring(1) : path;
      path = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
      return path;
    }).filter(path => StringUtils.isNotBlank(path));
    return paths.join('/');
  }
}