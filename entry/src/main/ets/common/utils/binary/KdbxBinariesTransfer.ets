import { KdbxBinaries, KdbxContext } from 'kdbxweb';
import { KdbxBaseTransfer } from './KdbxBaseTransfer';
import { KdbxBinaryStream } from './KdbxBinaryStream';

/**
 * 二进制文件的序列化工具类
 */
export class KdbxBinariesTransfer implements KdbxBaseTransfer<KdbxBinaries> {

    /**
     * 序列化对象
     * @param stream
     * @param obj
     */
    write(stream: KdbxBinaryStream, obj: KdbxBinaries): void {
    }

    /**
     * 反序列化对象
     * @param stream
     * @param ctx
     * @returns
     */
    read(stream: KdbxBinaryStream, ctx: KdbxContext): KdbxBinaries {
    }
}
