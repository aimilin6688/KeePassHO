/*
    @note           Disable typescript checking for this file since we are explicity trying to check for
                    invalid types. this became a requirement in typescript v5x

    @ref            'throws error for bad value type on set'
*/

// @ts-nocheck

import { describe, expect, it } from '@ohos/hypium';
import { BinaryStream, ByteUtils, Consts, Int64, VarDictionary } from '../../../../main/ets/index';
import { ValueType } from '../../../../main/ets/utils/var-dictionary';

describe('VarDictionary', () => {
    const data =
        '00010808000000426f6f6c5472756501000000010809000000426f6f6c46616c' +
        '73650100000000040600000055496e743332040000002a000000050600000055' +
        '496e74363408000000ccccddddeeeeffff0c05000000496e74333204000000d6' +
        'ffffff0d05000000496e74363408000000444433332222111118060000005374' +
        '72696e670b000000537472696e6756616c756542090000004279746541727261' +
        '7907000000000102030405ff00';

    it('reads and writes dictionary', 0,() => {
        const dataBytes = ByteUtils.hexToBytes(data);
        let stm = new BinaryStream(ByteUtils.arrayToBuffer(dataBytes));
        const dict = VarDictionary.read(stm);
        expect(dict).to.be.a(VarDictionary);
        expect(dict.length).assertEqual(8);
        expect(dict.get('BoolTrue')).assertEqual(true);
        expect(dict.get('BoolFalse')).assertEqual(false);
        expect(dict.get('UInt32')).assertEqual(42);
        expect((dict.get('UInt64') as Int64).hi).assertEqual(0xffffeeee);
        expect((dict.get('UInt64') as Int64).lo).assertEqual(0xddddcccc);
        expect(dict.get('Int32')).assertEqual(-42);
        expect((dict.get('Int64') as Int64).hi).assertEqual(0x11112222);
        expect((dict.get('Int64') as Int64).lo).assertEqual(0x33334444);
        expect(dict.get('String')).assertEqual('StringValue');
        expect(dict.keys()).to.eql([
            'BoolTrue',
            'BoolFalse',
            'UInt32',
            'UInt64',
            'Int32',
            'Int64',
            'String',
            'ByteArray'
        ]);
        expect(ByteUtils.bytesToHex(dict.get('ByteArray') as ArrayBuffer)).assertEqual('000102030405ff');

        stm = new BinaryStream();
        dict.write(stm);
        expect(ByteUtils.bytesToHex(stm.getWrittenBytes())).assertEqual(data);
    });

    it('writes dictionary', 0,() => {
        const dict = new VarDictionary();
        dict.set('BoolTrue', ValueType.Bool, true);
        dict.set('BoolFalse', ValueType.Bool, false);
        dict.set('UInt32', ValueType.UInt32, 42);
        dict.set('UInt64', ValueType.UInt64, new Int64(0xddddcccc, 0xffffeeee));
        dict.set('Int32', ValueType.Int32, -42);
        dict.set('Int64', ValueType.Int64, new Int64(0x33334444, 0x11112222));
        dict.set('String', ValueType.String, 'StringValue');
        dict.set('ByteArray', ValueType.Bytes, ByteUtils.hexToBytes('000102030405ff'));
        const stm = new BinaryStream();
        dict.write(stm);
        expect(ByteUtils.bytesToHex(stm.getWrittenBytes())).assertEqual(data);
    });

    it('returns undefined for not found value', 0,() => {
        const dict = new VarDictionary();
        expect(dict.length).assertEqual(0);
        expect(dict.get('val')).assertEqual(undefined);
    });

    it('removes item from dictionary', 0,() => {
        const dict = new VarDictionary();
        expect(dict.length).assertEqual(0);
        expect(dict.get('val')).assertEqual(undefined);
        dict.set('val', ValueType.Bool, true);
        expect(dict.length).assertEqual(1);
        expect(dict.get('val')).assertEqual(true);
        dict.remove('val');
        expect(dict.length).assertEqual(0);
        expect(dict.get('val')).assertEqual(undefined);
    });

    it('allows to add key twice', 0,() => {
        const dict = new VarDictionary();
        dict.set('UInt32', ValueType.UInt32, 42);
        expect(dict.length).assertEqual(1);
        dict.set('UInt32', ValueType.UInt32, 42);
        expect(dict.length).assertEqual(1);
    });

    it('throws error for empty version', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('0000')))
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidVersion);
        });
    });

    it('throws error for larger version', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('0002')))
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidVersion);
        });
    });

    it('throws error for bad value type', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('0001ff01000000dd10000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad value type');
        });
    });

    it('reads empty dictionary', 0,() => {
        const dict = VarDictionary.read(
            new BinaryStream(ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('000100')))
        );
        expect(dict.length).assertEqual(0);
    });

    it('throws error for bad key length', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('0001ff00000000dd10000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad key length');
        });
    });

    it('throws error for bad value length', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('0001ff01000000ddffffffff'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad value length');
        });
    });

    it('throws error for bad uint32 value', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('00010401000000dd0500000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad uint32');
        });
    });

    it('throws error for bad uint64 value', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('00010501000000dd0500000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad uint64');
        });
    });

    it('throws error for bad bool value', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('00010801000000dd0500000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad bool');
        });
    });

    it('throws error for bad int32 value', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('00010c01000000dd0500000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad int32');
        });
    });

    it('throws error for bad int64 value', 0,() => {
        expect(() => {
            VarDictionary.read(
                new BinaryStream(
                    ByteUtils.arrayToBuffer(ByteUtils.hexToBytes('00010d01000000dd0500000000'))
                )
            );
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
            expect(e.message).to.contain('bad int64');
        });
    });

    it('throws error for bad value type on write', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            dict.set('BoolTrue', ValueType.Bool, true);
            // @ets-ignore
            dict._items[0].type = 0xff;
            dict.write(new BinaryStream());
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.Unsupported);
        });
    });

    it('throws error for bad value type on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', 0xff, true);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad int32 on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Int32, 'str');
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.Int32, null);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad int64 on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.Int64, null);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Int64, 'str');
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Int64, 123);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.Int64, { hi: 1 });
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.Int64, { lo: 1 });
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad bool on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Bool, 'true');
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Bool, 1);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.Bool, null);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Bool, undefined);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad uint32 on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.UInt32, 'str');
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.UInt32, -1);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad uint64 on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.UInt64, null);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.UInt64, 'str');
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.UInt64, 123);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.UInt64, { hi: 1 });
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.UInt64, { lo: 1 });
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad string on set', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.String, null);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.String, 123);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });

    it('throws error for bad bytes', 0,() => {
        expect(() => {
            const dict = new VarDictionary();
            // @ets-ignore
            dict.set('val', ValueType.Bytes, null);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Bytes, 123);
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
        expect(() => {
            const dict = new VarDictionary();
            dict.set('val', ValueType.Bytes, '0000');
        }).to.throwException((e) => {
            expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
        });
    });
});
