import { describe, expect, it } from '@ohos/hypium';
import { Document } from '@xmldom/xmldom';
import { Kdbx, KdbxContext, KdbxCustomData, KdbxCustomDataItem, XmlUtils } from '../../../../main/ets/index';

function getDocumentXml(doc:Document | string) {
    return doc.toString().replace('<?xml version="1.0" encoding="utf-8" standalone="yes"?>', '');
}

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
            expect(Array.from(cd.entries())).assertDeepEquals([
                ['k1', { value: 'v1' } as KdbxCustomDataItem],
                ['k2', { value: 'v2' } as KdbxCustomDataItem]
            ]);
        });

        it('reads empty custom data from empty xml', 0, () => {
            const xml = XmlUtils.parse('<CustomData></CustomData>');
            const cd = KdbxCustomData.read(xml.documentElement);
            expect(cd).assertDeepEquals(new Map());
        });

        it('skips unknown tags', 0,() => {
            const xml = XmlUtils.parse(
                '<CustomData><Item><Key>k</Key><Value>v</Value><x></x></Item><Something></Something></CustomData>'
            );
            const cd = KdbxCustomData.read(xml.documentElement);
            expect(Array.from(cd.entries())).assertDeepEquals([['k', { value: 'v' } as KdbxCustomDataItem]]);
        });

        it('skips empty keys', 0,() => {
            const xml = XmlUtils.parse(
                '<CustomData><Item><Key></Key><Value>v</Value></Item></CustomData>'
            );
            const cd = KdbxCustomData.read(xml.documentElement);
            expect(cd).assertDeepEquals(new Map());
        });

        it('writes custom data to xml', 0,() => {
            const xml = XmlUtils.create('root');
            KdbxCustomData.write(
                xml.documentElement,
                ctx,
                new Map([
                    ['k1', { value: 'v1' }  as KdbxCustomDataItem],
                    ['k2', { value: 'v2' }  as KdbxCustomDataItem]
                ])
            );
            expect(getDocumentXml(XmlUtils.serialize(xml))).assertEqual(
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
                getDocumentXml(XmlUtils.serialize(xml)).replace(/\s/g, '')
            ).assertEqual('<root><CustomData/></root>');
        });

        it('does not create tag for empty custom data', 0,() => {
            const xml = XmlUtils.create('root');
            KdbxCustomData.write(xml.documentElement, ctx, undefined);
            expect(
                getDocumentXml(XmlUtils.serialize(xml)).replace(/\s/g, '')
            ).assertEqual('<root/>');
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
            expect(getDocumentXml(XmlUtils.serialize(xml))).assertEqual(
                '<root><CustomData>' +
                    '<Item><Key>k1</Key><Value>v1</Value></Item>' +
                    '</CustomData></root>'
            );
        });
    });
}

