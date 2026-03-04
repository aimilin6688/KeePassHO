/**
 * 预置模板常量定义
 * 包含20+常用模板类型
 */
import { IPresetTemplate, ITemplateField, TemplateCategory } from './TemplateTypes';
import { Icons } from '../TypeDefined';

/**
 * 模板字段快捷创建函数（带资源引用）
 */
function field(key: string, value: string, isProtected: boolean,
  placeholder: string | undefined, placeholderRes: Resource | undefined, 
  required: boolean, keyRes: Resource | undefined): ITemplateField {
  return { key, value, isProtected, placeholder, placeholderRes, required, keyRes };
}

/**
 * 保护字段快捷创建函数（带资源引用）
 */
function protectedField(key: string, value: string, placeholder: string | undefined,
  placeholderRes: Resource | undefined, required: boolean, 
  keyRes: Resource | undefined): ITemplateField {
  return { key, value, isProtected: true, placeholder, placeholderRes, required, keyRes };
}

/**
 * 预置模板常量类
 */
export class TemplateConstants {
  // ==================== 通用类 ====================

  /** 通用账户 */
  static readonly GENERAL: IPresetTemplate = {
    id: 'general',
    name: '通用账户',
    nameRes: $r('app.string.template_general'),
    iconId: Icons.Key,
    category: TemplateCategory.GENERAL,
    description: '标准的用户名/密码账户',
    descriptionRes: $r('app.string.template_desc_general'),
    standardFields: {},
    customFields: []
  };

  /** 网站登录 */
  static readonly WEBSITE: IPresetTemplate = {
    id: 'website',
    name: '网站登录',
    nameRes: $r('app.string.template_website'),
    iconId: Icons.World,
    category: TemplateCategory.GENERAL,
    description: '网站账户登录信息',
    descriptionRes: $r('app.string.template_desc_website'),
    standardFields: {},
    customFields: []
  };

  /** 邮箱账户 */
  static readonly EMAIL: IPresetTemplate = {
    id: 'email',
    name: '邮箱账户',
    nameRes: $r('app.string.template_email'),
    iconId: Icons.EMail,
    category: TemplateCategory.GENERAL,
    description: '电子邮件账户信息',
    descriptionRes: $r('app.string.template_desc_email'),
    standardFields: {},
    customFields: [
      field('SMTP服务器', '', false, 'smtp.example.com', undefined, false, $r('app.string.template_field_smtp_server')),
      field('SMTP端口', '465', false, '465/587', undefined, false, $r('app.string.template_field_smtp_port')),
      field('IMAP服务器', '', false, 'imap.example.com', undefined, false, $r('app.string.template_field_imap_server')),
      field('IMAP端口', '993', false, '993/143', undefined, false, $r('app.string.template_field_imap_port'))
    ]
  };

  // ==================== 身份信息类 ====================

  /** 身份证 */
  static readonly ID_CARD: IPresetTemplate = {
    id: 'id_card',
    name: '身份证',
    nameRes: $r('app.string.template_id_card'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: '中国居民身份证信息',
    descriptionRes: $r('app.string.template_desc_id_card'),
    standardFields: {
      notes: '身份证信息'
    },
    customFields: [
      protectedField('身份证号', '', '', $r('app.string.template_placeholder_id_card'), false, $r('app.string.template_field_id_number')),
      field('姓名', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('性别', '', false, '男/女', $r('app.string.template_placeholder_gender'), false, $r('app.string.template_field_gender')),
      field('民族', '', false, '汉族', $r('app.string.template_placeholder_ethnicity'), false, $r('app.string.template_field_ethnicity')),
      field('出生日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_birth_date')),
      field('住址', '', false, undefined, undefined, false, $r('app.string.template_field_address'))
    ]
  };

  /** 护照 */
  static readonly PASSPORT: IPresetTemplate = {
    id: 'passport',
    name: '护照',
    nameRes: $r('app.string.template_passport'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: '护照信息',
    descriptionRes: $r('app.string.template_desc_passport'),
    standardFields: {
      notes: '护照信息'
    },
    customFields: [
      protectedField('护照号码', '', undefined, undefined, false, $r('app.string.template_field_passport_number')),
      field('姓名', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('性别', '', false, '男/女', $r('app.string.template_placeholder_gender'), false, $r('app.string.template_field_gender')),
      field('国籍', '中国', false, undefined, undefined, false, $r('app.string.template_field_nationality')),
      field('出生日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_birth_date')),
      field('签发地', '', false, undefined, undefined, false, $r('app.string.template_field_issue_place')),
      field('签发日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_issue_date')),
      field('有效期至', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** 驾驶证 */
  static readonly DRIVER_LICENSE: IPresetTemplate = {
    id: 'driver_license',
    name: '驾驶证',
    nameRes: $r('app.string.template_driver_license'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: '机动车驾驶证信息',
    descriptionRes: $r('app.string.template_desc_driver_license'),
    standardFields: {
      notes: '驾驶证信息'
    },
    customFields: [
      protectedField('驾驶证号', '', undefined, undefined, false, $r('app.string.template_field_driver_license_number')),
      field('姓名', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('性别', '', false, '男/女', $r('app.string.template_placeholder_gender'), false, $r('app.string.template_field_gender')),
      field('国籍', '中国', false, undefined, undefined, false, $r('app.string.template_field_nationality')),
      field('住址', '', false, undefined, undefined, false, $r('app.string.template_field_address')),
      field('出生日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_birth_date')),
      field('准驾车型', '', false, 'C1/C2/B2等', $r('app.string.template_placeholder_vehicle_class'), false, $r('app.string.template_field_vehicle_class')),
      field('初次领证日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_first_issue_date')),
      field('有效期起始', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_valid_from')),
      field('有效期至', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** 社保卡 */
  static readonly SOCIAL_SECURITY: IPresetTemplate = {
    id: 'social_security',
    name: '社保卡',
    nameRes: $r('app.string.template_social_security'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: '社会保障卡信息',
    descriptionRes: $r('app.string.template_desc_social_security'),
    standardFields: {},
    customFields: [
      protectedField('社保卡号', '', undefined, undefined, false, $r('app.string.template_field_social_security_number')),
      field('姓名', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('身份证号', '', false, undefined, undefined, false, $r('app.string.template_field_id_number')),
      protectedField('社保密码', '', undefined, undefined, false, $r('app.string.template_field_social_security_password')),
      field('发卡地', '', false, undefined, undefined, false, $r('app.string.template_field_issue_location'))
    ]
  };

  // ==================== 金融类 ====================

  /** 银行卡 */
  static readonly BANK_CARD: IPresetTemplate = {
    id: 'bank_card',
    name: '银行卡',
    nameRes: $r('app.string.template_bank_card'),
    iconId: Icons.EMailBox,
    category: TemplateCategory.FINANCE,
    description: '银行借记卡信息',
    descriptionRes: $r('app.string.template_desc_bank_card'),
    standardFields: {},
    customFields: [
      protectedField('银行卡号', '', '', $r('app.string.template_placeholder_bank_card_number'), false, $r('app.string.template_field_bank_card_number')),
      field('持卡人', '', false, '', undefined, true, $r('app.string.template_field_card_holder')),
      field('银行名称', '', false, '', undefined, true, $r('app.string.template_field_bank_name')),
      field('卡类型', '借记卡', false, '借记卡/储蓄卡', $r('app.string.template_placeholder_card_type'), false, $r('app.string.template_field_card_type')),
      field('有效期', '', false, 'MM/YY', $r('app.string.template_placeholder_expiry'), false, $r('app.string.template_field_valid_thru')),
      protectedField('CVV', '', '', $r('app.string.template_placeholder_cvv'), false, $r('app.string.template_field_cvv')),
      protectedField('取款密码', '', undefined, undefined, false, $r('app.string.template_field_withdrawal_password')),
      field('开户行', '', false, undefined, undefined, false, $r('app.string.template_field_opening_bank'))
    ]
  };

  /** 信用卡 */
  static readonly CREDIT_CARD: IPresetTemplate = {
    id: 'credit_card',
    name: '信用卡',
    nameRes: $r('app.string.template_credit_card'),
    iconId: Icons.EMailBox,
    category: TemplateCategory.FINANCE,
    description: '信用卡信息',
    descriptionRes: $r('app.string.template_desc_credit_card'),
    standardFields: {},
    customFields: [
      protectedField('信用卡号', '', '', $r('app.string.template_placeholder_credit_card_number'), false, $r('app.string.template_field_credit_card_number')),
      field('持卡人', '', false, '', undefined, true, $r('app.string.template_field_card_holder')),
      field('发卡银行', '', false, '', undefined, true, $r('app.string.template_field_issuing_bank')),
      field('卡组织', '', false, 'Visa/Mastercard/银联等', $r('app.string.template_placeholder_card_network'), false, $r('app.string.template_field_card_network')),
      field('有效期', '', false, 'MM/YY', $r('app.string.template_placeholder_expiry'), false, $r('app.string.template_field_valid_thru')),
      protectedField('CVV', '', '', $r('app.string.template_placeholder_cvv'), false, $r('app.string.template_field_cvv')),
      protectedField('查询密码', '', undefined, undefined, false, $r('app.string.template_field_query_password')),
      protectedField('交易密码', '', undefined, undefined, false, $r('app.string.template_field_transaction_password')),
      field('信用额度', '', false, undefined, undefined, false, $r('app.string.template_field_credit_limit')),
      field('账单日', '', false, '每月几号', $r('app.string.template_placeholder_billing_day'), false, $r('app.string.template_field_billing_day')),
      field('还款日', '', false, '每月几号', $r('app.string.template_placeholder_payment_day'), false, $r('app.string.template_field_payment_day'))
    ]
  };

  /** 会员卡 */
  static readonly MEMBERSHIP: IPresetTemplate = {
    id: 'membership',
    name: '会员卡',
    nameRes: $r('app.string.template_membership'),
    iconId: Icons.Star,
    category: TemplateCategory.FINANCE,
    description: '会员卡/积分卡信息',
    descriptionRes: $r('app.string.template_desc_membership'),
    standardFields: {},
    customFields: [
      field('会员号', '', false, '', undefined, true, $r('app.string.template_field_membership_number')),
      field('会员名称', '', false, undefined, undefined, false, $r('app.string.template_field_membership_name')),
      field('会员等级', '', false, undefined, undefined, false, $r('app.string.template_field_membership_level')),
      field('积分', '', false, undefined, undefined, false, $r('app.string.template_field_points')),
      field('有效期至', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date')),
      protectedField('会员密码', '', undefined, undefined, false, $r('app.string.template_field_membership_password'))
    ]
  };

  /** 加密货币钱包 */
  static readonly CRYPTO_WALLET: IPresetTemplate = {
    id: 'crypto_wallet',
    name: '加密货币钱包',
    nameRes: $r('app.string.template_crypto_wallet'),
    iconId: Icons.Money,
    category: TemplateCategory.FINANCE,
    description: '加密货币钱包信息',
    descriptionRes: $r('app.string.template_desc_crypto_wallet'),
    standardFields: {},
    customFields: [
      field('钱包名称', '', false, undefined, undefined, false, $r('app.string.template_field_wallet_name')),
      field('链类型', '', false, 'BTC/ETH/TRON等', $r('app.string.template_placeholder_chain_type'), false, $r('app.string.template_field_chain_type')),
      field('钱包地址', '', false, undefined, undefined, false, $r('app.string.template_field_wallet_address')),
      protectedField('助记词', '', '', $r('app.string.template_placeholder_keep_safe'), false, $r('app.string.template_field_mnemonic')),
      protectedField('私钥', '', '', $r('app.string.template_placeholder_keep_safe'), false, $r('app.string.template_field_private_key')),
      protectedField('Keystore密码', '', undefined, undefined, false, $r('app.string.template_field_keystore_password'))
    ]
  };

  // ==================== 网络类 ====================

  /** WiFi网络 */
  static readonly WIFI: IPresetTemplate = {
    id: 'wifi',
    name: 'WiFi网络',
    nameRes: $r('app.string.template_wifi'),
    iconId: Icons.MultiKeys,
    category: TemplateCategory.NETWORK,
    description: 'WiFi网络信息',
    descriptionRes: $r('app.string.template_desc_wifi'),
    standardFields: {
      password: ''
    },
    customFields: [
      field('SSID', '', false, 'WiFi名称', $r('app.string.template_placeholder_ssid'), true, $r('app.string.template_field_ssid')),
      field('安全类型', 'WPA2', false, 'WPA/WPA2/WPA3/WEP', $r('app.string.template_placeholder_security_type'), false, $r('app.string.template_field_security_type')),
      field('频段', '', false, '2.4GHz/5GHz', $r('app.string.template_placeholder_frequency'), false, $r('app.string.template_field_frequency')),
      field('隐藏网络', '否', false, '是/否', $r('app.string.template_placeholder_hidden_network'), false, $r('app.string.template_field_hidden_network'))
    ]
  };

  /** VPN连接 */
  static readonly VPN: IPresetTemplate = {
    id: 'vpn',
    name: 'VPN连接',
    nameRes: $r('app.string.template_vpn'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.NETWORK,
    description: 'VPN连接信息',
    descriptionRes: $r('app.string.template_desc_vpn'),
    standardFields: {
      username: '',
      password: ''
    },
    customFields: [
      field('服务器地址', '', false, '', undefined, true, $r('app.string.template_field_server_address')),
      field('端口', '', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('协议', '', false, 'OpenVPN/WireGuard/L2TP等', $r('app.string.template_placeholder_vpn_protocol'), false, $r('app.string.template_field_protocol')),
      field('加密方式', '', false, undefined, undefined, false, $r('app.string.template_field_encryption')),
      field('CA证书', '', false, undefined, undefined, false, $r('app.string.template_field_ca_certificate')),
      field('客户端证书', '', false, undefined, undefined, false, $r('app.string.template_field_client_certificate'))
    ]
  };

  /** FTP账户 */
  static readonly FTP: IPresetTemplate = {
    id: 'ftp',
    name: 'FTP账户',
    nameRes: $r('app.string.template_ftp'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.NETWORK,
    description: 'FTP/SFTP连接信息',
    descriptionRes: $r('app.string.template_desc_ftp'),
    standardFields: {
      username: '',
      password: '',
      url: ''
    },
    customFields: [
      field('服务器地址', '', false, '', undefined, true, $r('app.string.template_field_server_address')),
      field('端口', '21', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('协议', 'FTP', false, 'FTP/SFTP', $r('app.string.template_placeholder_ftp_protocol'), false, $r('app.string.template_field_protocol')),
      field('编码', 'UTF-8', false, undefined, undefined, false, $r('app.string.template_field_encoding'))
    ]
  };

  /** 远程桌面 */
  static readonly REMOTE_DESKTOP: IPresetTemplate = {
    id: 'remote_desktop',
    name: '远程桌面',
    nameRes: $r('app.string.template_remote_desktop'),
    iconId: Icons.Monitor,
    category: TemplateCategory.NETWORK,
    description: '远程桌面连接信息',
    descriptionRes: $r('app.string.template_desc_remote_desktop'),
    standardFields: {
      username: '',
      password: ''
    },
    customFields: [
      field('主机地址', '', false, '', undefined, true, $r('app.string.template_field_host_address')),
      field('端口', '3389', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('协议', 'RDP', false, 'RDP/VNC/SSH', $r('app.string.template_placeholder_rdp_protocol'), false, $r('app.string.template_field_protocol')),
      field('域名', '', false, undefined, undefined, false, $r('app.string.template_field_domain'))
    ]
  };

  /** 路由器 */
  static readonly ROUTER: IPresetTemplate = {
    id: 'router',
    name: '路由器',
    nameRes: $r('app.string.template_router'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.NETWORK,
    description: '路由器管理信息',
    descriptionRes: $r('app.string.template_desc_router'),
    standardFields: {
      username: '',
      password: ''
    },
    customFields: [
      field('管理地址', '192.168.1.1', false, undefined, undefined, false, $r('app.string.template_field_admin_address')),
      field('SSID', '', false, undefined, undefined, false, $r('app.string.template_field_ssid')),
      field('WiFi密码', '', true, undefined, undefined, false, $r('app.string.template_field_wifi_password')),
      field('管理员密码', '', true, undefined, undefined, false, $r('app.string.template_field_admin_password'))
    ]
  };

  // ==================== 开发类 ====================

  /** SSH密钥 */
  static readonly SSH_KEY: IPresetTemplate = {
    id: 'ssh_key',
    name: 'SSH密钥',
    nameRes: $r('app.string.template_ssh_key'),
    iconId: Icons.UserKey,
    category: TemplateCategory.DEVELOPMENT,
    description: 'SSH密钥登录信息',
    descriptionRes: $r('app.string.template_desc_ssh_key'),
    standardFields: {
      username: ''
    },
    customFields: [
      field('主机', '', false, '', undefined, true, $r('app.string.template_field_host')),
      field('端口', '22', false, undefined, undefined, false, $r('app.string.template_field_port')),
      protectedField('私钥', '', '', $r('app.string.template_placeholder_pem_key'), false, $r('app.string.template_field_private_key')),
      field('公钥', '', false, '可选，用于参考', $r('app.string.template_placeholder_public_key'), false, $r('app.string.template_field_public_key')),
      field('密钥密码', '', true, '如有', $r('app.string.template_placeholder_key_passphrase'), false, $r('app.string.template_field_key_passphrase'))
    ]
  };

  /** 数据库 */
  static readonly DATABASE: IPresetTemplate = {
    id: 'database',
    name: '数据库',
    nameRes: $r('app.string.template_database'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.DEVELOPMENT,
    description: '数据库连接信息',
    descriptionRes: $r('app.string.template_desc_database'),
    standardFields: {
      username: '',
      password: ''
    },
    customFields: [
      field('数据库类型', 'MySQL', false, 'MySQL/PostgreSQL/Oracle/SQL Server/MongoDB等', $r('app.string.template_placeholder_db_type'), true, $r('app.string.template_field_db_type')),
      field('主机', '', false, '', undefined, true, $r('app.string.template_field_host')),
      field('端口', '3306', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('数据库名', '', false, '', undefined, true, $r('app.string.template_field_db_name')),
      field('字符集', 'utf8mb4', false, undefined, undefined, false, $r('app.string.template_field_charset')),
      field('连接字符串', '', false, undefined, undefined, false, $r('app.string.template_field_connection_string'))
    ]
  };

  /** 服务器 */
  static readonly SERVER: IPresetTemplate = {
    id: 'server',
    name: '服务器',
    nameRes: $r('app.string.template_server'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.DEVELOPMENT,
    description: '服务器登录信息',
    descriptionRes: $r('app.string.template_desc_server'),
    standardFields: {
      username: '',
      password: ''
    },
    customFields: [
      field('IP地址', '', false, '', undefined, true, $r('app.string.template_field_ip_address')),
      field('SSH端口', '22', false, undefined, undefined, false, $r('app.string.template_field_ssh_port')),
      field('操作系统', '', false, 'CentOS/Ubuntu/Windows等', $r('app.string.template_placeholder_os'), false, $r('app.string.template_field_os')),
      field('服务商', '', false, '阿里云/腾讯云/AWS等', $r('app.string.template_placeholder_provider'), false, $r('app.string.template_field_provider')),
      field('到期时间', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** API密钥 */
  static readonly API_KEY: IPresetTemplate = {
    id: 'api_key',
    name: 'API密钥',
    nameRes: $r('app.string.template_api_key'),
    iconId: Icons.Tool,
    category: TemplateCategory.DEVELOPMENT,
    description: 'API访问密钥信息',
    descriptionRes: $r('app.string.template_desc_api_key'),
    standardFields: {},
    customFields: [
      field('API Key', '', false, '', undefined, true, $r('app.string.template_field_api_key')),
      protectedField('API Secret', '', undefined, undefined, false, $r('app.string.template_field_api_secret')),
      field('端点URL', '', false, undefined, undefined, false, $r('app.string.template_field_endpoint_url')),
      field('所属平台', '', false, undefined, undefined, false, $r('app.string.template_field_platform')),
      field('权限范围', '', false, undefined, undefined, false, $r('app.string.template_field_scope')),
      field('有效期至', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** 软件许可证 */
  static readonly SOFTWARE_LICENSE: IPresetTemplate = {
    id: 'software_license',
    name: '软件许可证',
    nameRes: $r('app.string.template_software_license'),
    iconId: Icons.CDRom,
    category: TemplateCategory.DEVELOPMENT,
    description: '软件许可证密钥',
    descriptionRes: $r('app.string.template_desc_software_license'),
    standardFields: {},
    customFields: [
      protectedField('许可证密钥', '', undefined, undefined, true, $r('app.string.template_field_license_key')),
      field('软件名称', '', false, '', undefined, true, $r('app.string.template_field_software_name')),
      field('购买邮箱', '', false, undefined, undefined, false, $r('app.string.template_field_purchase_email')),
      field('购买日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_purchase_date')),
      field('过期日期', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date')),
      field('授权类型', '', false, '永久/订阅/教育版等', $r('app.string.template_placeholder_license_type'), false, $r('app.string.template_field_license_type')),
      field('授权设备数', '', false, undefined, undefined, false, $r('app.string.template_field_device_count'))
    ]
  };

  /** 电子签名 */
  static readonly DIGITAL_SIGNATURE: IPresetTemplate = {
    id: 'digital_signature',
    name: '电子签名',
    nameRes: $r('app.string.template_digital_signature'),
    iconId: Icons.Certificate,
    category: TemplateCategory.DEVELOPMENT,
    description: '数字证书和签名信息',
    descriptionRes: $r('app.string.template_desc_digital_signature'),
    standardFields: {},
    customFields: [
      field('证书名称', '', false, undefined, undefined, false, $r('app.string.template_field_certificate_name')),
      protectedField('证书内容', '', '', $r('app.string.template_placeholder_pem_format'), false, $r('app.string.template_field_certificate_content')),
      protectedField('私钥', '', undefined, undefined, false, $r('app.string.template_field_private_key')),
      protectedField('私钥密码', '', undefined, undefined, false, $r('app.string.template_field_private_key_password')),
      field('有效期至', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date')),
      field('颁发机构', '', false, undefined, undefined, false, $r('app.string.template_field_issuer'))
    ]
  };

  /** Git仓库 */
  static readonly GIT_REPOSITORY: IPresetTemplate = {
    id: 'git_repository',
    name: 'Git仓库',
    nameRes: $r('app.string.template_git_repository'),
    iconId: Icons.Package,
    category: TemplateCategory.DEVELOPMENT,
    description: 'Git仓库访问信息',
    descriptionRes: $r('app.string.template_desc_git_repository'),
    standardFields: {
      username: '',
      url: ''
    },
    customFields: [
      protectedField('访问令牌', '', undefined, undefined, false, $r('app.string.template_field_access_token')),
      protectedField('SSH私钥', '', undefined, undefined, false, $r('app.string.template_field_ssh_private_key')),
      field('平台', '', false, 'GitHub/GitLab/Gitee等', $r('app.string.template_placeholder_git_platform'), false, $r('app.string.template_field_git_platform')),
      field('默认分支', 'main', false, undefined, undefined, false, $r('app.string.template_field_default_branch'))
    ]
  };

  // ==================== 其他类 ====================

  /** 安全问题 */
  static readonly SECURITY_QUESTION: IPresetTemplate = {
    id: 'security_question',
    name: '安全问题',
    nameRes: $r('app.string.template_security_question'),
    iconId: Icons.Warning,
    category: TemplateCategory.OTHER,
    description: '安全问题及答案',
    descriptionRes: $r('app.string.template_desc_security_question'),
    standardFields: {},
    customFields: [
      field('问题1', '', false, '', undefined, true, $r('app.string.template_field_question1')),
      protectedField('答案1', '', undefined, undefined, true, $r('app.string.template_field_answer1')),
      field('问题2', '', false, undefined, undefined, false, $r('app.string.template_field_question2')),
      protectedField('答案2', '', undefined, undefined, false, $r('app.string.template_field_answer2')),
      field('问题3', '', false, undefined, undefined, false, $r('app.string.template_field_question3')),
      protectedField('答案3', '', undefined, undefined, false, $r('app.string.template_field_answer3'))
    ]
  };

  /** 门禁卡 */
  static readonly ACCESS_CARD: IPresetTemplate = {
    id: 'access_card',
    name: '门禁卡',
    nameRes: $r('app.string.template_access_card'),
    iconId: Icons.LockOpen,
    category: TemplateCategory.OTHER,
    description: '门禁卡信息',
    descriptionRes: $r('app.string.template_desc_access_card'),
    standardFields: {},
    customFields: [
      field('卡号', '', false, undefined, undefined, false, $r('app.string.template_field_card_number')),
      field('所属小区/公司', '', false, undefined, undefined, false, $r('app.string.template_field_community_company')),
      field('持有人', '', false, undefined, undefined, false, $r('app.string.template_field_holder')),
      field('有效期至', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /**
   * 获取所有预置模板
   */
  static getAllTemplates(): IPresetTemplate[] {
    return [
      // 通用
      TemplateConstants.GENERAL,
      TemplateConstants.WEBSITE,
      TemplateConstants.EMAIL,
      // 身份
      TemplateConstants.ID_CARD,
      TemplateConstants.PASSPORT,
      TemplateConstants.DRIVER_LICENSE,
      TemplateConstants.SOCIAL_SECURITY,
      // 金融
      TemplateConstants.BANK_CARD,
      TemplateConstants.CREDIT_CARD,
      TemplateConstants.MEMBERSHIP,
      TemplateConstants.CRYPTO_WALLET,
      // 网络
      TemplateConstants.WIFI,
      TemplateConstants.VPN,
      TemplateConstants.FTP,
      TemplateConstants.REMOTE_DESKTOP,
      TemplateConstants.ROUTER,
      // 开发
      TemplateConstants.SSH_KEY,
      TemplateConstants.DATABASE,
      TemplateConstants.SERVER,
      TemplateConstants.API_KEY,
      TemplateConstants.SOFTWARE_LICENSE,
      TemplateConstants.DIGITAL_SIGNATURE,
      TemplateConstants.GIT_REPOSITORY,
      // 其他
      TemplateConstants.SECURITY_QUESTION,
      TemplateConstants.ACCESS_CARD
    ];
  }

  /**
   * 根据ID获取预置模板
   */
  static getTemplateById(id: string): IPresetTemplate | undefined {
    return TemplateConstants.getAllTemplates().find(t => t.id === id);
  }

  /**
   * 根据分类获取模板列表
   */
  static getTemplatesByCategory(category: TemplateCategory): IPresetTemplate[] {
    return TemplateConstants.getAllTemplates().filter(t => t.category === category);
  }

  /**
   * 获取所有分类
   */
  static getAllCategories(): TemplateCategory[] {
    return [
      TemplateCategory.GENERAL,
      TemplateCategory.IDENTITY,
      TemplateCategory.FINANCE,
      TemplateCategory.NETWORK,
      TemplateCategory.DEVELOPMENT,
      TemplateCategory.OTHER
    ];
  }
}
