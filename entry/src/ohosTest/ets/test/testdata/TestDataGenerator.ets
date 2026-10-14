import { ByteUtils, Kdbx, KdbxEntry, KdbxGroup, ProtectedValue, KdbxCredentials } from 'kdbxweb';
import { TotpAlgorithm, TotpConfig, TotpService, TotpType } from '../../../../main/ets/services/TotpService';
import { TestPngBuilder } from './TestPngBuilder';

/**
 * E2E 测试数据库数据生成器（仅存在于 ohosTest，不进入主应用）。
 *
 * 生成完整测试数据（KDBX4，默认 KDF/加密）：
 * - 多级嵌套分组（中文长名/颜色/背景，验证底部面包屑导航条自动滚动与点击切换）
 * - 标题边界（空/单字符/300 字超长/特殊字符/Emoji/多行/前后空格/重复/长英文）
 * - 密码强度边界（空/弱/中/强/256 位极强/Unicode/纯符号/128 位）
 * - TOTP 边界（SHA1/SHA256/SHA512、60 秒周期、8 位、Steam、带发行者）
 * - 附件边界（txt/json/csv/bin/多附件/50KB 大文本/无扩展名/中文名）
 * - 图片附件（16x16 / 64x64 渐变 / 多图 / 256x256 大图 / 图文混合，程序化合法 PNG）
 * - 综合条目（全字段/tags/自定义字段/历史 3 版本/过期/回收站）
 *
 * 连接方式与主密码见 docs/e2e-test-database.md。
 */
export class TestDataGenerator {
  /** 数据库名称（元数据 Name） */
  public static readonly DB_NAME: string = 'E2E-Test-Database';
  /** 数据库描述（元数据 DatabaseDescription） */
  public static readonly DB_DESCRIPTION: string =
    'SM4 资产丢失 E2E 测试数据库：多级嵌套分组 / 边界条目 / TOTP / 附件 / 图片附件，由 TestDataGenerator 自动生成';
  /** 数据库主密码（文档同步维护，勿随意变更） */
  public static readonly DB_PASSWORD: string = 'E2e-Test-123!';
  /** 默认用户名（元数据 DefaultUser） */
  public static readonly DEFAULT_USER: string = 'test-user@example.com';
  /** 历史最大条数（元数据 HistoryMaxItems） */
  public static readonly HISTORY_MAX_ITEMS: number = 10;
  /** 历史最大体积（元数据 HistoryMaxSize，字节） */
  public static readonly HISTORY_MAX_SIZE_BYTES: number = 10 * 1024 * 1024;

  /**
   * 生成完整测试数据库（内存对象，调用方负责 save 与上传）
   */
  public static async generate(): Promise<Kdbx> {
    const credentials = new KdbxCredentials(ProtectedValue.fromString(TestDataGenerator.DB_PASSWORD));
    const db = Kdbx.create(credentials, TestDataGenerator.DB_NAME);
    db.meta.desc = TestDataGenerator.DB_DESCRIPTION;
    db.meta.defaultUser = TestDataGenerator.DEFAULT_USER;
    db.meta.historyMaxItems = TestDataGenerator.HISTORY_MAX_ITEMS;
    db.meta.historyMaxSize = TestDataGenerator.HISTORY_MAX_SIZE_BYTES;
    db.meta.recycleBinEnabled = true;
    const root = db.getDefaultGroup();
    TestDataGenerator.addUsageEntry(db, root);
    TestDataGenerator.buildNetworkAccounts(db, root);
    TestDataGenerator.buildWorkAccounts(db, root);
    TestDataGenerator.buildFinanceAccounts(db, root);
    await TestDataGenerator.buildBoundaryTests(db, root);
    TestDataGenerator.buildDeepNesting(db, root);
    TestDataGenerator.buildColorGroups(db, root);
    return db;
  }

  /**
   * 递归统计分组树内条目总数
   */
  public static countEntries(group: KdbxGroup): number {
    let count = group.entries.length;
    for (let i = 0; i < group.groups.length; i++) {
      count += TestDataGenerator.countEntries(group.groups[i]);
    }
    return count;
  }

  /**
   * 递归统计分组树内子分组总数（不含自身）
   */
  public static countGroups(group: KdbxGroup): number {
    let count = group.groups.length;
    for (let i = 0; i < group.groups.length; i++) {
      count += TestDataGenerator.countGroups(group.groups[i]);
    }
    return count;
  }

  /**
   * 按名称递归查找子分组（首个命中）
   */
  public static findGroupByName(group: KdbxGroup, name: string): KdbxGroup | undefined {
    for (let i = 0; i < group.groups.length; i++) {
      const child = group.groups[i];
      if (child.name === name) {
        return child;
      }
      const found = TestDataGenerator.findGroupByName(child, name);
      if (found !== undefined) {
        return found;
      }
    }
    return undefined;
  }

  /**
   * 按标题递归查找条目（首个命中）
   */
  public static findEntryByTitle(group: KdbxGroup, title: string): KdbxEntry | undefined {
    for (let i = 0; i < group.entries.length; i++) {
      if (group.entries[i].fields.get('Title') === title) {
        return group.entries[i];
      }
    }
    for (let i = 0; i < group.groups.length; i++) {
      const found = TestDataGenerator.findEntryByTitle(group.groups[i], title);
      if (found !== undefined) {
        return found;
      }
    }
    return undefined;
  }

  private static addUsageEntry(db: Kdbx, root: KdbxGroup): void {
    const notes = '本数据库由测试代码自动生成，用于验证：多级嵌套分组（底部导航条自动滚动/点击切换）、'
      + '标题/密码强度/TOTP/附件/图片附件边界条目、修改主密码、设置元数据。\n'
      + '连接方式与主密码见 docs/e2e-test-database.md。';
    TestDataGenerator.createEntry(db, root, '使用说明（必读）', TestDataGenerator.DEFAULT_USER,
      TestDataGenerator.DB_PASSWORD, '', notes);
  }

  private static buildNetworkAccounts(db: Kdbx, root: KdbxGroup): void {
    const network = TestDataGenerator.createGroup(db, root, '网络账号', 1, '#1E88E5', undefined, '网络服务账号分组');
    const mail = TestDataGenerator.createGroup(db, network, '邮箱服务', 8);
    const qq = TestDataGenerator.createEntry(db, mail, 'QQ邮箱', 'user@qq.com', 'Qq-Mail-123!',
      'https://mail.qq.com', 'IMAP: imap.qq.com:993');
    TestDataGenerator.addTotpField(qq, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', 'QQ邮箱');
    TestDataGenerator.createEntry(db, mail, 'Gmail', 'user@gmail.com', 'Gm-Str0ng-Pass#456',
      'https://mail.google.com', '两步验证已开启');
    TestDataGenerator.createEntry(db, mail, 'Outlook', 'user@outlook.com', 'Out-look-789!',
      'https://outlook.com', '');
    const social = TestDataGenerator.createGroup(db, network, '社交平台', 5, '#8E24AA');
    TestDataGenerator.createEntry(db, social, '微信', 'wx_user', 'WeChat-Pass-111!',
      'https://weixin.qq.com', '微信账号');
    TestDataGenerator.createEntry(db, social, '微博', 'weibo_user', 'WeiBo-Pass-222!', 'https://weibo.com', '');
    TestDataGenerator.createEntry(db, social, 'Twitter X', 'twitter_user', 'Tw-X-Pass-333!', 'https://x.com', '');
    const cloud = TestDataGenerator.createGroup(db, network, '云存储', 3, undefined, '#00ACC1');
    TestDataGenerator.createEntry(db, cloud, '阿里云OSS', 'oss-user', 'Ali-OSS-Key-444!',
      'https://oss.console.aliyun.com', 'AccessKeyId 在备注');
    const aws = TestDataGenerator.createEntry(db, cloud, 'AWS S3', 'aws-user', 'Aws-S3-Key-555!',
      'https://console.aws.amazon.com', '区域 us-east-1');
    TestDataGenerator.addTotpField(aws, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', 'AWS',
      undefined, undefined, 60, 'AWS');
    TestDataGenerator.createEntry(db, cloud, '七牛云', 'qiniu-user', 'Qiniu-Key-666!', 'https://qiniu.com', '');
  }

  private static buildWorkAccounts(db: Kdbx, root: KdbxGroup): void {
    const work = TestDataGenerator.createGroup(db, root, '工作账号', 7, '#43A047', undefined, '工作相关账号');
    const office = TestDataGenerator.createGroup(db, work, '办公系统', 9);
    TestDataGenerator.createEntry(db, office, 'OA系统', 'emp001', 'Oa-System-777!',
      'https://oa.company.com', '工号 emp001');
    TestDataGenerator.createEntry(db, office, '企业VPN', 'emp001', 'Vpn-Pass-888!',
      'vpn://vpn.company.com', 'Cisco AnyConnect');
    const dev = TestDataGenerator.createGroup(db, work, '开发平台', 6, undefined, '#FDD835');
    const gitlab = TestDataGenerator.createEntry(db, dev, 'GitLab', 'dev-user', 'Git-Lab-999!',
      'https://gitlab.company.com', '内部代码仓库');
    TestDataGenerator.addTotpField(gitlab, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', 'GitLab',
      undefined, undefined, undefined, 'CompanyGitLab');
    TestDataGenerator.createEntry(db, dev, 'Jenkins', 'dev-user', 'Jenkins-000!',
      'https://ci.company.com', 'CI/CD');
    TestDataGenerator.createEntry(db, dev, '生产服务器SSH', 'root', 'Ssh-Key-111!',
      'ssh://prod.company.com', 'ssh -p 22 root@prod.company.com');
  }

  private static buildFinanceAccounts(db: Kdbx, root: KdbxGroup): void {
    const finance = TestDataGenerator.createGroup(db, root, '金融账户', 4, '#E53935', undefined, '金融类账户（重要）');
    const bank = TestDataGenerator.createGroup(db, finance, '银行账户', 0);
    TestDataGenerator.createEntry(db, bank, '招商银行', '13800138000', 'Cmb-Pass-222!',
      'https://www.cmbchina.com', '借记卡尾号 8888');
    TestDataGenerator.createEntry(db, bank, '支付宝', '13800138000', 'Alipay-Pass-333!',
      'https://www.alipay.com', '支付密码与登录密码不同');
    const invest = TestDataGenerator.createGroup(db, finance, '投资理财', 10);
    TestDataGenerator.createEntry(db, invest, '证券账户', 'stock_user', 'Stock-Pass-444!',
      'https://www.stock.com', '资金账号 66668888');
  }

  private static async buildBoundaryTests(db: Kdbx, root: KdbxGroup): Promise<void> {
    const boundary = TestDataGenerator.createGroup(db, root, '边界测试', 2, '#E53935', undefined, '各类边界条件测试数据');
    TestDataGenerator.buildTitleBoundaryEntries(db, boundary);
    TestDataGenerator.buildPasswordBoundaryEntries(db, boundary);
    TestDataGenerator.buildTotpBoundaryEntries(db, boundary);
    await TestDataGenerator.buildAttachmentBoundaryEntries(db, boundary);
    await TestDataGenerator.buildImageAttachmentEntries(db, boundary);
    TestDataGenerator.buildComprehensiveEntries(db, boundary);
  }

  private static buildTitleBoundaryEntries(db: Kdbx, boundary: KdbxGroup): void {
    const group = TestDataGenerator.createGroup(db, boundary, '标题边界测试', 2, undefined, undefined,
      '标题长度/字符集/换行/重复边界');
    TestDataGenerator.createEntry(db, group, '', 'empty-title-user', 'Empty-Title-1!', '',
      '空标题条目（Title 为空字符串）');
    TestDataGenerator.createEntry(db, group, 'A', 'single-char-user', 'Single-Char-2!', '', '单字符标题');
    let longTitle = '';
    while (longTitle.length < 300) {
      longTitle += '超长标题边界测试';
    }
    longTitle = longTitle.substring(0, 300);
    TestDataGenerator.createEntry(db, group, longTitle, 'long-title-user', 'Long-Title-3!', '',
      '超长标题（300 字符），验证列表项换行/省略');
    TestDataGenerator.createEntry(db, group, '!@#$%^&*()_+-=[]{}|;:,.<>?/\\`~\'"', 'special-user',
      'Special-Char-4!', '', '特殊字符标题');
    TestDataGenerator.createEntry(db, group, '😀🎉🔐⚡🌟手机', 'emoji-user', 'Emoji-Title-5!', '', 'Emoji 标题');
    TestDataGenerator.createEntry(db, group, '第一行标题\n第二行标题\n第三行标题', 'multiline-user',
      'Multi-Line-6!', '', '多行标题（含换行符）');
    TestDataGenerator.createEntry(db, group, '  前后有空格的标题  ', 'space-user', 'Space-Title-7!', '',
      '标题前后含空格');
    TestDataGenerator.createEntry(db, group, '重复标题', 'dup-user-1', 'Dup-Title-8!', '', '重复标题第一条');
    TestDataGenerator.createEntry(db, group, '重复标题', 'dup-user-2', 'Dup-Title-9!', '', '重复标题第二条（同名）');
    TestDataGenerator.createEntry(db, group,
      'Long English Title Boundary Test Entry With Many Words For Layout Verification', 'en-user',
      'En-Title-10!', '', '长英文标题');
  }

  private static buildPasswordBoundaryEntries(db: Kdbx, boundary: KdbxGroup): void {
    const group = TestDataGenerator.createGroup(db, boundary, '密码强度测试', 0, undefined, undefined,
      '密码强度指示器边界');
    TestDataGenerator.createEntry(db, group, '空密码条目', 'no-pass-user', '', '',
      '密码为空（强度指示器应显示最弱）');
    TestDataGenerator.createEntry(db, group, '弱密码-纯数字', 'weak-user-1', '123456', '', '常见弱密码');
    TestDataGenerator.createEntry(db, group, '弱密码-常见单词', 'weak-user-2', 'password', '', '常见弱密码');
    TestDataGenerator.createEntry(db, group, '中等密码', 'medium-user', 'Abc12345', '', '中等强度');
    TestDataGenerator.createEntry(db, group, '强密码', 'strong-user', 'Tr0ub4dor&3', '', '强密码');
    const veryStrong = TestDataGenerator.pseudoRandomString(256, 12345678,
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+');
    TestDataGenerator.createEntry(db, group, '极强密码-256位', 'very-strong-user', veryStrong, '',
      '256 位随机混合密码（强度指示器应显示最强）');
    TestDataGenerator.createEntry(db, group, 'Unicode密码', 'unicode-user', '密码测试🔐帕斯沃德ΩλЖ', '',
      '含中文/Emoji/希腊/西里尔字符');
    TestDataGenerator.createEntry(db, group, '纯符号密码', 'symbol-user', '!@#$%^&*()_+-=', '', '仅符号');
    TestDataGenerator.createEntry(db, group, '128位混合密码', 'long-user',
      TestDataGenerator.pseudoRandomString(128, 87654321,
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'), '', '128 位随机字母数字');
  }

  private static buildTotpBoundaryEntries(db: Kdbx, boundary: KdbxGroup): void {
    const group = TestDataGenerator.createGroup(db, boundary, 'TOTP令牌测试', 13, undefined, undefined,
      'TOTP 算法/位数/周期/类型边界');
    const standard = TestDataGenerator.createEntry(db, group, 'TOTP-标准SHA1-30秒', 'totp-user-1',
      'Totp-Pass-1!', '', '标准 RFC6238：SHA1 / 6 位 / 30 秒');
    TestDataGenerator.addTotpField(standard, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', '标准TOTP',
      TotpAlgorithm.SHA1, 6, 30);
    const sha256 = TestDataGenerator.createEntry(db, group, 'TOTP-SHA256算法', 'totp-user-2',
      'Totp-Pass-2!', '', 'SHA256 算法');
    TestDataGenerator.addTotpField(sha256, TotpType.RFC6238, 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP',
      'SHA256-TOTP', TotpAlgorithm.SHA256, 6, 30);
    const sha512 = TestDataGenerator.createEntry(db, group, 'TOTP-SHA512算法', 'totp-user-3',
      'Totp-Pass-3!', '', 'SHA512 算法');
    TestDataGenerator.addTotpField(sha512, TotpType.RFC6238, 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP',
      'SHA512-TOTP', TotpAlgorithm.SHA512, 6, 30);
    const period60 = TestDataGenerator.createEntry(db, group, 'TOTP-60秒周期', 'totp-user-4',
      'Totp-Pass-4!', '', '60 秒刷新周期');
    TestDataGenerator.addTotpField(period60, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', '60秒TOTP',
      TotpAlgorithm.SHA1, 6, 60);
    const digits8 = TestDataGenerator.createEntry(db, group, 'TOTP-8位数字', 'totp-user-5',
      'Totp-Pass-5!', '', '8 位验证码');
    TestDataGenerator.addTotpField(digits8, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', '8位TOTP',
      TotpAlgorithm.SHA1, 8, 30);
    const steam = TestDataGenerator.createEntry(db, group, 'TOTP-Steam令牌', 'steam-user',
      'Steam-Pass-6!', 'https://steampowered.com', 'Steam 类型令牌');
    TestDataGenerator.addTotpField(steam, TotpType.STEAM, 'JBSWY3DPEHPK3PXP', 'Steam令牌');
    const withIssuer = TestDataGenerator.createEntry(db, group, 'TOTP-带发行者', 'totp-user-7',
      'Totp-Pass-7!', '', '带 issuer 参数');
    TestDataGenerator.addTotpField(withIssuer, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', 'IssuedTOTP',
      TotpAlgorithm.SHA1, 6, 30, 'TestCorp');
    const combined = TestDataGenerator.createEntry(db, group, 'TOTP-密码组合条目', 'totp-user-8',
      'Weak-Pass-8!', '', '弱密码 + TOTP 双因素');
    TestDataGenerator.addTotpField(combined, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', '组合条目');
  }

  private static async buildAttachmentBoundaryEntries(db: Kdbx, boundary: KdbxGroup): Promise<void> {
    const group = TestDataGenerator.createGroup(db, boundary, '附件测试', 10, undefined, undefined,
      '文本/结构化/二进制/大文件/多附件边界');
    const textEntry = TestDataGenerator.createEntry(db, group, '附件-文本文件', 'attach-user-1',
      'Attach-Pass-1!', '', 'readme.txt + notes.md 两个文本附件');
    await TestDataGenerator.addTextAttachment(db, textEntry, 'readme.txt',
      'KeePassHO E2E 测试附件\n本文件由测试代码自动生成。\n用于验证文本附件的保存与读取。\n');
    await TestDataGenerator.addTextAttachment(db, textEntry, 'notes.md', '# 备注\n- 第一行\n- 第二行\n- 第三行\n');
    const jsonEntry = TestDataGenerator.createEntry(db, group, '附件-JSON文件', 'attach-user-2',
      'Attach-Pass-2!', '', 'config.json');
    await TestDataGenerator.addTextAttachment(db, jsonEntry, 'config.json',
      '{"name": "e2e-test", "version": 1, "features": ["attachment", "totp"], "nested": {"enabled": true}}');
    const csvEntry = TestDataGenerator.createEntry(db, group, '附件-CSV文件', 'attach-user-3',
      'Attach-Pass-3!', '', 'data.csv');
    await TestDataGenerator.addTextAttachment(db, csvEntry, 'data.csv', 'id,name,value\n1,foo,100\n2,bar,200\n3,baz,300\n');
    const binEntry = TestDataGenerator.createEntry(db, group, '附件-二进制文件', 'attach-user-4',
      'Attach-Pass-4!', '', 'binary.bin（1KB 伪随机字节）');
    await TestDataGenerator.addBinaryAttachment(db, binEntry, 'binary.bin',
      TestDataGenerator.pseudoRandomBytes(1024, 424242));
    const multiEntry = TestDataGenerator.createEntry(db, group, '附件-多附件条目', 'attach-user-5',
      'Attach-Pass-5!', '', '同一条目挂 4 个不同类型附件');
    await TestDataGenerator.addTextAttachment(db, multiEntry, 'file1.txt', '第一个附件内容');
    await TestDataGenerator.addTextAttachment(db, multiEntry, 'file2.json', '{"k": "v"}');
    await TestDataGenerator.addTextAttachment(db, multiEntry, 'file3.csv', 'a,b\n1,2\n');
    await TestDataGenerator.addBinaryAttachment(db, multiEntry, 'file4.bin',
      TestDataGenerator.pseudoRandomBytes(512, 999));
    const lines: string[] = [];
    let total = 0;
    let lineNo = 1;
    while (total < 51200) {
      const line = '第' + lineNo + '行：大文本附件填充内容，用于验证大文本附件的保存与读取性能。';
      lines.push(line);
      total += line.length;
      lineNo++;
    }
    const largeText = lines.join('\n');
    const largeEntry = TestDataGenerator.createEntry(db, group, '附件-50KB大文本', 'attach-user-6',
      'Attach-Pass-6!', '', 'large-50kb.txt（约 50K 字符）');
    await TestDataGenerator.addTextAttachment(db, largeEntry, 'large-50kb.txt', largeText);
    const noExtEntry = TestDataGenerator.createEntry(db, group, '附件-无扩展名', 'attach-user-7',
      'Attach-Pass-7!', '', 'LICENSE（无扩展名纯文本）');
    await TestDataGenerator.addTextAttachment(db, noExtEntry, 'LICENSE', 'MIT License\n\nCopyright (c) 2026 E2E Test\n');
    const cnEntry = TestDataGenerator.createEntry(db, group, '附件-中文名', 'attach-user-8',
      'Attach-Pass-8!', '', '中文文件名附件');
    await TestDataGenerator.addTextAttachment(db, cnEntry, '说明文件.txt',
      '这是一个中文文件名的附件，用于验证中文附件名的保存与展示。\n');
  }

  private static async buildImageAttachmentEntries(db: Kdbx, boundary: KdbxGroup): Promise<void> {
    const group = TestDataGenerator.createGroup(db, boundary, '图片附件测试', 11, undefined, undefined,
      'PNG 图片附件（程序化生成的合法 PNG）');
    const small = TestDataGenerator.createEntry(db, group, '图片-16x16小图', 'img-user-1',
      'Img-Pass-1!', '', 'icon-16x16.png（纯色小图）');
    await TestDataGenerator.addBinaryAttachment(db, small, 'icon-16x16.png',
      TestPngBuilder.buildSolidPng(16, 16, 226, 57, 57));
    const gradient = TestDataGenerator.createEntry(db, group, '图片-64x64渐变', 'img-user-2',
      'Img-Pass-2!', '', 'gradient-64x64.png（红绿渐变）');
    await TestDataGenerator.addBinaryAttachment(db, gradient, 'gradient-64x64.png',
      TestPngBuilder.buildGradientPng(64, 64));
    const multi = TestDataGenerator.createEntry(db, group, '图片-多图片条目', 'img-user-3',
      'Img-Pass-3!', '', '同一条目挂 3 张图片');
    await TestDataGenerator.addBinaryAttachment(db, multi, 'photo-1.png',
      TestPngBuilder.buildSolidPng(32, 32, 226, 57, 57));
    await TestDataGenerator.addBinaryAttachment(db, multi, 'photo-2.png',
      TestPngBuilder.buildSolidPng(32, 32, 67, 160, 71));
    await TestDataGenerator.addBinaryAttachment(db, multi, 'photo-3.png',
      TestPngBuilder.buildSolidPng(32, 32, 30, 136, 229));
    const large = TestDataGenerator.createEntry(db, group, '图片-256x256大图', 'img-user-4',
      'Img-Pass-4!', '', 'large-256x256.png（渐变大图）');
    await TestDataGenerator.addBinaryAttachment(db, large, 'large-256x256.png',
      TestPngBuilder.buildGradientPng(256, 256));
    const mixed = TestDataGenerator.createEntry(db, group, '图片-图文混合', 'img-user-5',
      'Img-Pass-5!', '', 'screenshot.png + log.txt 混合附件');
    await TestDataGenerator.addBinaryAttachment(db, mixed, 'screenshot.png',
      TestPngBuilder.buildGradientPng(48, 48));
    await TestDataGenerator.addTextAttachment(db, mixed, 'log.txt',
      '2026-10-14 10:00:00 系统启动\n2026-10-14 10:00:05 加载完成\n');
  }

  private static buildComprehensiveEntries(db: Kdbx, boundary: KdbxGroup): void {
    const group = TestDataGenerator.createGroup(db, boundary, '综合测试', 6, undefined, undefined,
      '全字段/历史/过期/回收站综合场景');
    const full = TestDataGenerator.createEntry(db, group, '综合-全字段条目', 'full-user@example.com',
      'Full-Field-Pass#123!', 'https://full.example.com/path?q=1',
      '长备注第一行\n长备注第二行\n包含特殊字符：<>&"\'\n包含 emoji：😀🔐\n包含制表符：\tEND');
    full.icon = 12;
    full.fgColor = '#1E88E5';
    full.bgColor = '#FDD835';
    full.tags = ['工作', '重要', '综合测试'];
    full.setField('自定义明文字段', '自定义字段的值 CustomValue');
    full.fields.set('受保护字段', ProtectedValue.fromString('这是受保护的自定义字段内容 SecretNote'));
    TestDataGenerator.addTotpField(full, TotpType.RFC6238, 'JBSWY3DPEHPK3PXP', '全字段条目');
    const mp = db.meta.memoryProtection;
    const history = db.createEntry(group);
    history.setField('Title', '综合-历史版本条目', mp.title);
    history.setField('UserName', 'history-user', mp.userName);
    history.setField('Password', 'History-V1-Pass', mp.password ?? true);
    history.setField('Notes', '第一版备注', mp.notes);
    history.pushHistory();
    history.setField('Password', 'History-V2-Pass', mp.password ?? true);
    history.setField('Notes', '第二版备注', mp.notes);
    history.pushHistory();
    history.setField('Password', 'History-V3-Pass', mp.password ?? true);
    history.setField('Notes', '第三版备注（当前版本）', mp.notes);
    const expired = TestDataGenerator.createEntry(db, group, '综合-已过期条目', 'expired-user',
      'Expired-Pass-1!', '', '过期时间在过去（30 天前）');
    expired.times.expires = true;
    expired.times.expiryTime = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const soon = TestDataGenerator.createEntry(db, group, '综合-即将过期条目', 'soon-user',
      'Soon-Pass-2!', '', '过期时间在 7 天后');
    soon.times.expires = true;
    soon.times.expiryTime = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const trash = TestDataGenerator.createEntry(db, group, '综合-已删除条目', 'trash-user',
      'Trash-Pass-3!', '', '该条目被移入回收站（回收站分组内可见）');
    db.remove(trash);
  }

  private static buildDeepNesting(db: Kdbx, root: KdbxGroup): void {
    const levelNames: string[] = [
      '深层嵌套-第1层-区域一',
      '深层嵌套-第2层-这是一个非常长的中文分组名称专门用来测试底部面包屑导航条的自动滚动效果是否正常工作',
      '深层嵌套-第3层-子分组A',
      '深层嵌套-第4层-继续向下嵌套的分组B',
      '深层嵌套-第5层-更深层级的分组名称也要有一定的长度C',
      '深层嵌套-第6层-接近最底层的分组名称需要足够长才能触发横向滚动D',
      '深层嵌套-第7层-最深层分组E'
    ];
    let parent = root;
    for (let i = 0; i < levelNames.length; i++) {
      parent = db.createGroup(parent, levelNames[i]);
      TestDataGenerator.createEntry(db, parent, '第' + (i + 1) + '层示例条目', 'deep-user-' + (i + 1),
        'Deep-Pass-' + (i + 1) + '!', '', '深层嵌套第 ' + (i + 1) + ' 层的示例条目');
    }
  }

  private static buildColorGroups(db: Kdbx, root: KdbxGroup): void {
    const palette = TestDataGenerator.createGroup(db, root, '颜色分组大全', 6, undefined, undefined,
      '全部预设颜色的分组（前景/背景/混合）');
    TestDataGenerator.createColorGroup(db, palette, '红色分组', '#E53935', undefined);
    TestDataGenerator.createColorGroup(db, palette, '橙色分组', '#FB8C00', undefined);
    TestDataGenerator.createColorGroup(db, palette, '柠檬绿分组', '#C0CA33', undefined);
    TestDataGenerator.createColorGroup(db, palette, '绿色分组', '#43A047', undefined);
    TestDataGenerator.createColorGroup(db, palette, '青色分组', '#00ACC1', undefined);
    TestDataGenerator.createColorGroup(db, palette, '蓝绿色分组', '#00897B', undefined);
    TestDataGenerator.createColorGroup(db, palette, '蓝色分组', '#1E88E5', undefined);
    TestDataGenerator.createColorGroup(db, palette, '靛蓝色分组', '#3949AB', undefined);
    TestDataGenerator.createColorGroup(db, palette, '紫色分组', '#8E24AA', undefined);
    TestDataGenerator.createColorGroup(db, palette, '粉色分组', '#D81B60', undefined);
    TestDataGenerator.createColorGroup(db, palette, '棕色分组', '#6D4C41', undefined);
    TestDataGenerator.createColorGroup(db, palette, '灰色分组', '#757575', undefined);
    TestDataGenerator.createColorGroup(db, palette, '黑色分组', '#212121', undefined);
    TestDataGenerator.createColorGroup(db, palette, '黄色背景分组', undefined, '#FDD835');
    TestDataGenerator.createColorGroup(db, palette, '混合配色分组', '#E53935', '#FDD835');
  }

  private static createColorGroup(db: Kdbx, parent: KdbxGroup, name: string, fg: string | undefined,
    bg: string | undefined): void {
    const fgText = fg ?? '无';
    const bgText = bg ?? '无';
    const group = TestDataGenerator.createGroup(db, parent, name, 6, fg, bg,
      name + '：fgColor=' + fgText + '，bgColor=' + bgText);
    TestDataGenerator.createEntry(db, group, name + '-示例条目', 'color-user', 'Color-Pass-1!', '',
      name + ' 下的示例条目');
  }

  private static createGroup(db: Kdbx, parent: KdbxGroup, name: string, icon: number,
    fgColor: string | undefined = undefined, bgColor: string | undefined = undefined,
    notes: string | undefined = undefined): KdbxGroup {
    const group = db.createGroup(parent, name);
    group.icon = icon;
    if (fgColor !== undefined) {
      group.fgColor = fgColor;
    }
    if (bgColor !== undefined) {
      group.bgColor = bgColor;
    }
    if (notes !== undefined) {
      group.notes = notes;
    }
    return group;
  }

  private static createEntry(db: Kdbx, group: KdbxGroup, title: string, username: string,
    password: string, url: string, notes: string): KdbxEntry {
    const entry = db.createEntry(group);
    TestDataGenerator.setEntryFields(db, entry, title, username, password, url, notes);
    return entry;
  }

  private static setEntryFields(db: Kdbx, entry: KdbxEntry, title: string, username: string,
    password: string, url: string, notes: string): void {
    const mp = db.meta.memoryProtection;
    entry.setField('Title', title, mp.title);
    entry.setField('UserName', username, mp.userName);
    entry.setField('Password', password, mp.password ?? true);
    entry.setField('URL', url, mp.url);
    entry.setField('Notes', notes, mp.notes);
  }

  private static addTotpField(entry: KdbxEntry, type: TotpType, secret: string, label: string,
    algorithm?: TotpAlgorithm, digits?: number, period?: number, issuer?: string): void {
    const config: TotpConfig = {
      type: type,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
      name: label,
      issuer: issuer
    };
    const uri = TotpService.getInstance().generateUri(config);
    entry.fields.set('otp', ProtectedValue.fromString(uri));
  }

  private static async addTextAttachment(db: Kdbx, entry: KdbxEntry, name: string,
    text: string): Promise<void> {
    const binary = await db.binaries.add(ByteUtils.stringToBuffer(text));
    entry.binaries.set(name, binary);
  }

  private static async addBinaryAttachment(db: Kdbx, entry: KdbxEntry, name: string,
    content: ArrayBuffer): Promise<void> {
    const binary = await db.binaries.add(content);
    entry.binaries.set(name, binary);
  }

  /** Lehmer 伪随机数发生器（state ∈ [1, 2147483646]，确定性可复现） */
  private static nextSeed(state: number): number {
    return (state * 48271) % 2147483647;
  }

  /** 确定性伪随机字符串（LCG + 字母表采样） */
  private static pseudoRandomString(length: number, seed: number, alphabet: string): string {
    let state = seed;
    let result = '';
    for (let i = 0; i < length; i++) {
      state = TestDataGenerator.nextSeed(state);
      result += alphabet.charAt(state % alphabet.length);
    }
    return result;
  }

  /** 确定性伪随机字节 */
  private static pseudoRandomBytes(length: number, seed: number): ArrayBuffer {
    const bytes = new Uint8Array(length);
    let state = seed;
    for (let i = 0; i < length; i++) {
      state = TestDataGenerator.nextSeed(state);
      bytes[i] = state % 256;
    }
    return bytes.buffer;
  }
}
