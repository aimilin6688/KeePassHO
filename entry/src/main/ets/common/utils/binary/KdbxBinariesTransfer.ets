import { KdbxBinaries, KdbxContext, KdbxBinary, KdbxBinaryOrRef, KdbxBinaryRef, ProtectedValue, ByteUtils } from 'kdbxweb';
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
        const binaries = obj.getAll();
        stream.setUint32(binaries.length, true);
        
        for (const binary of binaries) {
            if (binary instanceof ProtectedValue) {
                // 处理ProtectedValue类型
                stream.setUint8(1); // 标记为ProtectedValue
                stream.writeBytes(binary.getBinary());
            } else if (binary instanceof ArrayBuffer) {
                // 处理普通ArrayBuffer
                stream.setUint8(0); // 标记为普通二进制
                stream.writeBytes(new Uint8Array(binary));
            } else if (binary && typeof binary === 'object' && binary.ref) {
                // 处理引用类型
                stream.setUint8(2); // 标记为引用
                stream.writeString((binary as KdbxBinaryRef).ref);
            }
        }
    }

    /**
     * 反序列化对象
     * @param stream
     * @param ctx
     * @returns
     */
    read(stream: KdbxBinaryStream, ctx: KdbxContext): KdbxBinaries {
        const count = stream.getUint32(true);
        const binaries = new KdbxBinaries();
        
        for (let i = 0; i < count; i++) {
            const type = stream.getUint8();
            let binary: KdbxBinary | Uint8Array;
            
            switch (type) {
                case 0: // 普通二进制
                    const bytes = stream.readBytes(stream.getUint32(true));
                    binary = ByteUtils.bufferToBytes(bytes);
                    break;
                case 1: // ProtectedValue
                    const protectedBytes = stream.readBytes(stream.getUint32(true));
                    binary = ProtectedValue.fromBinary(protectedBytes);
                    break;
                case 2: // 引用
                    const ref = stream.readString();
                    binary = ByteUtils.stringToBuffer(ref);
                    break;
                default:
                    throw new Error('Invalid binary type');
            }
            
            binaries.add(binary);
        }
        
        return binaries;
    }
}
