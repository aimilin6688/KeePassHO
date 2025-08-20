import { KdbxContext } from "kdbxweb";
import { KdbxBinaryStream } from "./KdbxBinaryStream";


/**
 * 二进制文件的序列化工具类
 */
export interface KdbxBaseTransfer<T> {

  /**
   * 序列化对象
   * @param stream
   * @param obj
   */
  write(stream: KdbxBinaryStream, obj:T): void;

  /**
   * 反序列化对象
   * @param stream
   * @param ctx
   * @returns
   */
  read(stream: KdbxBinaryStream, ctx:KdbxContext): T;
}