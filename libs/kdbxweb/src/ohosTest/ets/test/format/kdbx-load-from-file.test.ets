import { describe, expect, it, beforeAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
import { TestResources } from '../test-support/test-resources';
import { fileIo as fs } from '@kit.CoreFileKit';

export default function KdbxLoadFromFileTest() {
    describe('KdbxLoadFromFile', () => {
        let testDir: string;

        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
            testDir = '/data/storage/el2/base/haps/entry/files/loadfromfile-test';
            try {
                if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(testDir, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
        });

        /**
         * loadFromFile 加载 demo.kdbx 与 Kdbx.load 结果一致（meta.name）
         */
        it('loadFromFile loads demo.kdbx matching Kdbx.load', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            // 写 demo.kdbx 到文件
            const dbPath = testDir + '/demo.kdbx';
            return writeFile(dbPath, TestResources.demoKdbx).then(() => {
                const t1Path = testDir + '/demo-t1.tmp';
                return kdbxweb.Kdbx.loadFromFile(dbPath, cred, { t1Path: t1Path }).then((dbFromFile) => {
                    return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((dbFromBuffer) => {
                        expect(dbFromFile.meta.name).assertEqual(dbFromBuffer.meta.name);
                        expect(dbFromFile.meta.name).assertEqual('demo');
                        // 清理
                        try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
                    });
                });
            });
        });

        /**
         * loadFromFile 条目数与 Kdbx.load 一致
         */
        it('loadFromFile entries match Kdbx.load', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            const dbPath = testDir + '/demo-entries.kdbx';
            return writeFile(dbPath, TestResources.demoKdbx).then(() => {
                const t1Path = testDir + '/demo-entries-t1.tmp';
                return kdbxweb.Kdbx.loadFromFile(dbPath, cred, { t1Path: t1Path }).then((dbFromFile) => {
                    return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((dbFromBuffer) => {
                        const fromFileEntries = collectEntryTitles(dbFromFile);
                        const fromBufferEntries = collectEntryTitles(dbFromBuffer);
                        expect(fromFileEntries.length).assertEqual(fromBufferEntries.length);
                        for (let i = 0; i < fromFileEntries.length; i++) {
                            expect(fromFileEntries[i]).assertEqual(fromBufferEntries[i]);
                        }
                        try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
                    });
                });
            });
        });

        /**
         * loadFromFile 错误密码抛出 InvalidKey
         */
        it('loadFromFile with wrong password throws InvalidKey', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('wrong-password'),
                TestResources.demoKey
            );
            const dbPath = testDir + '/demo-wrong.kdbx';
            return writeFile(dbPath, TestResources.demoKdbx).then(() => {
                const t1Path = testDir + '/demo-wrong-t1.tmp';
                return kdbxweb.Kdbx.loadFromFile(dbPath, cred, { t1Path: t1Path })
                    .then(() => {
                        throw new Error('should have thrown');
                    })
                    .catch((e: Error) => {
                        try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
                        expect(e instanceof kdbxweb.KdbxError).assertTrue();
                        expect((e as kdbxweb.KdbxError).code)
                            .assertEqual(kdbxweb.Consts.ErrorCodes.InvalidKey);
                    });
            });
        });

        /**
         * loadFromFile + maxDecompressedBytes 守卫触发 DecompressedTooLarge
         */
        it('loadFromFile respects maxDecompressedBytes limit', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            const dbPath = testDir + '/demo-limit.kdbx';
            return writeFile(dbPath, TestResources.demoKdbx).then(() => {
                const t1Path = testDir + '/demo-limit-t1.tmp';
                // 设极小上限（1 字节），必然超限
                return kdbxweb.Kdbx.loadFromFile(dbPath, cred,
                    { t1Path: t1Path, maxDecompressedBytes: 1 })
                    .then(() => {
                        throw new Error('should have thrown DecompressedTooLarge');
                    })
                    .catch((e: Error) => {
                        try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
                        expect(e instanceof kdbxweb.KdbxError).assertTrue();
                        expect((e as kdbxweb.KdbxError).code)
                            .assertEqual(kdbxweb.Consts.ErrorCodes.DecompressedTooLarge);
                    });
            });
        });

        /**
         * loadFromFile 缺少 t1Path 抛 InvalidArg
         */
        it('loadFromFile without t1Path throws InvalidArg', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.loadFromFile(testDir + '/demo.kdbx', cred, {})
                .then(() => {
                    throw new Error('should have thrown');
                })
                .catch((e: Error) => {
                    expect(e instanceof kdbxweb.KdbxError).assertTrue();
                    expect((e as kdbxweb.KdbxError).code)
                        .assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                });
        });
    });
}

function writeFile(path: string, data: ArrayBuffer): Promise<void> {
    return fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).then((file) => {
        return fs.write(file.fd, data).then(() => {
            return fs.fsync(file.fd).then(() => {
                return fs.close(file.fd);
            });
        });
    });
}

function appendGroupEntryTitles(group: kdbxweb.KdbxGroup, titles: string[]): void {
    for (let i = 0; i < group.entries.length; i++) {
        const title = group.entries[i].fields.get('Title');
        if (typeof title === 'string') {
            titles.push(title);
        }
    }
    for (let i = 0; i < group.groups.length; i++) {
        appendGroupEntryTitles(group.groups[i], titles);
    }
}

function collectEntryTitles(db: kdbxweb.Kdbx): string[] {
    const titles: string[] = [];
    appendGroupEntryTitles(db.getDefaultGroup(), titles);
    return titles;
}
