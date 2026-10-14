import { ByteUtils } from 'kdbxweb';
import { EncodingUtil, OtpDataFmt } from './EncodingUtil';
import { HmacOtp } from './HmacOtp';
import { OtpInfo } from './OtpInfo';
import { OtpUtil } from './OtpUtil';

/**
 * OTP 派生结果：secret（hex 交 Worker 构建 customKey）+ 计数器增量（解锁成功后写回辅助文件）
 */
export class OtpDerivedSecret {
  public secret: Uint8Array = new Uint8Array(0);
  public secretHex: string = '';
  /** v2 = OtpsRequired + 前瞻偏移 i；v1 = OtpsRequired */
  public counterDelta: number = 0;
}

/**
 * OtpKeyProv 编排服务（对齐 OathHotpKeyProv.cs / PasswordActivity OTP 流程）：
 * - OTP 码模式：辅助文件 OtpInfo（v1/v2 双格式）+ 用户连续输入的 OTP 码 → 派生 secret；
 * - 恢复模式：直接按编码格式（Hex/Base64/Base32/UTF-8/Dec）解析 secret；
 * - Counter 写回：解锁成功后由 UI 调 toXml 持久化（本层仅计算增量）。
 */
export class OtpKeyProvService {
  /** 辅助文件扩展名（对齐 OathHotpKeyProv.AuxFileExt） */
  public static readonly AUX_FILE_EXT: string = '.otp.xml';
  private static readonly OTP_TYPE = 'OATH HOTP / RFC 4226';
  private static readonly OTP_VERSION = '2.0';

  /**
   * 数据库文件名 → 同目录辅助文件名：<去扩展名数据库名>.otp.xml
   * （对齐 KP2A GetAuxFileIoc：GetFilenameWithoutPathAndExt + AuxFileExt）
   */
  public static buildAuxFileName(dbFileName: string): string {
    let name = dbFileName;
    const slash = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    const dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    return name + OtpKeyProvService.AUX_FILE_EXT;
  }

  /**
   * OTP 码模式派生 secret（对齐 OathHotpKeyProv.CreateOtpSecret / SetSecret）：
   * - v1（EncryptedSecret 非空）：KeyFromOtps + DecryptData（无 PlainTextHash 校验）；
   * - v2（EncryptedSecrets[]）：逐项 DecryptSecret，命中前瞻窗口第 i 项时 Counter += OtpsRequired + i。
   * @param otpInfo 辅助文件解析结果
   * @param otps 用户连续输入的 OtpsRequired 个 OTP 码
   */
  public static async deriveSecretFromOtps(otpInfo: OtpInfo, otps: string[]): Promise<OtpDerivedSecret> {
    if (otpInfo.encryptedSecret.length > 0) {
      // v1（< v2.0）
      const trfKey32 = ByteUtils.base64ToBytes(otpInfo.transformationKey);
      const key32 = await OtpUtil.keyFromOtps(otps, 0, otps.length, trfKey32, otpInfo.transformationRounds);
      const iv = ByteUtils.base64ToBytes(otpInfo.encryptionIV);
      const secret = OtpUtil.decryptData(otpInfo.encryptedSecret, key32, iv);
      if (!secret) {
        throw new Error('bad encrypted secret data');
      }
      return OtpKeyProvService.buildResult(secret, otpInfo.otpsRequired);
    }
    // v2（>= 2.0），支持前瞻窗口
    for (let i = 0; i < otpInfo.encryptedSecrets.length; i++) {
      const secret = await OtpUtil.decryptSecret(otpInfo.encryptedSecrets[i], otps, 0, otps.length);
      if (secret) {
        return OtpKeyProvService.buildResult(secret, otpInfo.otpsRequired + i);
      }
    }
    throw new Error('otp verification failed: PlainTextHash mismatch or wrong OTPs');
  }

  /**
   * 恢复模式：直接解析 secret 输入（对齐 EncodingUtil.ParseKey，非法输入抛错）
   */
  public static deriveSecretFromRecoveryInput(secretInput: string, fmt: OtpDataFmt): Uint8Array {
    const secret = EncodingUtil.parseKey(secretInput, fmt);
    if (!secret || secret.length === 0) {
      throw new Error('invalid recovery secret for format');
    }
    return secret;
  }

  /**
   * v2 辅助文件创建（对齐 OathHotpKeyProv.CreateAuxFile + OtpInfo.EncryptSecret）：
   * 按 Counter 起生成 OtpsRequired + LookAheadCount 个 HOTP 码，
   * 对每个前瞻偏移 i 加密 secret（EncryptedSecrets 长度 = 1 + LookAheadCount），并清空 v1 字段。
   */
  public static async encryptOtpInfoSecret(otpInfo: OtpInfo, secret: Uint8Array): Promise<void> {
    otpInfo.type = OtpKeyProvService.OTP_TYPE;
    otpInfo.version = OtpKeyProvService.OTP_VERSION;
    otpInfo.generator = 'KeePassHO';

    const otps: string[] = [];
    let counter = otpInfo.counter;
    const total = otpInfo.otpsRequired + otpInfo.lookAheadCount;
    for (let i = 0; i < total; i++) {
      otps.push(await HmacOtp.generate(secret, counter, otpInfo.otpLength, false, -1));
      counter++;
    }

    otpInfo.encryptedSecret = '';
    otpInfo.encryptionIV = '';
    otpInfo.transformationKey = '';
    otpInfo.transformationRounds = OtpInfo.DEFAULT_TRANSFORMATION_ROUNDS;
    otpInfo.encryptedSecrets = [];
    for (let i = 0; i <= otpInfo.lookAheadCount; i++) {
      otpInfo.encryptedSecrets.push(await OtpUtil.encryptSecret(secret, otps, i, otpInfo.otpsRequired));
    }
  }

  private static buildResult(secret: Uint8Array, counterDelta: number): OtpDerivedSecret {
    const result = new OtpDerivedSecret();
    result.secret = secret;
    result.secretHex = ByteUtils.bytesToHex(secret);
    result.counterDelta = counterDelta;
    return result;
  }
}
