import { ByteUtils } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocationInfo } from '../beans/LocationParam';
import { KdbxFileManager } from '../kdbx/KdbxFileManager';
import { OtpInfo } from './OtpInfo';
import { OtpKeyProvService } from './OtpKeyProvService';

const DOMAIN = 0x0000;
const TAG = 'OtpAuxFileService';

/**
 * OTP 辅助文件（<数据库名>.otp.xml）读写服务：
 * - 定位：与数据库同目录同名 + OtpKeyProv 扩展名（对齐 KP2A GetAuxFileIoc）；
 * - 读取解析：经 IFileStorage 抽象（本地/远端统一）；
 * - 解锁成功后写回：Counter 前进 → 以新 Counter 重新加密 secret → 序列化持久化
 *   （对齐 KP2A SaveOtpAuxFileAndLoadDb + OathHotpKeyProv.CreateAuxFile；
 *   写回失败仅告警不阻断，远端存储可能只读）。
 */
export class OtpAuxFileService {
  /**
   * 数据库完整路径 → 同目录辅助文件完整路径
   * @param dbFilePath 数据库文件完整路径
   */
  public static buildAuxFilePath(dbFilePath: string): string {
    const slash = Math.max(dbFilePath.lastIndexOf('/'), dbFilePath.lastIndexOf('\\'));
    const dir = slash >= 0 ? dbFilePath.substring(0, slash + 1) : '';
    return dir + OtpKeyProvService.buildAuxFileName(dbFilePath);
  }

  /**
   * 读取并解析辅助文件
   * @param auxLocation 辅助文件位置（同目录自动推导或用户手动选择）
   * @returns Promise<OtpInfo> 解析结果
   * @throws 文件不存在/不可读/XML 损坏时抛错，由调用方决定引导（手动选择等）
   */
  public static async loadOtpInfo(auxLocation: LocationInfo): Promise<OtpInfo> {
    const manager = KdbxFileManager.of(auxLocation);
    const fileContent = await manager.read(auxLocation.filePath);
    return OtpInfo.fromXml(ByteUtils.bytesToString(new Uint8Array(fileContent.content)));
  }

  /**
   * 解锁成功后写回辅助文件（对齐 KP2A SaveOtpAuxFileAndLoadDb / OathHotpKeyProv.CreateAuxFile）：
   * Counter += counterDelta → 以新 Counter 重新加密 secret（v1 文件同时升级为 v2 格式）→ 序列化写入。
   * @param otpInfo 本次解锁使用的辅助文件解析结果
   * @param secret 本次派生的 OTP secret
   * @param counterDelta 计数器增量（OtpsRequired + 前瞻偏移 i）
   * @param auxLocation 辅助文件位置
   * @throws 写入失败抛错，由调用方决定告警（不阻断解锁流程）
   */
  public static async saveAfterUnlock(otpInfo: OtpInfo, secret: Uint8Array, counterDelta: number,
    auxLocation: LocationInfo): Promise<void> {
    otpInfo.counter += counterDelta;
    hilog.info(DOMAIN, TAG, 'advance otp counter: +%{public}d -> %{public}d', counterDelta, otpInfo.counter);
    await OtpKeyProvService.encryptOtpInfoSecret(otpInfo, secret);
    await OtpAuxFileService.writeOtpInfo(otpInfo, auxLocation);
  }

  /**
   * 序列化并写入辅助文件
   */
  public static async writeOtpInfo(otpInfo: OtpInfo, auxLocation: LocationInfo): Promise<void> {
    const manager = KdbxFileManager.of(auxLocation);
    await manager.write(auxLocation.filePath, ByteUtils.stringToBuffer(otpInfo.toXml()));
  }
}
