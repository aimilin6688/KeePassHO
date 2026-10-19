/**
 * AutoOpen 条目解析结果模型
 *
 * 描述父数据库「AutoOpen」组内的一条子数据库引用条目
 * （参考 keepass2android KeeAutoExec.cs AutoExecItem）。
 */
export class AutoOpenItem {
  /** 归属父库的 iocKey（`${storageType}::${filePath}`） */
  public sourceIocKey: string = '';
  /** 条目 UUID（KdbxUuid.id，编辑/启停定位用） */
  public entryUuid: string = '';
  /** 条目父组 UUID（跳转编辑页用） */
  public parentGroupId: string = '';
  /** 显示名（Title 字段原文） */
  public title: string = '';
  /** 子库路径（URL 字段原文，未做占位符展开） */
  public url: string = '';
  /** 密钥文件路径（UserName 字段，KeePass 桌面约定） */
  public keyFilePath: string = '';
  /** 子库主密码（Password 字段明文，仅在内存中） */
  public passwordText: string = '';
  /** 远端协议连接用户名（IocUserName，WEBDAV/FTP 登录名 / S3 AccessKeyId） */
  public iocUserName: string = '';
  /** 远端协议连接密码（IocPassword，仅在内存中） */
  public iocPassword: string = '';
  /**
   * 其余自定义字符串字段原文（S3Region/S3PathStyle 等，键 = 字段名）：
   * 框架不解释内容，原样交给目标存储 childDb 适配器的 rebuildConfig 按需读取
   */
  public customStrings: Map<string, string> = new Map();
  /** 条目总开关（Expires / 自定义 Enabled 综合判定） */
  public enabled: boolean = true;
  /** 是否在切换界面展示（自定义 Visible，默认 true） */
  public visible: boolean = true;
  /** 打开顺序（自定义 Priority，默认按扫描顺序） */
  public priority: number = 0;
  /** 设备 CSV 过滤原文（自定义 IfDevice，空串表示不过滤） */
  public ifDeviceRaw: string = '';
  /** 打开前检查子库文件存在（自定义 SkipIfNotExists / 旧名） */
  public skipIfNotExists: boolean = false;
  /** 密钥文件不存在时静默跳过（自定义 SkipIfKeyFileNotExists） */
  public skipIfKeyFileNotExists: boolean = false;
  /** 条目图标 ID（UI 展示用） */
  public iconId: number = 0;
  /** 自定义图标 UUID（UI 展示用，空串表示无） */
  public customIconId: string = '';
  /** 条目最近修改时间（毫秒，列表排序用） */
  public lastModificationTime: number = 0;
}
