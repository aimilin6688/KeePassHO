import { describe, expect, it } from '@ohos/hypium';
import { Kdbx, KdbxContext, KdbxCustomData, KdbxCustomDataItem, XmlUtils } from '../../../../main/ets/index';
export default function KdbxCustomDataTest() {
    describe('KdbxCustomData', () => {
        const kdbx = new Kdbx();
        const ctx = new KdbxContext({ kdbx });

        it('reads custom data from xml', 0,() => {
            const xml = XmlUtils.parse(
                '<CustomData>' +
                    '<Item><Key>k1</Key><Value>v1</Value></Item>' +
                    '<Item><Key>k2</Key><Value>v2</Value></Item>' +
                    '</CustomData>'
            );
            const cd = KdbxCustomData.read(xml.documentElement);
            expect([...cd.entries()]).assertDeepEquals([
                ['k1', { value: 'v1' }],
                ['k2', { value: 'v2' }]
            ]);
        });

        it('reads empty custom data from empty xml', 0,() => {
            const xml = XmlUtils.parse('<CustomData></CustomData>');
            const cd = KdbxCustomData.read(xml.documentElement);
            expect(cd).assertDeepEquals({});
        });

        it('skips unknown tags', 0,() => {
            const xml = XmlUtils.parse(
                '<CustomData><Item><Key>k</Key><Value>v</Value><x></x></Item><Something></Something></CustomData>'
            );
            const cd = KdbxCustomData.read(xml.documentElement);
            expect([...cd.entries()]).assertDeepEquals([['k', { value: 'v' }]]);
        });

        it('skips empty keys', 0,() => {
            const xml = XmlUtils.parse(
                '<CustomData><Item><Key></Key><Value>v</Value></Item></CustomData>'
            );
            const cd = KdbxCustomData.read(xml.documentElement);
            expect(cd).assertDeepEquals({});
        });

        it('writes custom data to xml', 0,() => {
            const xml = XmlUtils.create('root');
            KdbxCustomData.write(
                xml.documentElement,
                ctx,
                new Map([
                    ['k1', { value: 'v1' }],
                    ['k2', { value: 'v2' }]
                ])
            );
            expect(XmlUtils.serialize(<Document>(<unknown>xml.documentElement))).assertDeepEquals(
                '<root><CustomData>' +
                    '<Item><Key>k1</Key><Value>v1</Value></Item>' +
                    '<Item><Key>k2</Key><Value>v2</Value></Item>' +
                    '</CustomData></root>'
            );
        });

        it('writes empty custom data to xml', 0,() => {
            const xml = XmlUtils.create('root');
            KdbxCustomData.write(xml.documentElement, ctx, new Map());
            expect(
                XmlUtils.serialize(<Document>(<unknown>xml.documentElement)).replace(/\s/g, '')
            ).assertDeepEquals('<root><CustomData/></root>');
        });

        it('does not create tag for empty custom data', 0,() => {
            const xml = XmlUtils.create('root');
            KdbxCustomData.write(xml.documentElement, ctx, undefined);
            expect(
                XmlUtils.serialize(<Document>(<unknown>xml.documentElement)).replace(/\s/g, '')
            ).assertDeepEquals('<root/>');
        });

        it('skips keys without values', 0,() => {
            const xml = XmlUtils.create('root');
            KdbxCustomData.write(
                xml.documentElement,
                ctx,
                new Map<string, KdbxCustomDataItem>([
                    ['k1', { value: 'v1' }],
                    ['k2', { value: '' }],
                    ['k3', { value: undefined }]
                ])
            );
            expect(XmlUtils.serialize(<Document>(<unknown>xml.documentElement))).assertDeepEquals(
                '<root><CustomData>' +
                    '<Item><Key>k1</Key><Value>v1</Value></Item>' +
                    '</CustomData></root>'
            );
        });
    });
}

