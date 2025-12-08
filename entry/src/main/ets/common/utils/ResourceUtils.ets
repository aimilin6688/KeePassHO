export class ResourceUtils {
  /**
   * 判断是否是ResourceStr
   * @param resource
   * @returns
   */
  public static isResourceStr(resource: Object): boolean {
    if (typeof resource == 'string') {
      return true;
    }
    const keys = Object.keys(resource);
    return keys.indexOf('bundleName') !== -1 && keys.indexOf('id') !== -1;
  }
}