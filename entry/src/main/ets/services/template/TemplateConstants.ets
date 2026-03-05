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
    name: $r('app.string.template_general'),
    iconId: Icons.Key,
    category: TemplateCategory.GENERAL,
    description: $r('app.string.template_desc_general'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: []
  };

  /** 网站登录 */
  static readonly WEBSITE: IPresetTemplate = {
    id: 'website',
    name: $r('app.string.template_website'),
    iconId: Icons.World,
    category: TemplateCategory.GENERAL,
    description: $r('app.string.template_desc_website'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: []
  };

  /** 邮箱账户 */
  static readonly EMAIL: IPresetTemplate = {
    id: 'email',
    name: $r('app.string.template_email'),
    iconId: Icons.EMail,
    category: TemplateCategory.GENERAL,
    description: $r('app.string.template_desc_email'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('smtp_server', '', false, 'smtp.example.com', undefined, false, $r('app.string.template_field_smtp_server')),
      field('smtp_port', '465', false, '465/587', undefined, false, $r('app.string.template_field_smtp_port')),
      field('imap_server', '', false, 'imap.example.com', undefined, false, $r('app.string.template_field_imap_server')),
      field('imap_port', '993', false, '993/143', undefined, false, $r('app.string.template_field_imap_port'))
    ]
  };

  // ==================== 身份信息类 ====================

  /** 身份证 */
  static readonly ID_CARD: IPresetTemplate = {
    id: 'id_card',
    name: $r('app.string.template_id_card'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: $r('app.string.template_desc_id_card'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('id_number', '', '', $r('app.string.template_placeholder_id_card'), false, $r('app.string.template_field_id_number')),
      field('name', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('gender', '', false, '男/女', $r('app.string.template_placeholder_gender'), false, $r('app.string.template_field_gender')),
      field('ethnicity', '', false, '汉族', $r('app.string.template_placeholder_ethnicity'), false, $r('app.string.template_field_ethnicity')),
      field('birth_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_birth_date')),
      field('address', '', false, undefined, undefined, false, $r('app.string.template_field_address'))
    ]
  };

  /** 护照 */
  static readonly PASSPORT: IPresetTemplate = {
    id: 'passport',
    name: $r('app.string.template_passport'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: $r('app.string.template_desc_passport'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('passport_number', '', undefined, undefined, false, $r('app.string.template_field_passport_number')),
      field('name', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('gender', '', false, '男/女', $r('app.string.template_placeholder_gender'), false, $r('app.string.template_field_gender')),
      field('nationality', '中国', false, undefined, undefined, false, $r('app.string.template_field_nationality')),
      field('birth_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_birth_date')),
      field('issue_place', '', false, undefined, undefined, false, $r('app.string.template_field_issue_place')),
      field('issue_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_issue_date')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** 驾驶证 */
  static readonly DRIVER_LICENSE: IPresetTemplate = {
    id: 'driver_license',
    name: $r('app.string.template_driver_license'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: $r('app.string.template_desc_driver_license'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('driver_license_number', '', undefined, undefined, false, $r('app.string.template_field_driver_license_number')),
      field('name', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('gender', '', false, '男/女', $r('app.string.template_placeholder_gender'), false, $r('app.string.template_field_gender')),
      field('nationality', '中国', false, undefined, undefined, false, $r('app.string.template_field_nationality')),
      field('address', '', false, undefined, undefined, false, $r('app.string.template_field_address')),
      field('birth_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_birth_date')),
      field('vehicle_class', '', false, 'C1/C2/B2等', $r('app.string.template_placeholder_vehicle_class'), false, $r('app.string.template_field_vehicle_class')),
      field('first_issue_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_first_issue_date')),
      field('valid_from', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_valid_from')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** 社保卡 */
  static readonly SOCIAL_SECURITY: IPresetTemplate = {
    id: 'social_security',
    name: $r('app.string.template_social_security'),
    iconId: Icons.Identity,
    category: TemplateCategory.IDENTITY,
    description: $r('app.string.template_desc_social_security'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('social_security_number', '', undefined, undefined, false, $r('app.string.template_field_social_security_number')),
      field('name', '', false, '', undefined, true, $r('app.string.template_field_name')),
      field('id_number', '', false, undefined, undefined, false, $r('app.string.template_field_id_number')),
      protectedField('social_security_password', '', undefined, undefined, false, $r('app.string.template_field_social_security_password')),
      field('issue_location', '', false, undefined, undefined, false, $r('app.string.template_field_issue_location'))
    ]
  };

  // ==================== 金融类 ====================

  /** 银行卡 */
  static readonly BANK_CARD: IPresetTemplate = {
    id: 'bank_card',
    name: $r('app.string.template_bank_card'),
    iconId: Icons.EMailBox,
    category: TemplateCategory.FINANCE,
    description: $r('app.string.template_desc_bank_card'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('bank_card_number', '', '', $r('app.string.template_placeholder_bank_card_number'), false, $r('app.string.template_field_bank_card_number')),
      field('card_holder', '', false, '', undefined, true, $r('app.string.template_field_card_holder')),
      field('bank_name', '', false, '', undefined, true, $r('app.string.template_field_bank_name')),
      field('card_type', '借记卡', false, '借记卡/储蓄卡', $r('app.string.template_placeholder_card_type'), false, $r('app.string.template_field_card_type')),
      field('valid_thru', '', false, 'MM/YY', $r('app.string.template_placeholder_expiry'), false, $r('app.string.template_field_valid_thru')),
      protectedField('cvv', '', '', $r('app.string.template_placeholder_cvv'), false, $r('app.string.template_field_cvv')),
      protectedField('withdrawal_password', '', undefined, undefined, false, $r('app.string.template_field_withdrawal_password')),
      field('opening_bank', '', false, undefined, undefined, false, $r('app.string.template_field_opening_bank'))
    ]
  };

  /** 信用卡 */
  static readonly CREDIT_CARD: IPresetTemplate = {
    id: 'credit_card',
    name: $r('app.string.template_credit_card'),
    iconId: Icons.EMailBox,
    category: TemplateCategory.FINANCE,
    description: $r('app.string.template_desc_credit_card'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('credit_card_number', '', '', $r('app.string.template_placeholder_credit_card_number'), false, $r('app.string.template_field_credit_card_number')),
      field('card_holder', '', false, '', undefined, true, $r('app.string.template_field_card_holder')),
      field('issuing_bank', '', false, '', undefined, true, $r('app.string.template_field_issuing_bank')),
      field('card_network', '', false, 'Visa/Mastercard/银联等', $r('app.string.template_placeholder_card_network'), false, $r('app.string.template_field_card_network')),
      field('valid_thru', '', false, 'MM/YY', $r('app.string.template_placeholder_expiry'), false, $r('app.string.template_field_valid_thru')),
      protectedField('cvv', '', '', $r('app.string.template_placeholder_cvv'), false, $r('app.string.template_field_cvv')),
      protectedField('query_password', '', undefined, undefined, false, $r('app.string.template_field_query_password')),
      protectedField('transaction_password', '', undefined, undefined, false, $r('app.string.template_field_transaction_password')),
      field('credit_limit', '', false, undefined, undefined, false, $r('app.string.template_field_credit_limit')),
      field('billing_day', '', false, '每月几号', $r('app.string.template_placeholder_billing_day'), false, $r('app.string.template_field_billing_day')),
      field('payment_day', '', false, '每月几号', $r('app.string.template_placeholder_payment_day'), false, $r('app.string.template_field_payment_day'))
    ]
  };

  /** 会员卡 */
  static readonly MEMBERSHIP: IPresetTemplate = {
    id: 'membership',
    name: $r('app.string.template_membership'),
    iconId: Icons.Star,
    category: TemplateCategory.FINANCE,
    description: $r('app.string.template_desc_membership'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('membership_number', '', false, '', undefined, true, $r('app.string.template_field_membership_number')),
      field('membership_name', '', false, undefined, undefined, false, $r('app.string.template_field_membership_name')),
      field('membership_level', '', false, undefined, undefined, false, $r('app.string.template_field_membership_level')),
      field('points', '', false, undefined, undefined, false, $r('app.string.template_field_points')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date')),
      protectedField('membership_password', '', undefined, undefined, false, $r('app.string.template_field_membership_password'))
    ]
  };

  /** 加密货币钱包 */
  static readonly CRYPTO_WALLET: IPresetTemplate = {
    id: 'crypto_wallet',
    name: $r('app.string.template_crypto_wallet'),
    iconId: Icons.Money,
    category: TemplateCategory.FINANCE,
    description: $r('app.string.template_desc_crypto_wallet'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('wallet_name', '', false, undefined, undefined, false, $r('app.string.template_field_wallet_name')),
      field('chain_type', '', false, 'BTC/ETH/TRON等', $r('app.string.template_placeholder_chain_type'), false, $r('app.string.template_field_chain_type')),
      field('wallet_address', '', false, undefined, undefined, false, $r('app.string.template_field_wallet_address')),
      protectedField('mnemonic', '', '', $r('app.string.template_placeholder_keep_safe'), false, $r('app.string.template_field_mnemonic')),
      protectedField('private_key', '', '', $r('app.string.template_placeholder_keep_safe'), false, $r('app.string.template_field_private_key')),
      protectedField('keystore_password', '', undefined, undefined, false, $r('app.string.template_field_keystore_password'))
    ]
  };

  // ==================== 网络类 ====================

  /** WiFi网络 */
  static readonly WIFI: IPresetTemplate = {
    id: 'wifi',
    name: $r('app.string.template_wifi'),
    iconId: Icons.MultiKeys,
    category: TemplateCategory.NETWORK,
    description: $r('app.string.template_desc_wifi'),
    standardFields: {
      password: '',
      notes: ''
    },
    customFields: [
      field('ssid', '', false, 'WiFi名称', $r('app.string.template_placeholder_ssid'), true, $r('app.string.template_field_ssid')),
      field('security_type', 'WPA2', false, 'WPA/WPA2/WPA3/WEP', $r('app.string.template_placeholder_security_type'), false, $r('app.string.template_field_security_type')),
      field('frequency', '', false, '2.4GHz/5GHz', $r('app.string.template_placeholder_frequency'), false, $r('app.string.template_field_frequency')),
      field('hidden_network', '否', false, '是/否', $r('app.string.template_placeholder_hidden_network'), false, $r('app.string.template_field_hidden_network'))
    ]
  };

  /** VPN连接 */
  static readonly VPN: IPresetTemplate = {
    id: 'vpn',
    name: $r('app.string.template_vpn'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.NETWORK,
    description: $r('app.string.template_desc_vpn'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('server_address', '', false, '', undefined, true, $r('app.string.template_field_server_address')),
      field('port', '', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('protocol', '', false, 'OpenVPN/WireGuard/L2TP等', $r('app.string.template_placeholder_vpn_protocol'), false, $r('app.string.template_field_protocol')),
      field('encryption', '', false, undefined, undefined, false, $r('app.string.template_field_encryption')),
      field('ca_certificate', '', false, undefined, undefined, false, $r('app.string.template_field_ca_certificate')),
      field('client_certificate', '', false, undefined, undefined, false, $r('app.string.template_field_client_certificate'))
    ]
  };

  /** FTP账户 */
  static readonly FTP: IPresetTemplate = {
    id: 'ftp',
    name: $r('app.string.template_ftp'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.NETWORK,
    description: $r('app.string.template_desc_ftp'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('server_address', '', false, '', undefined, true, $r('app.string.template_field_server_address')),
      field('port', '21', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('protocol', 'FTP', false, 'FTP/SFTP', $r('app.string.template_placeholder_ftp_protocol'), false, $r('app.string.template_field_protocol')),
      field('encoding', 'UTF-8', false, undefined, undefined, false, $r('app.string.template_field_encoding'))
    ]
  };

  /** 远程桌面 */
  static readonly REMOTE_DESKTOP: IPresetTemplate = {
    id: 'remote_desktop',
    name: $r('app.string.template_remote_desktop'),
    iconId: Icons.Monitor,
    category: TemplateCategory.NETWORK,
    description: $r('app.string.template_desc_remote_desktop'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('host_address', '', false, '', undefined, true, $r('app.string.template_field_host_address')),
      field('port', '3389', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('protocol', 'RDP', false, 'RDP/VNC/SSH', $r('app.string.template_placeholder_rdp_protocol'), false, $r('app.string.template_field_protocol')),
      field('domain', '', false, undefined, undefined, false, $r('app.string.template_field_domain'))
    ]
  };

  /** 路由器 */
  static readonly ROUTER: IPresetTemplate = {
    id: 'router',
    name: $r('app.string.template_router'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.NETWORK,
    description: $r('app.string.template_desc_router'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('admin_address', '192.168.1.1', false, undefined, undefined, false, $r('app.string.template_field_admin_address')),
      field('ssid', '', false, undefined, undefined, false, $r('app.string.template_field_ssid')),
      protectedField('wifi_password', '', undefined, undefined, false, $r('app.string.template_field_wifi_password')),
      protectedField('admin_password', '', undefined, undefined, false, $r('app.string.template_field_admin_password'))
    ]
  };

  // ==================== 开发类 ====================

  /** SSH密钥 */
  static readonly SSH_KEY: IPresetTemplate = {
    id: 'ssh_key',
    name: $r('app.string.template_ssh_key'),
    iconId: Icons.UserKey,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_ssh_key'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('host', '', false, '', undefined, true, $r('app.string.template_field_host')),
      field('port', '22', false, undefined, undefined, false, $r('app.string.template_field_port')),
      protectedField('private_key', '', '', $r('app.string.template_placeholder_pem_key'), false, $r('app.string.template_field_private_key')),
      field('public_key', '', false, '可选，用于参考', $r('app.string.template_placeholder_public_key'), false, $r('app.string.template_field_public_key')),
      protectedField('key_passphrase', '', '如有', $r('app.string.template_placeholder_key_passphrase'), false, $r('app.string.template_field_key_passphrase'))
    ]
  };

  /** 数据库 */
  static readonly DATABASE: IPresetTemplate = {
    id: 'database',
    name: $r('app.string.template_database'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_database'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('db_type', 'MySQL', false, 'MySQL/PostgreSQL/Oracle/SQL Server/MongoDB等', $r('app.string.template_placeholder_db_type'), true, $r('app.string.template_field_db_type')),
      field('host', '', false, '', undefined, true, $r('app.string.template_field_host')),
      field('port', '3306', false, undefined, undefined, false, $r('app.string.template_field_port')),
      field('db_name', '', false, '', undefined, true, $r('app.string.template_field_db_name')),
      field('charset', 'utf8mb4', false, undefined, undefined, false, $r('app.string.template_field_charset')),
      field('connection_string', '', false, undefined, undefined, false, $r('app.string.template_field_connection_string'))
    ]
  };

  /** 服务器 */
  static readonly SERVER: IPresetTemplate = {
    id: 'server',
    name: $r('app.string.template_server'),
    iconId: Icons.NetworkServer,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_server'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('ip_address', '', false, '', undefined, true, $r('app.string.template_field_ip_address')),
      field('ssh_port', '22', false, undefined, undefined, false, $r('app.string.template_field_ssh_port')),
      field('os', '', false, 'CentOS/Ubuntu/Windows等', $r('app.string.template_placeholder_os'), false, $r('app.string.template_field_os')),
      field('provider', '', false, '阿里云/腾讯云/AWS等', $r('app.string.template_placeholder_provider'), false, $r('app.string.template_field_provider')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** API密钥 */
  static readonly API_KEY: IPresetTemplate = {
    id: 'api_key',
    name: $r('app.string.template_api_key'),
    iconId: Icons.Tool,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_api_key'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      field('api_key', '', false, '', undefined, true, $r('app.string.template_field_api_key')),
      protectedField('api_secret', '', undefined, undefined, false, $r('app.string.template_field_api_secret')),
      field('endpoint_url', '', false, undefined, undefined, false, $r('app.string.template_field_endpoint_url')),
      field('platform', '', false, undefined, undefined, false, $r('app.string.template_field_platform')),
      field('scope', '', false, undefined, undefined, false, $r('app.string.template_field_scope')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
    ]
  };

  /** 软件许可证 */
  static readonly SOFTWARE_LICENSE: IPresetTemplate = {
    id: 'software_license',
    name: $r('app.string.template_software_license'),
    iconId: Icons.CDRom,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_software_license'),
    standardFields: {
      notes: ''
    },
    customFields: [
      protectedField('license_key', '', undefined, undefined, true, $r('app.string.template_field_license_key')),
      field('software_name', '', false, '', undefined, true, $r('app.string.template_field_software_name')),
      field('purchase_email', '', false, undefined, undefined, false, $r('app.string.template_field_purchase_email')),
      field('purchase_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_purchase_date')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date')),
      field('license_type', '', false, '永久/订阅/教育版等', $r('app.string.template_placeholder_license_type'), false, $r('app.string.template_field_license_type')),
      field('device_count', '', false, undefined, undefined, false, $r('app.string.template_field_device_count'))
    ]
  };

  /** 电子签名 */
  static readonly DIGITAL_SIGNATURE: IPresetTemplate = {
    id: 'digital_signature',
    name: $r('app.string.template_digital_signature'),
    iconId: Icons.Certificate,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_digital_signature'),
    standardFields: {
      notes: ''
    },
    customFields: [
      field('certificate_name', '', false, undefined, undefined, false, $r('app.string.template_field_certificate_name')),
      protectedField('certificate_content', '', '', $r('app.string.template_placeholder_pem_format'), false, $r('app.string.template_field_certificate_content')),
      protectedField('private_key', '', undefined, undefined, false, $r('app.string.template_field_private_key')),
      protectedField('private_key_password', '', undefined, undefined, false, $r('app.string.template_field_private_key_password')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date')),
      field('issuer', '', false, undefined, undefined, false, $r('app.string.template_field_issuer'))
    ]
  };

  /** Git仓库 */
  static readonly GIT_REPOSITORY: IPresetTemplate = {
    id: 'git_repository',
    name: $r('app.string.template_git_repository'),
    iconId: Icons.Package,
    category: TemplateCategory.DEVELOPMENT,
    description: $r('app.string.template_desc_git_repository'),
    standardFields: {
      username: '',
      password: '',
      url: '',
      notes: ''
    },
    customFields: [
      protectedField('access_token', '', undefined, undefined, false, $r('app.string.template_field_access_token')),
      protectedField('ssh_private_key', '', undefined, undefined, false, $r('app.string.template_field_ssh_private_key')),
      field('git_platform', '', false, 'GitHub/GitLab/Gitee等', $r('app.string.template_placeholder_git_platform'), false, $r('app.string.template_field_git_platform')),
      field('default_branch', 'main', false, undefined, undefined, false, $r('app.string.template_field_default_branch'))
    ]
  };

  // ==================== 其他类 ====================

  /** 安全问题 */
  static readonly SECURITY_QUESTION: IPresetTemplate = {
    id: 'security_question',
    name: $r('app.string.template_security_question'),
    iconId: Icons.Warning,
    category: TemplateCategory.OTHER,
    description: $r('app.string.template_desc_security_question'),
    standardFields: {
      notes: ''
    },
    customFields: [
      field('question1', '', false, '', undefined, true, $r('app.string.template_field_question1')),
      protectedField('answer1', '', undefined, undefined, true, $r('app.string.template_field_answer1')),
      field('question2', '', false, undefined, undefined, false, $r('app.string.template_field_question2')),
      protectedField('answer2', '', undefined, undefined, false, $r('app.string.template_field_answer2')),
      field('question3', '', false, undefined, undefined, false, $r('app.string.template_field_question3')),
      protectedField('answer3', '', undefined, undefined, false, $r('app.string.template_field_answer3'))
    ]
  };

  /** 门禁卡 */
  static readonly ACCESS_CARD: IPresetTemplate = {
    id: 'access_card',
    name: $r('app.string.template_access_card'),
    iconId: Icons.LockOpen,
    category: TemplateCategory.OTHER,
    description: $r('app.string.template_desc_access_card'),
    standardFields: {
      notes: ''
    },
    customFields: [
      field('card_number', '', false, undefined, undefined, false, $r('app.string.template_field_card_number')),
      field('community_company', '', false, undefined, undefined, false, $r('app.string.template_field_community_company')),
      field('holder', '', false, undefined, undefined, false, $r('app.string.template_field_holder')),
      field('expiry_date', '', false, 'YYYY-MM-DD', $r('app.string.template_placeholder_date'), false, $r('app.string.template_field_expiry_date'))
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
