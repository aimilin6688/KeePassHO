import { describe, expect, it } from '@ohos/hypium';
import {
    ByteUtils,
    Consts,
    KdbxError,
    KdbxUuid,
    ProtectedValue,
    ProtectSaltGenerator,
    Salsa20,
    XmlUtils
} from '../../../../main/ets/index';

describe('XmlUtils', () => {
    function removeSpaces(str: string) {
        return str.replace(/\s/g, '');
    }

    const isNode = !!global.process?.versions?.node;

    describe('parse', () => {
        it('parses XML document', 0,() => {
            const xml = XmlUtils.parse('<root><item><cd>&lt;&gt;</cd></item></root>');
            expect(xml.documentElement.nodeName).assertEqual('root');
            expect(xml.documentElement.firstChild!.nodeName).assertEqual('item');
            expect(xml.documentElement.firstChild!.firstChild!.nodeName).assertEqual('cd');
            expect(xml.documentElement.firstChild!.firstChild!.textContent).assertEqual('<>');
        });

        if (isNode) {
            it('uses the global DOMParser if possible', 0,() => {
                const doc = {
                    documentElement: 'hello',
                    getElementsByTagName: () => []
                };
                try {
                    // @ets-ignore
                    global.DOMParser = class {
                        parseFromString() {
                            return doc;
                        }
                    };
                    const xml = XmlUtils.parse('<root><item><cd>&lt;&gt;</cd></item></root>');
                    expect(xml).assertEqual(doc);
                } finally {
                    // @ets-ignore
                    delete global.DOMParser;
                }
            });
        }

        it('throws error for non-xml document', 0,() => {
            expect(() => {
                XmlUtils.parse('err');
            }).to.throwException((e) => {
                expect(e).to.be.a(KdbxError);
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).to.contain('bad xml');
            });
        });

        it('throws error for malformed xml document', 0,() => {
            expect(() => {
                XmlUtils.parse('<root><item><cd>&lt;&gt;</cd></item></bad>');
            }).to.throwException((e) => {
                expect(e).to.be.a(KdbxError);
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).to.contain('bad xml');
            });
        });

        it('throws error for generated parseerror element', 0,() => {
            expect(() => {
                XmlUtils.parse('<root><parsererror/></root>');
            }).to.throwException((e) => {
                expect(e).to.be.a(KdbxError);
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).to.contain('bad xml');
            });
        });

        it('parses bad characters', 0,() => {
            let chars = '';
            for (let i = 0; i <= 0x20; i++) {
                chars += String.fromCharCode(i);
            }
            for (let j = 0x80; j <= 0xff; j++) {
                chars += String.fromCharCode(j);
            }
            const xml = XmlUtils.parse('<root><item><cd>' + chars + '</cd></item></root>');
            expect(xml.documentElement.nodeName).assertEqual('root');
            expect(xml.documentElement.firstChild!.nodeName).assertEqual('item');
        });
    });

    describe('serialize', () => {
        it('serializes XML document', 0,() => {
            const doc = XmlUtils.parse('<root><item><cd>123</cd><e></e></item></root>');
            const xml = XmlUtils.serialize(doc);
            expect(xml).assertEqual('<root><item><cd>123</cd><e/></item></root>');
        });

        it('pretty prints XML document', 0,() => {
            const doc = XmlUtils.parse('<root><item><cd>123</cd><e></e></item></root>');
            const xml = XmlUtils.serialize(doc, true);
            expect(xml).assertEqual(
                '<root>\n    <item>\n        <cd>123</cd>\n        <e/>\n    </item>\n</root>'
            );
        });

        if (isNode) {
            it('uses the global XMLSerializer if possible', 0,() => {
                try {
                    // @ets-ignore
                    global.XMLSerializer = class {
                        serializeToString() {
                            return 'xml';
                        }
                    };
                    const doc = XmlUtils.parse('<root><item><cd>123</cd><e></e></item></root>');
                    const xml = XmlUtils.serialize(doc, true);
                    expect(xml).assertEqual('xml');
                } finally {
                    // @ets-ignore
                    delete global.XMLSerializer;
                }
            });
        }

        it('pretty prints processing instructions', 0,() => {
            const doc = XmlUtils.parse(
                '<?xml version="1.0" encoding="UTF-8"?><root><item><cd>123</cd><e></e></item></root>'
            );
            const xml = XmlUtils.serialize(doc, true);
            expect(xml).assertEqual(
                '<?xml version="1.0" encoding="UTF-8"?>\n<root>\n    <item>\n        <cd>123</cd>\n        <e/>\n    </item>\n</root>'
            );
        });
    });

    describe('create', () => {
        it('creates XML document', 0,() => {
            const doc = XmlUtils.create('root');
            expect(doc.documentElement.nodeName).assertEqual('root');
        });
    });

    describe('getChildNode', () => {
        it('gets first child node', 0,() => {
            const xml = XmlUtils.parse('<root><item>1</item><item>2</item></root>');
            const childNode = XmlUtils.getChildNode(xml.documentElement, 'item');
            expect(childNode).to.be.ok();
            expect(childNode!.textContent).assertEqual('1');
        });

        it("gets null if there's no matching child node", () => {
            const xml = XmlUtils.parse('<root><item>1</item><item>2</item></root>');
            const childNode = XmlUtils.getChildNode(xml.documentElement, 'notexisting');
            expect(childNode).assertEqual(null);
        });

        it('gets null for null', 0,() => {
            const childNode = XmlUtils.getChildNode(null, 'notexisting');
            expect(childNode).assertEqual(null);
        });

        it("gets null if there's no child nodes at all", () => {
            const xml = XmlUtils.parse('<root><item/></root>');
            let childNode = XmlUtils.getChildNode(xml.documentElement, 'item');
            expect(childNode).to.be.ok();
            childNode = XmlUtils.getChildNode(childNode, 'notexisting');
            expect(childNode).assertEqual(null);
        });

        it("throws error if there's no matching node", () => {
            const xml = XmlUtils.parse('<root><item/></root>');
            expect(() => {
                XmlUtils.getChildNode(xml.documentElement, 'notexisting', 'not found');
            }).to.throwException((e) => {
                expect(e).to.be.a(KdbxError);
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).to.contain('not found');
            });
        });
    });

    describe('addChildNode', () => {
        it('adds child node and returns it', 0,() => {
            const xml = XmlUtils.parse('<root><old/></root>');
            const childNode = XmlUtils.addChildNode(xml.documentElement, 'item');
            XmlUtils.addChildNode(childNode, 'inner');
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual(
                '<root><old/><item><inner/></item></root>'
            );
        });
    });

    describe('getText', () => {
        it('returns node text', 0,() => {
            const xml = XmlUtils.parse('<item> some text </item>');
            const text = XmlUtils.getText(xml.documentElement);
            expect(text).assertEqual(' some text ');
        });

        it('returns empty string for existing node without content', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const text = XmlUtils.getText(xml.documentElement);
            expect(text).assertEqual('');
        });

        it('returns empty string for empty node', 0,() => {
            const xml = XmlUtils.parse('<item/>');
            const text = XmlUtils.getText(xml.documentElement);
            expect(text).assertEqual('');
        });

        it('returns undefined for not existing node node', 0,() => {
            const text = XmlUtils.getText(null);
            expect(text).assertEqual(undefined);
        });

        it('returns node protected value if any', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            xml.documentElement.protectedValue = ProtectedValue.fromString('pr');
            const text = XmlUtils.getText(xml.documentElement);
            expect(text).assertEqual('pr');
        });
    });

    describe('setText', () => {
        it('sets node text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setText(xml.documentElement, 'new');
            expect(XmlUtils.serialize(xml)).assertEqual('<item>new</item>');
        });

        it('sets node empty text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setText(xml.documentElement, undefined);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });

        it('escapes special characters', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setText(xml.documentElement, ']]>');
            expect(XmlUtils.serialize(xml)).assertEqual('<item>]]&gt;</item>');
        });
    });

    describe('getTags', () => {
        it('returns node tags', 0,() => {
            const xml = XmlUtils.parse('<item>Tag1 ; Tag2, Another tag  , more tags </item>');
            const tags = XmlUtils.getTags(xml.documentElement);
            expect(tags).to.eql(['Tag1', 'Tag2', 'Another tag', 'more tags']);
        });

        it('returns empty tags for an empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const tags = XmlUtils.getTags(xml.documentElement);
            expect(tags).to.eql([]);
        });

        it('returns empty tags for a closed node', 0,() => {
            const xml = XmlUtils.parse('<item />');
            const tags = XmlUtils.getTags(xml.documentElement);
            expect(tags).to.eql([]);
        });

        it('returns empty tags for a node with blank text', 0,() => {
            const xml = XmlUtils.parse('<item>   </item>');
            const tags = XmlUtils.getTags(xml.documentElement);
            expect(tags).to.eql([]);
        });
    });

    describe('setTags', () => {
        it('sets node tags', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setTags(xml.documentElement, ['Tag1', 'Tag2', 'Another tag', 'more tags']);
            expect(XmlUtils.serialize(xml)).assertEqual(
                '<item>Tag1, Tag2, Another tag, more tags</item>'
            );
        });

        it('sets node empty tags', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setTags(xml.documentElement, []);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });
    });

    describe('getBytes', () => {
        it('returns node bytes', 0,() => {
            const xml = XmlUtils.parse('<item>YWJj</item>');
            const bytes = new Uint8Array(XmlUtils.getBytes(xml.documentElement)!);
            expect(bytes).assertDeepEquals(
                new Uint8Array(['a'.charCodeAt(0), 'b'.charCodeAt(0), 'c'.charCodeAt(0)])
            );
        });

        it('returns undefined for empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const bytes = XmlUtils.getBytes(xml.documentElement);
            expect(bytes).assertEqual(undefined);
        });
    });

    describe('setBytes', () => {
        it('sets node bytes from array', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBytes(xml.documentElement, new Uint8Array([1, 2, 3]));
            expect(XmlUtils.serialize(xml)).assertEqual('<item>AQID</item>');
        });

        it('sets node bytes from base64 string', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBytes(xml.documentElement, 'AQID');
            expect(XmlUtils.serialize(xml)).assertEqual('<item>AQID</item>');
        });

        it('sets node empty bytes', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBytes(xml.documentElement, undefined);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
            XmlUtils.setBytes(xml.documentElement, '');
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
            XmlUtils.setBytes(xml.documentElement, new Uint8Array(0));
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });
    });

    describe('setDate', () => {
        it('sets node date in ISO format', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setDate(xml.documentElement, new Date('2015-08-17T21:20Z'));
            expect(XmlUtils.serialize(xml)).assertEqual('<item>2015-08-17T21:20:00Z</item>');
        });

        it('sets node date in binary format', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setDate(xml.documentElement, new Date('2015-08-16T14:45:23.000Z'), true);
            expect(XmlUtils.serialize(xml)).assertEqual('<item>A5lizQ4AAAA=</item>');
        });

        it('sets node empty date', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setDate(xml.documentElement, undefined);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });
    });

    describe('getDate', () => {
        it('returns node date', 0,() => {
            const xml = XmlUtils.parse('<item>2015-01-02T03:04:05Z</item>');
            const dt = XmlUtils.getDate(xml.documentElement);
            expect(dt!.getUTCFullYear()).assertEqual(2015);
            expect(dt!.getUTCMonth()).assertEqual(0);
            expect(dt!.getUTCDate()).assertEqual(2);
            expect(dt!.getUTCHours()).assertEqual(3);
            expect(dt!.getUTCMinutes()).assertEqual(4);
            expect(dt!.getUTCSeconds()).assertEqual(5);
        });

        it('returns node date from base64', 0,() => {
            const xml = XmlUtils.parse('<item>A5lizQ4AAAA=</item>');
            const dt = XmlUtils.getDate(xml.documentElement);
            expect(dt!.toISOString()).assertEqual('2015-08-16T14:45:23.000Z');
        });

        it('returns undefined for empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const dt = XmlUtils.getDate(xml.documentElement);
            expect(dt).assertEqual(undefined);
        });
    });

    describe('getNumber', () => {
        it('returns node number', 0,() => {
            const xml = XmlUtils.parse('<item>123</item>');
            const num = XmlUtils.getNumber(xml.documentElement);
            expect(num).assertEqual(123);
        });

        it('returns undefined for empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const num = XmlUtils.getNumber(xml.documentElement);
            expect(num).assertEqual(undefined);
        });
    });

    describe('setNumber', () => {
        it('sets node number', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setNumber(xml.documentElement, 1);
            expect(XmlUtils.serialize(xml)).assertEqual('<item>1</item>');
        });

        it('sets zero as node number', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setNumber(xml.documentElement, 0);
            expect(XmlUtils.serialize(xml)).assertEqual('<item>0</item>');
        });

        it('sets node empty number', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setNumber(xml.documentElement, undefined);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
            XmlUtils.setNumber(xml.documentElement, NaN);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });
    });

    describe('getBoolean', () => {
        it('returns node true', 0,() => {
            let xml = XmlUtils.parse('<item>True</item>');
            let bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(true);
            xml = XmlUtils.parse('<item>true</item>');
            bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(true);
        });

        it('returns node false', 0,() => {
            let xml = XmlUtils.parse('<item>False</item>');
            let bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(false);
            xml = XmlUtils.parse('<item>false</item>');
            bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(false);
        });

        it('returns undefined for unknown text', 0,() => {
            const xml = XmlUtils.parse('<item>blablabla</item>');
            const bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(undefined);
        });

        it('returns null for null', 0,() => {
            const xml = XmlUtils.parse('<item>null</item>');
            const bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(null);
        });

        it('returns undefined for empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(undefined);
        });

        it('returns undefined for closed node', 0,() => {
            const xml = XmlUtils.parse('<item />');
            const bool = XmlUtils.getBoolean(xml.documentElement);
            expect(bool).assertEqual(undefined);
        });
    });

    describe('strToBoolean', () => {
        it('converts "true" to boolean', 0,() => {
            expect(XmlUtils.strToBoolean('true')).assertEqual(true);
        });

        it('converts "false" to boolean', 0,() => {
            expect(XmlUtils.strToBoolean('false')).assertEqual(false);
        });

        it('converts "null" to boolean', 0,() => {
            expect(XmlUtils.strToBoolean('null')).assertEqual(null);
        });

        it('converts a bad string to null', 0,() => {
            expect(XmlUtils.strToBoolean('bad')).assertEqual(undefined);
        });

        it('converts an empty string to undefined', 0,() => {
            expect(XmlUtils.strToBoolean('')).assertEqual(undefined);
        });

        it('converts null to undefined', 0,() => {
            expect(XmlUtils.strToBoolean(null)).assertEqual(undefined);
        });

        it('converts undefined to undefined', 0,() => {
            expect(XmlUtils.strToBoolean(undefined)).assertEqual(undefined);
        });
    });

    describe('setBoolean', () => {
        it('sets node false', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBoolean(xml.documentElement, false);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item>False</item>');
        });

        it('sets node true', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBoolean(xml.documentElement, true);
            expect(XmlUtils.serialize(xml)).assertEqual('<item>True</item>');
        });

        it('sets node null', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBoolean(xml.documentElement, null);
            expect(XmlUtils.serialize(xml)).assertEqual('<item>null</item>');
        });

        it('sets node empty boolean', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setBoolean(xml.documentElement, undefined);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });
    });

    describe('getUuid', () => {
        it('returns node uuid', 0,() => {
            const xml = XmlUtils.parse('<item>hADuI/JGbkmnRZxNNIZDew==</item>');
            const uuid = XmlUtils.getUuid(xml.documentElement);
            expect(uuid).to.be.ok();
            expect(uuid?.id).assertEqual('hADuI/JGbkmnRZxNNIZDew==');
        });

        it('returns undefined for empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const uuid = XmlUtils.getUuid(xml.documentElement);
            expect(uuid).assertEqual(undefined);
        });
    });

    describe('setUuid', () => {
        it('sets node uuid', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setUuid(xml.documentElement, new KdbxUuid(new ArrayBuffer(16)));
            expect(XmlUtils.serialize(xml)).assertEqual('<item>AAAAAAAAAAAAAAAAAAAAAA==</item>');
        });

        it('sets node empty uuid', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setUuid(xml.documentElement, undefined);
            expect(removeSpaces(XmlUtils.serialize(xml))).assertEqual('<item/>');
        });
    });

    describe('getProtectedText', () => {
        it('returns node protected text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            const pv = ProtectedValue.fromString('pv');
            xml.documentElement.protectedValue = pv;
            const res = XmlUtils.getProtectedText(xml.documentElement);
            expect(res).assertEqual(pv);
        });

        it('returns node text as protected text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            const res = XmlUtils.getProtectedText(xml.documentElement);
            expect(res).assertEqual('text');
        });

        it('returns empty string as protected text for node without text', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const res = XmlUtils.getProtectedText(xml.documentElement);
            expect(res).assertEqual('');
        });

        it('returns empty string as protected text for empty node', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const res = XmlUtils.getProtectedText(xml.documentElement);
            expect(res).assertEqual('');
        });
    });

    describe('setProtectedText', () => {
        it('sets node protected text as protected value', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            const pv = ProtectedValue.fromString('str');
            XmlUtils.setProtectedText(xml.documentElement, pv);
            expect(XmlUtils.serialize(xml)).assertEqual('<item Protected="True">text</item>');
            expect(xml.documentElement.protectedValue).assertEqual(pv);
        });

        it('sets node protected text as text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setProtectedText(xml.documentElement, 'str');
            expect(XmlUtils.serialize(xml)).assertEqual('<item>str</item>');
            expect(xml.documentElement.protectedValue).assertEqual(undefined);
        });
    });

    describe('getProtectedBinary', () => {
        it('returns node protected binary', 0,() => {
            const xml = XmlUtils.parse('<item>YWJj</item>');
            const pv = ProtectedValue.fromString('pv');
            xml.documentElement.protectedValue = pv;
            const res = XmlUtils.getProtectedBinary(xml.documentElement);
            expect(res).assertEqual(pv);
        });

        it('returns node ref as protected binary', 0,() => {
            const xml = XmlUtils.parse('<item Ref="MyRef">YWJj</item>');
            const res = XmlUtils.getProtectedBinary(xml.documentElement);
            expect(res).assertDeepEquals({ ref: 'MyRef' });
        });

        it('returns undefined as protected binary', 0,() => {
            const xml = XmlUtils.parse('<item></item>');
            const res = XmlUtils.getProtectedBinary(xml.documentElement);
            expect(res).assertEqual(undefined);
        });

        it('returns node text as protected binary', 0,() => {
            const xml = XmlUtils.parse('<item>YWJj</item>');
            const res = XmlUtils.getProtectedBinary(xml.documentElement);
            expect(ByteUtils.bytesToString(res as ArrayBuffer)).assertEqual('abc');
        });

        it('decompresses node text as protected binary', 0,() => {
            const xml = XmlUtils.parse(
                '<item Compressed="True">H4sIAAAAAAAAA0tMSgYAwkEkNQMAAAA=</item>'
            );
            const res = XmlUtils.getProtectedBinary(xml.documentElement);
            expect(ByteUtils.bytesToString(res as ArrayBuffer)).assertEqual('abc');
        });
    });

    describe('setProtectedBinary', () => {
        it('sets node protected binary as protected value', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            const pv = ProtectedValue.fromString('str');
            XmlUtils.setProtectedBinary(xml.documentElement, pv);
            expect(XmlUtils.serialize(xml)).assertEqual('<item Protected="True">text</item>');
            expect(xml.documentElement.protectedValue).assertEqual(pv);
        });

        it('sets node protected binary as ref', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setProtectedBinary(xml.documentElement, { ref: '123' });
            expect(XmlUtils.serialize(xml)).assertEqual('<item Ref="123">text</item>');
            expect(xml.documentElement.protectedValue).assertEqual(undefined);
        });

        it('sets node protected binary as text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setProtectedBinary(xml.documentElement, ByteUtils.base64ToBytes('YWJj'));
            expect(XmlUtils.serialize(xml)).assertEqual('<item>YWJj</item>');
            expect(xml.documentElement.protectedValue).assertEqual(undefined);
        });

        it('sets node protected binary as encoded text', 0,() => {
            const xml = XmlUtils.parse('<item>text</item>');
            XmlUtils.setProtectedBinary(xml.documentElement, new TextEncoder().encode('abc'));
            expect(XmlUtils.serialize(xml)).assertEqual('<item>YWJj</item>');
            expect(xml.documentElement.protectedValue).assertEqual(undefined);
        });
    });

    describe('setProtectedValues', () => {
        it('sets protected values', 0,() => {
            const xml = XmlUtils.parse(
                '<root><item1><inner Protected="True">MTIz</inner><i2 Protected="True"></i2></item1>' +
                    '<item2 Protected="True">NDU2</item2></root>'
            );
            let count = 0;

            class TestPSG extends ProtectSaltGenerator {
                constructor() {
                    super(new Salsa20(new Uint8Array(32), new Uint8Array(32)));
                }

                getSalt(): ArrayBuffer {
                    count++;
                    return new Uint8Array([count, count, count]);
                }
            }

            XmlUtils.setProtectedValues(xml.documentElement, new TestPSG());
            const item1 = XmlUtils.getChildNode(xml.documentElement, 'item1');
            const item2 = XmlUtils.getChildNode(xml.documentElement, 'item2');
            const inner = XmlUtils.getChildNode(item1, 'inner');
            expect(item1!.protectedValue).assertEqual(undefined);
            expect(item2!.protectedValue).to.be.ok();
            expect(inner!.protectedValue).to.be.ok();
            expect(inner!.protectedValue!.getText()).assertEqual('032');
            expect(item2!.protectedValue!.getText()).assertEqual('674');
        });

        it('generates error for bad protected values', 0,() => {
            const xml = XmlUtils.parse('<root><inner Protected="True">MTIz</inner></root>');

            class TestPSGThrows extends ProtectSaltGenerator {
                constructor() {
                    super(new Salsa20(new Uint8Array(32), new Uint8Array(32)));
                }

                getSalt(): ArrayBuffer {
                    throw new Error('boom');
                }
            }

            expect(() => {
                XmlUtils.setProtectedValues(xml.documentElement, new TestPSGThrows());
            }).to.throwException((e) => {
                expect(e).to.be.a(KdbxError);
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).to.contain('Error FileCorrupt: bad protected value at line');
            });
        });
    });

    describe('updateProtectedValuesSalt', () => {
        it('sets protected values', 0,() => {
            const xml = XmlUtils.parse(
                '<root><item1><inner Protected="True">MTIz</inner><i2 Protected="True"></i2></item1>' +
                    '<item2 Protected="True">NDU2</item2></root>'
            );
            const item1 = XmlUtils.getChildNode(xml.documentElement, 'item1');
            const item2 = XmlUtils.getChildNode(xml.documentElement, 'item2');
            const inner = XmlUtils.getChildNode(item1, 'inner');
            inner!.protectedValue = ProtectedValue.fromString('123');
            item2!.protectedValue = ProtectedValue.fromString('456');
            let count = 0;

            class TestPSG extends ProtectSaltGenerator {
                constructor() {
                    super(new Salsa20(new Uint8Array(32), new Uint8Array(32)));
                }

                getSalt(): ArrayBuffer {
                    count++;
                    return new Uint8Array([count, count, count]);
                }
            }

            XmlUtils.updateProtectedValuesSalt(xml.documentElement, new TestPSG());
            expect(new Uint8Array(inner!.protectedValue.salt)).assertDeepEquals([1, 1, 1]);
            expect(new Uint8Array(item2!.protectedValue.salt)).assertDeepEquals([2, 2, 2]);
        });
    });

    describe('unprotectValues', () => {
        it('unprotects protected values', 0,() => {
            const xml = XmlUtils.parse(
                '<root><item1><inner Protected="True">MTIz</inner><i2 Protected="True"></i2></item1>' +
                    '<item2 Protected="True">NDU2</item2></root>'
            );
            const item1 = XmlUtils.getChildNode(xml.documentElement, 'item1');
            const item2 = XmlUtils.getChildNode(xml.documentElement, 'item2');
            const inner = XmlUtils.getChildNode(item1, 'inner');
            inner!.protectedValue = ProtectedValue.fromString('123');
            item2!.protectedValue = ProtectedValue.fromString('456');
            XmlUtils.unprotectValues(xml.documentElement);
            expect(XmlUtils.serialize(inner as Document)).assertEqual(
                '<inner ProtectInMemory="True">123</inner>'
            );
            expect(XmlUtils.serialize(item2 as Document)).assertEqual(
                '<item2 ProtectInMemory="True">456</item2>'
            );
        });
    });

    describe('protectUnprotectedValues', () => {
        it('protects unprotected values', 0,() => {
            const xml = XmlUtils.parse(
                '<root><item1><inner ProtectInMemory="True">123</inner><i2 ProtectInMemory="True"></i2></item1>' +
                    '<item2 ProtectInMemory="True">NDU2</item2></root>'
            );
            const item1 = XmlUtils.getChildNode(xml.documentElement, 'item1');
            const item2 = XmlUtils.getChildNode(xml.documentElement, 'item2');
            const inner = XmlUtils.getChildNode(item1, 'inner');
            const salt = new ArrayBuffer(16);
            inner!.protectedValue = ProtectedValue.fromString('123');
            item2!.protectedValue = ProtectedValue.fromString('456');
            inner!.protectedValue.setSalt(salt);
            item2!.protectedValue.setSalt(salt);
            XmlUtils.protectUnprotectedValues(xml.documentElement);
            expect(XmlUtils.serialize(inner as Document)).assertEqual(
                '<inner Protected="True">MTIz</inner>'
            );
            expect(XmlUtils.serialize(item2 as Document)).assertEqual(
                '<item2 Protected="True">NDU2</item2>'
            );
        });
    });

    describe('protectPlainValues', () => {
        it('protects plain values', 0,() => {
            const xml = XmlUtils.parse(
                '<root><item1><inner ProtectInMemory="True">123</inner><i2 ProtectInMemory="True"></i2></item1>' +
                    '<item2 ProtectInMemory="True">456</item2></root>'
            );
            XmlUtils.protectPlainValues(xml.documentElement);
            const item1 = XmlUtils.getChildNode(xml.documentElement, 'item1');
            const item2 = XmlUtils.getChildNode(xml.documentElement, 'item2');
            const inner = XmlUtils.getChildNode(item1, 'inner');

            expect(item1!.protectedValue).assertEqual(undefined);
            expect(item2!.protectedValue).to.be.ok();
            expect(inner!.protectedValue).to.be.ok();
            expect(inner!.protectedValue!.getText()).assertEqual('123');
            expect(item2!.protectedValue!.getText()).assertEqual('456');
            expect(inner!.textContent).assertEqual(inner!.protectedValue!.toString());
            expect(item2!.textContent).assertEqual(item2!.protectedValue!.toString());
            expect((inner as Element).getAttribute('Protected')).to.be.ok();
            expect((inner as Element).getAttribute('ProtectInMemory')).not.be.ok();
        });
    });
});
