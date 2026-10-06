import { fileIo as fs } from '@kit.CoreFileKit';
import util from '@ohos.util';
import { ungzip } from '@ohos/flate2';
import * as XmlNames from '../defs/xml-names';
import { KdbxError } from '../errors/kdbx-error';
import { ErrorCodes, Icons } from '../defs/consts';
import {
    arrayToBuffer,
    base64ToBytes
} from './byte-utils';
import { Int64 } from './int64';
import { KdbxUuid } from '../format/kdbx-uuid';
import { ProtectedValue } from '../crypto/protected-value';
import { ProtectSaltGenerator } from '../crypto/protect-salt-generator';
import { Kdbx } from '../format/kdbx';
import { KdbxContext } from '../format/kdbx-context';
import { KdbxMeta, KdbxCustomIcon } from '../format/kdbx-meta';
import { KdbxGroup } from '../format/kdbx-group';
import { KdbxEntry } from '../format/kdbx-entry';
import { KdbxTimes } from '../format/kdbx-times';
import { KdbxDeletedObject } from '../format/kdbx-deleted-object';
import {
    KdbxBinaries,
    KdbxBinary,
    KdbxBinaryOrRef,
    KdbxBinaryRef,
    KdbxBinaryWithHash
} from '../format/kdbx-binaries';

const EpochSeconds = 62135596800;
const DateRegex = /\.\d\d\d/;
const TagsSplitRegex = /\s*[;,:]\s*/;

// ==================== text → value helpers（镜像 XmlUtils.getXxx，去 Node 包装） ====================

function strToBoolean(str: string | null | undefined): boolean | null | undefined {
    switch (str?.toLowerCase()) {
        case 'true':
            return true;
        case 'false':
            return false;
        case 'null':
            return null;
    }
    return undefined;
}

function textToDate(text: string | undefined): Date | undefined {
    if (!text) {
        return undefined;
    }
    if (text.indexOf(':') > 0) {
        return new Date(text);
    }
    const bytes = new DataView(arrayToBuffer(base64ToBytes(text)));
    const secondsFrom00 = new Int64(bytes.getUint32(0, true), bytes.getUint32(4, true)).value;
    const diff = (secondsFrom00 - EpochSeconds) * 1000;
    return new Date(diff);
}

function textToNumber(text: string | undefined): number | undefined {
    return text ? +text : undefined;
}

function textToBoolean(text: string | undefined): boolean | null | undefined {
    return text ? strToBoolean(text) : undefined;
}

function textToBytes(text: string | undefined): ArrayBuffer | undefined {
    return text ? arrayToBuffer(base64ToBytes(text)) : undefined;
}

function textToUuid(text: string | undefined): KdbxUuid | undefined {
    const bytes = textToBytes(text);
    return bytes ? new KdbxUuid(bytes) : undefined;
}

function textToTags(text: string | undefined): string[] {
    if (!text) {
        return [];
    }
    return text
        .split(TagsSplitRegex)
        .map((t) => t.trim())
        .filter((s) => s);
}

// ==================== 实体解码 ====================

function decodeEntities(s: string): string {
    if (s.indexOf('&') < 0) {
        return s;
    }
    return s
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
        .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
        .replace(/&amp;/g, '&');
}

// ==================== ChunkReader 抽象 ====================

/**
 * 分块读取器接口：KdbxXmlPullParser 的输入源。
 * 实现方负责按块返回 UTF-8 解码后的字符串，EOF 返回 null。
 * 跨块 UTF-8 边界处理由实现方负责（复用 findUtf8Boundary）。
 */
export interface ChunkReader {
    readNext(): Promise<string | null>;
}

function findUtf8Boundary(bytes: Uint8Array): number {
    const len = bytes.length;
    if (len === 0) {
        return 0;
    }
    let i = len - 1;
    while (i >= 0 && (bytes[i] & 0xC0) === 0x80) {
        i--;
    }
    if (i < 0) {
        return 0;
    }
    const b = bytes[i];
    if ((b & 0x80) === 0) {
        return len;
    }
    let expected: number;
    if ((b & 0xE0) === 0xC0) {
        expected = 2;
    } else if ((b & 0xF0) === 0xE0) {
        expected = 3;
    } else if ((b & 0xF8) === 0xF0) {
        expected = 4;
    } else {
        return len;
    }
    const have = len - i;
    return have < expected ? i : len;
}

interface DecodeResult {
    text: string | null;
    newLeftover: Uint8Array;
}

/**
 * 将 Uint8Array 按 UTF-8 边界切分、解码、过滤控制字符。
 * FileChunkReader 和 MemoryChunkReader 共用此逻辑。
 */
function decodeUtf8Chunk(
    bytes: Uint8Array,
    oldLeftover: Uint8Array,
    decoder: util.TextDecoder
): DecodeResult {
    if (oldLeftover.length > 0) {
        const merged = new Uint8Array(oldLeftover.length + bytes.length);
        merged.set(oldLeftover, 0);
        merged.set(bytes, oldLeftover.length);
        bytes = merged;
    }
    const validEnd = findUtf8Boundary(bytes);
    let newLeftover = new Uint8Array(0);
    if (validEnd < bytes.length) {
        newLeftover = new Uint8Array(bytes.length - validEnd);
        newLeftover.set(bytes.subarray(validEnd));
        bytes = bytes.subarray(0, validEnd);
    }
    if (bytes.length === 0) {
        return { text: null, newLeftover };
    }
    let str = decoder.decodeToString(bytes);
    str = str.replace(/[\x00-\x09\x0B-\x0C\x0E-\x1F]/g, '');
    return { text: str, newLeftover };
}

// ==================== FileChunkReader ====================

export class FileChunkReader implements ChunkReader {
    private readonly fd: number;
    private offset: number;
    private readonly end: number;
    private readonly chunkSize: number;
    private readonly decoder: util.TextDecoder;
    private leftover: Uint8Array = new Uint8Array(0);

    constructor(fd: number, start: number, length: number, chunkSize?: number) {
        this.fd = fd;
        this.offset = start;
        this.end = start + length;
        this.chunkSize = chunkSize || (256 * 1024);
        this.decoder = new util.TextDecoder();
    }

    readNext(): Promise<string | null> {
        if (this.offset >= this.end && this.leftover.length === 0) {
            return Promise.resolve(null);
        }
        const len = Math.min(this.chunkSize, this.end - this.offset);
        if (len <= 0) {
            const str = this.decoder.decodeToString(this.leftover);
            this.leftover = new Uint8Array(0);
            return Promise.resolve(str);
        }
        const buf = new ArrayBuffer(len);
        return fs.read(this.fd, buf, { offset: this.offset }).then((n) => {
            this.offset += n;
            let bytes: Uint8Array = n === len ? new Uint8Array(buf) : new Uint8Array(buf, 0, n);
            const result = decodeUtf8Chunk(bytes, this.leftover, this.decoder);
            this.leftover = result.newLeftover;
            if (result.text === null) {
                return this.readNext();
            }
            return result.text;
        });
    }
}

// ==================== MemoryChunkReader ====================

/**
 * 内存分块读取器：从内存 ArrayBuffer 按块切片喂给 KdbxXmlPullParser。
 * 用于 KdbxSnapshot.load 等场景（XML 已在内存，无需落盘）。
 */
export class MemoryChunkReader implements ChunkReader {
    private readonly data: Uint8Array;
    private readonly chunkSize: number;
    private readonly decoder: util.TextDecoder;
    private offset: number;
    private leftover: Uint8Array = new Uint8Array(0);

    constructor(data: ArrayBuffer | Uint8Array, chunkSize?: number) {
        this.data = data instanceof Uint8Array ? data : new Uint8Array(data);
        this.chunkSize = chunkSize || (256 * 1024);
        this.decoder = new util.TextDecoder();
        this.offset = 0;
    }

    readNext(): Promise<string | null> {
        if (this.offset >= this.data.length && this.leftover.length === 0) {
            return Promise.resolve(null);
        }
        const len = Math.min(this.chunkSize, this.data.length - this.offset);
        if (len <= 0) {
            const str = this.decoder.decodeToString(this.leftover);
            this.leftover = new Uint8Array(0);
            return Promise.resolve(str);
        }
        const bytes = this.data.subarray(this.offset, this.offset + len);
        this.offset += len;
        const result = decodeUtf8Chunk(bytes, this.leftover, this.decoder);
        this.leftover = result.newLeftover;
        if (result.text === null) {
            return this.readNext();
        }
        return Promise.resolve(result.text);
    }
}

// ==================== 事件类型 ====================

interface XmlStartEvent { type: 'start'; name: string; attrs: Map<string, string>; }
interface XmlEndEvent { type: 'end'; name: string; }
interface XmlTextEvent { type: 'text'; text: string; }
type XmlEvent = XmlStartEvent | XmlEndEvent | XmlTextEvent;

interface XmlHandler {
    onStartElement(name: string, attrs: Map<string, string>): void;
    onEndElement(name: string): void;
    onText(text: string): void;
}

// ==================== KdbxXmlPullParser tokenizer ====================

/**
 * 手写状态机 XML 拉取解析器（设计文档 §7.2）。
 * 输入：FileChunkReader（256KB 块，跨块标签/实体缓冲拼接）。
 * 输出：事件式（startElement/endElement/text），无中间节点树。
 * 支持：元素/属性/自闭合/文本实体/CDATA/注释/声明。跨块安全。
 */
export class KdbxXmlPullParser {
    private readonly reader: ChunkReader;
    private readonly handler: XmlHandler;
    private pending: string = '';
    private eof: boolean = false;
    private eventQueue: XmlEvent[] = [];

    constructor(reader: ChunkReader, handler: XmlHandler) {
        this.reader = reader;
        this.handler = handler;
    }

    parse(): Promise<void> {
        return this.fillAndProcess();
    }

    private fillAndProcess(): Promise<void> {
        return this.reader.readNext().then((chunk) => {
            if (chunk === null) {
                this.eof = true;
                this.flushRemaining();
            } else {
                this.pending += chunk;
            }
            this.extract();
            this.dispatch();
            if (this.eof) {
                return Promise.resolve();
            }
            return this.fillAndProcess();
        });
    }

    private dispatch(): void {
        while (this.eventQueue.length > 0) {
            const ev = this.eventQueue.shift()!;
            if (ev.type === 'start') {
                this.handler.onStartElement(ev.name, ev.attrs);
            } else if (ev.type === 'end') {
                this.handler.onEndElement(ev.name);
            } else {
                this.handler.onText(ev.text);
            }
        }
    }

    private flushRemaining(): void {
        if (this.pending.length > 0) {
            const text = decodeEntities(this.pending);
            if (text.length > 0) {
                this.eventQueue.push({ type: 'text', text });
            }
            this.pending = '';
        }
    }

    private extract(): void {
        while (this.pending.length > 0) {
            if (this.pending[0] === '<') {
                if (!this.extractMarkup()) {
                    return;
                }
            } else {
                if (!this.extractText()) {
                    return;
                }
            }
        }
    }

    private extractText(): boolean {
        const lt = this.pending.indexOf('<');
        if (lt < 0) {
            if (this.eof) {
                const text = decodeEntities(this.pending);
                if (text.length > 0) {
                    this.eventQueue.push({ type: 'text', text });
                }
                this.pending = '';
                return true;
            }
            return false;
        }
        if (lt > 0) {
            const raw = this.pending.substring(0, lt);
            const text = decodeEntities(raw);
            if (text.length > 0) {
                this.eventQueue.push({ type: 'text', text });
            }
            this.pending = this.pending.substring(lt);
        }
        return true;
    }

    private extractMarkup(): boolean {
        const p = this.pending;
        if (p.startsWith('<!--')) {
            const end = p.indexOf('-->');
            if (end < 0) {
                return false;
            }
            this.pending = p.substring(end + 3);
            return true;
        }
        if (p.startsWith('<![CDATA[')) {
            const end = p.indexOf(']]>');
            if (end < 0) {
                return false;
            }
            const content = p.substring(9, end);
            if (content.length > 0) {
                this.eventQueue.push({ type: 'text', text: content });
            }
            this.pending = p.substring(end + 3);
            return true;
        }
        if (p.startsWith('<?')) {
            const end = p.indexOf('?>');
            if (end < 0) {
                return false;
            }
            this.pending = p.substring(end + 2);
            return true;
        }
        const gt = this.findTagEnd(p);
        if (gt < 0) {
            return false;
        }
        const tagStr = p.substring(0, gt + 1);
        this.pending = p.substring(gt + 1);
        this.parseTag(tagStr);
        return true;
    }

    private findTagEnd(s: string): number {
        let inQuote = '';
        for (let i = 1; i < s.length; i++) {
            const c = s[i];
            if (inQuote) {
                if (c === inQuote) {
                    inQuote = '';
                }
            } else {
                if (c === '"' || c === "'") {
                    inQuote = c;
                } else if (c === '>') {
                    return i;
                }
            }
        }
        return -1;
    }

    private parseTag(tagStr: string): void {
        let s = tagStr.substring(1, tagStr.length - 1);
        if (s[0] === '/') {
            const name = s.substring(1).trim();
            this.eventQueue.push({ type: 'end', name });
            return;
        }
        let selfClose = false;
        if (s.endsWith('/')) {
            selfClose = true;
            s = s.substring(0, s.length - 1);
        }
        const sp = s.indexOf(' ');
        let name: string;
        let attrPart = '';
        if (sp < 0) {
            name = s.trim();
        } else {
            name = s.substring(0, sp).trim();
            attrPart = s.substring(sp + 1).trim();
        }
        const attrs = this.parseAttrs(attrPart);
        this.eventQueue.push({ type: 'start', name, attrs });
        if (selfClose) {
            this.eventQueue.push({ type: 'end', name });
        }
    }

    private parseAttrs(attrPart: string): Map<string, string> {
        const attrs = new Map<string, string>();
        if (!attrPart) {
            return attrs;
        }
        let i = 0;
        const len = attrPart.length;
        while (i < len) {
            while (i < len && (attrPart[i] === ' ' || attrPart[i] === '\t' || attrPart[i] === '\n' || attrPart[i] === '\r')) {
                i++;
            }
            if (i >= len) {
                break;
            }
            const eq = attrPart.indexOf('=', i);
            if (eq < 0) {
                break;
            }
            const name = attrPart.substring(i, eq).trim();
            i = eq + 1;
            while (i < len && (attrPart[i] === ' ' || attrPart[i] === '\t')) {
                i++;
            }
            if (i >= len) {
                break;
            }
            const q = attrPart[i];
            if (q !== '"' && q !== "'") {
                break;
            }
            i++;
            const close = attrPart.indexOf(q, i);
            if (close < 0) {
                break;
            }
            const rawVal = attrPart.substring(i, close);
            attrs.set(name, decodeEntities(rawVal));
            i = close + 1;
        }
        return attrs;
    }
}

// ==================== KdbxModelBuilder（handler 实现） ====================

type FrameKind =
    | 'doc'
    | 'meta'
    | 'root'
    | 'group'
    | 'entry'
    | 'times'
    | 'autoType'
    | 'autoTypeItem'
    | 'stringField'
    | 'binaryField'
    | 'metaBinary'
    | 'history'
    | 'customData'
    | 'customDataItem'
    | 'memoryProt'
    | 'customIcons'
    | 'customIconItem'
    | 'binaries'
    | 'deletedObjects'
    | 'deletedObject'
    | 'leaf';

interface Frame {
    kind: FrameKind;
    group?: KdbxGroup;
    entry?: KdbxEntry;
    meta?: KdbxMeta;
    times?: KdbxTimes;
    autoTypeItem?: { window: string; keystrokeSequence: string };
    customDataItem?: { key: string | undefined; value: string | undefined; lastModified: Date | undefined };
    customIcon?: { uuid: KdbxUuid | undefined; data: ArrayBuffer | undefined; name: string | undefined; lastModified: Date | undefined };
    deletedObject?: KdbxDeletedObject;
    leafName?: string;
    leafText?: string;
    leafAttrs?: Map<string, string>;
    fieldKey?: string;
    fieldValue?: ProtectedValue | string | undefined;
    fieldBinary?: KdbxBinaryOrRef;
    valuePresent?: boolean;
    metaBinaryId?: string;
    metaBinaryValue?: KdbxBinaryOrRef;
}

/**
 * 流式拉取解析器的模型构建器：直接构建 Kdbx 模型对象，不建 DOM。
 * 镜像 KdbxMeta/KdbxGroup/KdbxEntry/KdbxTimes/KdbxDeletedObject/KdbxCustomData 的 readNode 逻辑。
 * ProtectedValue 边解析边用 ProtectSaltGenerator 取 salt（流式 XOR，密钥流状态跨元素保持）。
 */
export class KdbxModelBuilder implements XmlHandler {
    private readonly kdbx: Kdbx;
    private readonly ctx: KdbxContext;
    private readonly gen: ProtectSaltGenerator | undefined;
    private readonly stack: Frame[] = [];
    readonly pendingEntryBinaries: { entry: KdbxEntry; key: string; ref: string }[] = [];

    constructor(kdbx: Kdbx, ctx: KdbxContext, gen: ProtectSaltGenerator | undefined) {
        this.kdbx = kdbx;
        this.ctx = ctx;
        this.gen = gen;
        this.stack.push({ kind: 'doc' });
    }

    onStartElement(name: string, attrs: Map<string, string>): void {
        const top = this.stack[this.stack.length - 1];
        switch (top.kind) {
            case 'doc':
                if (name === XmlNames.Elem.DocNode) {
                    this.push({ kind: 'doc' });
                } else if (name === XmlNames.Elem.Meta) {
                    this.push({ kind: 'meta', meta: new KdbxMeta() });
                } else if (name === XmlNames.Elem.Root) {
                    this.push({ kind: 'root' });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'meta':
                this.enterMetaChild(name, attrs);
                break;
            case 'memoryProt':
                this.pushLeaf(name);
                break;
            case 'customIcons':
                if (name === XmlNames.Elem.CustomIconItem) {
                    this.push({ kind: 'customIconItem', customIcon: { uuid: undefined, data: undefined, name: undefined, lastModified: undefined } });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'customIconItem':
                this.pushLeaf(name);
                break;
            case 'binaries':
                if (name === XmlNames.Elem.Binary) {
                    this.push({ kind: 'metaBinary', metaBinaryId: attrs.get(XmlNames.Attr.Id) || undefined });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'metaBinary':
                if (name === XmlNames.Elem.Value) {
                    this.pushLeaf(name, attrs);
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'customData':
                if (name === XmlNames.Elem.StringDictExItem) {
                    this.push({ kind: 'customDataItem', customDataItem: { key: undefined, value: undefined, lastModified: undefined } });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'customDataItem':
                this.pushLeaf(name);
                break;
            case 'root':
                if (name === XmlNames.Elem.Group) {
                    const parentGroup = undefined;
                    const g = new KdbxGroup();
                    g.parentGroup = parentGroup;
                    this.push({ kind: 'group', group: g });
                } else if (name === XmlNames.Elem.DeletedObjects) {
                    this.push({ kind: 'deletedObjects' });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'group':
                this.enterGroupChild(name);
                break;
            case 'entry':
                this.enterEntryChild(name);
                break;
            case 'history':
                if (name === XmlNames.Elem.Entry) {
                    const e = new KdbxEntry();
                    this.push({ kind: 'entry', entry: e });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'times':
                this.pushLeaf(name);
                break;
            case 'autoType':
                if (name === XmlNames.Elem.AutoTypeItem) {
                    this.push({ kind: 'autoTypeItem', autoTypeItem: { window: '', keystrokeSequence: '' } });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'autoTypeItem':
                this.pushLeaf(name);
                break;
            case 'stringField':
                this.pushLeaf(name, attrs);
                break;
            case 'binaryField':
                this.pushLeaf(name, attrs);
                break;
            case 'deletedObjects':
                if (name === XmlNames.Elem.DeletedObject) {
                    this.push({ kind: 'deletedObject', deletedObject: new KdbxDeletedObject() });
                } else {
                    this.pushLeaf(name);
                }
                break;
            case 'deletedObject':
                this.pushLeaf(name);
                break;
            default:
                this.pushLeaf(name);
        }
    }

    private enterMetaChild(name: string, attrs: Map<string, string>): void {
        const meta = this.stack[this.stack.length - 1].meta!;
        switch (name) {
            case XmlNames.Elem.MemoryProt:
                this.push({ kind: 'memoryProt', meta });
                break;
            case XmlNames.Elem.CustomIcons:
                this.push({ kind: 'customIcons' });
                break;
            case XmlNames.Elem.Binaries:
                this.push({ kind: 'binaries' });
                break;
            case XmlNames.Elem.CustomData:
                this.push({ kind: 'customData' });
                break;
            default:
                this.pushLeaf(name);
        }
    }

    private enterGroupChild(name: string): void {
        const parentGroup = this.stack[this.stack.length - 1].group!;
        switch (name) {
            case XmlNames.Elem.Group: {
                const g = new KdbxGroup();
                g.parentGroup = parentGroup;
                this.push({ kind: 'group', group: g });
                break;
            }
            case XmlNames.Elem.Entry: {
                const e = new KdbxEntry();
                e.parentGroup = parentGroup;
                this.push({ kind: 'entry', entry: e });
                break;
            }
            case XmlNames.Elem.Times:
                this.push({ kind: 'times', times: new KdbxTimes() });
                break;
            case XmlNames.Elem.CustomData:
                this.push({ kind: 'customData' });
                break;
            default:
                this.pushLeaf(name);
        }
    }

    private enterEntryChild(name: string): void {
        const entry = this.stack[this.stack.length - 1].entry!;
        switch (name) {
            case XmlNames.Elem.Times:
                this.push({ kind: 'times', times: new KdbxTimes() });
                break;
            case XmlNames.Elem.String:
                this.push({ kind: 'stringField' });
                break;
            case XmlNames.Elem.Binary:
                this.push({ kind: 'binaryField' });
                break;
            case XmlNames.Elem.AutoType:
                this.push({ kind: 'autoType' });
                break;
            case XmlNames.Elem.History:
                this.push({ kind: 'history' });
                break;
            case XmlNames.Elem.CustomData:
                this.push({ kind: 'customData' });
                break;
            default:
                this.pushLeaf(name);
        }
    }

    onText(text: string): void {
        const top = this.stack[this.stack.length - 1];
        if (top.kind === 'leaf') {
            top.leafText = (top.leafText || '') + text;
        }
    }

    onEndElement(name: string): void {
        const top = this.stack[this.stack.length - 1];
        if (top.kind === 'leaf') {
            this.commitLeaf(top, name);
            this.stack.pop();
            return;
        }
        this.commitContainer(top);
        this.stack.pop();
    }

    private commitLeaf(leaf: Frame, name: string): void {
        const parent = this.stack[this.stack.length - 2];
        const text = leaf.leafText;
        switch (parent.kind) {
            case 'meta':
                this.commitMetaLeaf(parent.meta!, name, text);
                break;
            case 'memoryProt':
                this.commitMemoryProtLeaf(parent.meta!, name, text);
                break;
            case 'customIconItem':
                this.commitCustomIconLeaf(parent.customIcon!, name, text);
                break;
            case 'customDataItem':
                this.commitCustomDataItemLeaf(parent.customDataItem!, name, text);
                break;
            case 'times':
                this.commitTimesLeaf(parent.times!, name, text);
                break;
            case 'autoTypeItem':
                this.commitAutoTypeItemLeaf(parent.autoTypeItem!, name, text);
                break;
            case 'group':
                this.commitGroupLeaf(parent.group!, name, text);
                break;
            case 'entry':
                this.commitEntryLeaf(parent.entry!, name, text);
                break;
            case 'deletedObject':
                this.commitDeletedObjectLeaf(parent.deletedObject!, name, text);
                break;
            case 'stringField':
                this.commitStringFieldLeaf(parent, name, text, leaf);
                break;
            case 'binaryField':
                this.commitBinaryFieldLeaf(parent, name, text, leaf);
                break;
            case 'metaBinary':
                this.commitMetaBinaryLeaf(parent, name, text, leaf);
                break;
            case 'autoType':
                this.commitAutoTypeLeaf(parent, name, text);
                break;
            default:
                break;
        }
    }

    private commitAutoTypeLeaf(parent: Frame, name: string, text: string | undefined): void {
        const owner = this.stack[this.stack.length - 3];
        if (owner.kind !== 'entry') {
            return;
        }
        const e = owner.entry!;
        switch (name) {
            case XmlNames.Elem.AutoTypeEnabled: e.autoType.enabled = textToBoolean(text) ?? true; break;
            case XmlNames.Elem.AutoTypeObfuscation: e.autoType.obfuscation = textToNumber(text) || 0; break;
            case XmlNames.Elem.AutoTypeDefaultSeq: e.autoType.defaultSequence = text; break;
            default: break;
        }
    }

    private commitMetaLeaf(meta: KdbxMeta, name: string, text: string | undefined): void {
        const m = meta as any;
        switch (name) {
            case XmlNames.Elem.Generator: meta.generator = text; break;
            case XmlNames.Elem.HeaderHash: meta.headerHash = textToBytes(text); break;
            case XmlNames.Elem.SettingsChanged: meta.settingsChanged = textToDate(text); break;
            case XmlNames.Elem.DbName: m._name = text; break;
            case XmlNames.Elem.DbNameChanged: meta.nameChanged = textToDate(text); break;
            case XmlNames.Elem.DbDesc: m._desc = text; break;
            case XmlNames.Elem.DbDescChanged: meta.descChanged = textToDate(text); break;
            case XmlNames.Elem.DbDefaultUser: m._defaultUser = text; break;
            case XmlNames.Elem.DbDefaultUserChanged: meta.defaultUserChanged = textToDate(text); break;
            case XmlNames.Elem.DbMntncHistoryDays: m._mntncHistoryDays = textToNumber(text); break;
            case XmlNames.Elem.DbColor: m._color = text; break;
            case XmlNames.Elem.DbKeyChanged: meta.keyChanged = textToDate(text); break;
            case XmlNames.Elem.DbKeyChangeRec: m._keyChangeRec = textToNumber(text); break;
            case XmlNames.Elem.DbKeyChangeForce: m._keyChangeForce = textToNumber(text); break;
            case XmlNames.Elem.RecycleBinEnabled: m._recycleBinEnabled = textToBoolean(text) ?? undefined; break;
            case XmlNames.Elem.RecycleBinUuid: m._recycleBinUuid = textToUuid(text); break;
            case XmlNames.Elem.RecycleBinChanged: meta.recycleBinChanged = textToDate(text); break;
            case XmlNames.Elem.EntryTemplatesGroup: m._entryTemplatesGroup = textToUuid(text); break;
            case XmlNames.Elem.EntryTemplatesGroupChanged: meta.entryTemplatesGroupChanged = textToDate(text); break;
            case XmlNames.Elem.HistoryMaxItems: m._historyMaxItems = textToNumber(text); break;
            case XmlNames.Elem.HistoryMaxSize: m._historyMaxSize = textToNumber(text); break;
            case XmlNames.Elem.LastSelectedGroup: m._lastSelectedGroup = textToUuid(text); break;
            case XmlNames.Elem.LastTopVisibleGroup: m._lastTopVisibleGroup = textToUuid(text); break;
            default: break;
        }
    }

    private commitMemoryProtLeaf(meta: KdbxMeta, name: string, text: string | undefined): void {
        const v = textToBoolean(text) ?? undefined;
        switch (name) {
            case XmlNames.Elem.ProtTitle: meta.memoryProtection.title = v; break;
            case XmlNames.Elem.ProtUserName: meta.memoryProtection.userName = v; break;
            case XmlNames.Elem.ProtPassword: meta.memoryProtection.password = v; break;
            case XmlNames.Elem.ProtUrl: meta.memoryProtection.url = v; break;
            case XmlNames.Elem.ProtNotes: meta.memoryProtection.notes = v; break;
            default: break;
        }
    }

    private commitCustomIconLeaf(
        icon: { uuid: KdbxUuid | undefined; data: ArrayBuffer | undefined; name: string | undefined; lastModified: Date | undefined },
        name: string, text: string | undefined
    ): void {
        switch (name) {
            case XmlNames.Elem.CustomIconItemID: icon.uuid = textToUuid(text); break;
            case XmlNames.Elem.CustomIconItemData: icon.data = textToBytes(text); break;
            case XmlNames.Elem.CustomIconItemName: icon.name = text ?? undefined; break;
            case XmlNames.Elem.LastModTime: icon.lastModified = textToDate(text); break;
            default: break;
        }
    }

    private commitCustomDataItemLeaf(
        item: { key: string | undefined; value: string | undefined; lastModified: Date | undefined },
        name: string, text: string | undefined
    ): void {
        switch (name) {
            case XmlNames.Elem.Key: item.key = text; break;
            case XmlNames.Elem.Value: item.value = text; break;
            case XmlNames.Elem.LastModTime: item.lastModified = textToDate(text); break;
            default: break;
        }
    }

    private commitTimesLeaf(times: KdbxTimes, name: string, text: string | undefined): void {
        switch (name) {
            case XmlNames.Elem.CreationTime: times.creationTime = textToDate(text); break;
            case XmlNames.Elem.LastModTime: times.lastModTime = textToDate(text); break;
            case XmlNames.Elem.LastAccessTime: times.lastAccessTime = textToDate(text); break;
            case XmlNames.Elem.ExpiryTime: times.expiryTime = textToDate(text); break;
            case XmlNames.Elem.Expires: times.expires = textToBoolean(text); break;
            case XmlNames.Elem.UsageCount: times.usageCount = textToNumber(text); break;
            case XmlNames.Elem.LocationChanged: times.locationChanged = textToDate(text); break;
            default: break;
        }
    }

    private commitAutoTypeItemLeaf(
        item: { window: string; keystrokeSequence: string }, name: string, text: string | undefined
    ): void {
        switch (name) {
            case XmlNames.Elem.Window: item.window = text || ''; break;
            case XmlNames.Elem.KeystrokeSequence: item.keystrokeSequence = text || ''; break;
            default: break;
        }
    }

    private commitGroupLeaf(group: KdbxGroup, name: string, text: string | undefined): void {
        switch (name) {
            case XmlNames.Elem.Uuid: group.uuid = textToUuid(text) ?? new KdbxUuid(); break;
            case XmlNames.Elem.Name: group.name = text; break;
            case XmlNames.Elem.Notes: group.notes = text; break;
            case XmlNames.Elem.Icon: group.icon = textToNumber(text); break;
            case XmlNames.Elem.CustomIconID: group.customIcon = textToUuid(text); break;
            case XmlNames.Elem.Tags: group.tags = textToTags(text); break;
            case XmlNames.Elem.IsExpanded: group.expanded = textToBoolean(text) ?? undefined; break;
            case XmlNames.Elem.GroupDefaultAutoTypeSeq: group.defaultAutoTypeSeq = text; break;
            case XmlNames.Elem.EnableAutoType: group.enableAutoType = textToBoolean(text); break;
            case XmlNames.Elem.EnableSearching: group.enableSearching = textToBoolean(text); break;
            case XmlNames.Elem.LastTopVisibleEntry: group.lastTopVisibleEntry = textToUuid(text); break;
            case XmlNames.Elem.PreviousParentGroup: group.previousParentGroup = textToUuid(text); break;
            default: break;
        }
    }

    private commitEntryLeaf(entry: KdbxEntry, name: string, text: string | undefined): void {
        switch (name) {
            case XmlNames.Elem.Uuid: entry.uuid = textToUuid(text) ?? new KdbxUuid(); break;
            case XmlNames.Elem.Icon: entry.icon = textToNumber(text) || Icons.Key; break;
            case XmlNames.Elem.CustomIconID: entry.customIcon = textToUuid(text); break;
            case XmlNames.Elem.FgColor: entry.fgColor = text; break;
            case XmlNames.Elem.BgColor: entry.bgColor = text; break;
            case XmlNames.Elem.OverrideUrl: entry.overrideUrl = text; break;
            case XmlNames.Elem.Tags: entry.tags = textToTags(text); break;
            case XmlNames.Elem.QualityCheck: entry.qualityCheck = textToBoolean(text) ?? undefined; break;
            case XmlNames.Elem.PreviousParentGroup: entry.previousParentGroup = textToUuid(text); break;
            default: break;
        }
    }

    private commitDeletedObjectLeaf(obj: KdbxDeletedObject, name: string, text: string | undefined): void {
        switch (name) {
            case XmlNames.Elem.Uuid: obj.uuid = textToUuid(text); break;
            case XmlNames.Elem.DeletionTime: obj.deletionTime = textToDate(text); break;
            default: break;
        }
    }

    private commitStringFieldLeaf(parent: Frame, name: string, text: string | undefined, leaf: Frame): void {
        if (name === XmlNames.Elem.Key) {
            parent.fieldKey = text;
        } else if (name === XmlNames.Elem.Value) {
            parent.fieldValue = this.readProtectedText(text, leaf.leafAttrs);
            parent.valuePresent = true;
        }
    }

    private commitBinaryFieldLeaf(parent: Frame, name: string, text: string | undefined, leaf: Frame): void {
        if (name === XmlNames.Elem.Key) {
            parent.fieldKey = text;
        } else if (name === XmlNames.Elem.Value) {
            parent.fieldBinary = this.readProtectedBinary(text, leaf.leafAttrs);
        }
    }

    private commitMetaBinaryLeaf(parent: Frame, name: string, text: string | undefined, leaf: Frame): void {
        if (name === XmlNames.Elem.Value) {
            parent.metaBinaryValue = this.readProtectedBinary(text, leaf.leafAttrs);
        }
    }

    private readProtectedText(text: string | undefined, attrs: Map<string, string> | undefined): ProtectedValue | string | undefined {
        if (attrs && strToBoolean(attrs.get(XmlNames.Attr.Protected))) {
            if (!this.gen) {
                throw new KdbxError(ErrorCodes.InvalidState,
                    'Protected attribute encountered without ProtectSaltGenerator');
            }
            const bytes = text ? base64ToBytes(text) : new Uint8Array(0);
            if (bytes.length === 0) {
                return undefined;
            }
            const value = arrayToBuffer(bytes);
            const salt = this.gen.getSalt(value.byteLength);
            return new ProtectedValue(value, salt);
        }
        if (attrs && strToBoolean(attrs.get(XmlNames.Attr.ProtectedInMemPlainXml))) {
            if (!text) {
                return undefined;
            }
            return ProtectedValue.fromString(text);
        }
        return text ?? undefined;
    }

    private readProtectedBinary(text: string | undefined, attrs: Map<string, string> | undefined): KdbxBinaryOrRef | undefined {
        if (!attrs) {
            return undefined;
        }
        const ref = attrs.get(XmlNames.Attr.Ref);
        if (ref) {
            return { ref } as KdbxBinaryRef;
        }
        if (strToBoolean(attrs.get(XmlNames.Attr.Protected))) {
            if (!this.gen) {
                throw new KdbxError(ErrorCodes.InvalidState,
                    'Protected attribute encountered without ProtectSaltGenerator');
            }
            const bytes = text ? base64ToBytes(text) : new Uint8Array(0);
            if (bytes.length === 0) {
                return undefined;
            }
            const value = arrayToBuffer(bytes);
            const salt = this.gen.getSalt(value.byteLength);
            return new ProtectedValue(value, salt);
        }
        if (strToBoolean(attrs.get(XmlNames.Attr.ProtectedInMemPlainXml))) {
            if (!text) {
                return undefined;
            }
            return ProtectedValue.fromBase64(text);
        }
        if (!text) {
            return undefined;
        }
        let bytes = base64ToBytes(text);
        if (strToBoolean(attrs.get(XmlNames.Attr.Compressed))) {
            bytes = ungzip(bytes);
        }
        return arrayToBuffer(bytes);
    }

    private commitContainer(frame: Frame): void {
        switch (frame.kind) {
            case 'meta':
                this.kdbx.meta = frame.meta!;
                break;
            case 'group': {
                const g = frame.group!;
                if (g.uuid.empty) {
                    g.uuid = KdbxUuid.random();
                }
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'root') {
                    this.kdbx.groups.push(g);
                } else if (parent.kind === 'group') {
                    parent.group!.groups.push(g);
                }
                break;
            }
            case 'entry': {
                const e = frame.entry!;
                if (e.uuid.empty) {
                    e.uuid = KdbxUuid.random();
                    for (const h of e.history) {
                        h.uuid = e.uuid;
                    }
                }
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'group') {
                    parent.group!.entries.push(e);
                } else if (parent.kind === 'history') {
                    const owner = this.stack[this.stack.length - 3];
                    if (owner.kind === 'entry') {
                        owner.entry!.history.push(e);
                    }
                }
                break;
            }
            case 'times': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'group') {
                    parent.group!.times = frame.times!;
                } else if (parent.kind === 'entry') {
                    parent.entry!.times = frame.times!;
                }
                break;
            }
            case 'autoType': {
                break;
            }
            case 'autoTypeItem': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'autoType') {
                    const item = frame.autoTypeItem!;
                    if (item.window && item.keystrokeSequence) {
                        const owner = this.stack[this.stack.length - 3];
                        if (owner.kind === 'entry') {
                            owner.entry!.autoType.items.push({ window: item.window, keystrokeSequence: item.keystrokeSequence });
                        }
                    }
                }
                break;
            }
            case 'stringField': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'entry') {
                    const key = frame.fieldKey;
                    const value = frame.fieldValue;
                    if (key && frame.valuePresent) {
                        parent.entry!.fields.set(key, value || '');
                    }
                }
                break;
            }
            case 'binaryField': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'entry') {
                    const key = frame.fieldKey;
                    const value = frame.fieldBinary;
                    if (key && value) {
                        this.setEntryBinary(parent.entry!, key, value);
                    }
                }
                break;
            }
            case 'metaBinary': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'binaries') {
                    const id = frame.metaBinaryId;
                    const value = frame.metaBinaryValue;
                    if (id && value) {
                        if (KdbxBinaries.isKdbxBinaryRef(value)) {
                            throw new KdbxError(ErrorCodes.FileCorrupt, 'binary ref in meta');
                        }
                        this.kdbx.binaries.addWithId(id, value as KdbxBinary);
                    }
                }
                break;
            }
            case 'customIconItem': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'customIcons') {
                    const metaFrame = this.stack[this.stack.length - 3];
                    if (metaFrame.kind === 'meta' && metaFrame.meta) {
                        const icon = frame.customIcon!;
                        if (icon.uuid && icon.data) {
                            const ci: KdbxCustomIcon = { data: icon.data, name: icon.name, lastModified: icon.lastModified };
                            metaFrame.meta.customIcons.set(icon.uuid.id, ci);
                        }
                    }
                }
                break;
            }
            case 'customData': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'group' && !parent.group!.customData) {
                    parent.group!.customData = new Map<string, { value: string | undefined; lastModified?: Date }>();
                } else if (parent.kind === 'entry' && !parent.entry!.customData) {
                    parent.entry!.customData = new Map<string, { value: string | undefined; lastModified?: Date }>();
                }
                this.flushCustomData(parent, frame);
                break;
            }
            case 'customDataItem': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'customData') {
                    const item = frame.customDataItem!;
                    if (item.key && item.value !== undefined) {
                        const m = this.getCustomDataMap(parent);
                        const entry: { value: string | undefined; lastModified?: Date } = { value: item.value };
                        if (item.lastModified) {
                            entry.lastModified = item.lastModified;
                        }
                        m.set(item.key, entry);
                    }
                }
                break;
            }
            case 'deletedObject': {
                const parent = this.stack[this.stack.length - 2];
                if (parent.kind === 'deletedObjects') {
                    this.kdbx.deletedObjects.push(frame.deletedObject!);
                }
                break;
            }
            default:
                break;
        }
    }

    private getCustomDataMap(parent: Frame): Map<string, { value: string | undefined; lastModified?: Date }> {
        let owner: Frame | undefined = parent;
        if (parent.kind === 'customData') {
            owner = this.stack[this.stack.length - 3];
        }
        if (!owner) {
            return this.kdbx.meta.customData;
        }
        if (owner.kind === 'meta') {
            return owner.meta!.customData;
        }
        if (owner.kind === 'group') {
            const g = owner.group!;
            if (!g.customData) {
                g.customData = new Map<string, { value: string | undefined; lastModified?: Date }>();
            }
            return g.customData;
        }
        if (owner.kind === 'entry') {
            const e = owner.entry!;
            if (!e.customData) {
                e.customData = new Map<string, { value: string | undefined; lastModified?: Date }>();
            }
            return e.customData;
        }
        return this.kdbx.meta.customData;
    }

    private flushCustomData(parent: Frame, frame: Frame): void {
        if (parent.kind === 'group' && frame.kind === 'customData') {
            const g = parent.group!;
            if (g.customData) {
                const fg = g.customData.get('fgColor')?.value;
                const bg = g.customData.get('bgColor')?.value;
                if (fg !== undefined) {
                    g.fgColor = fg;
                }
                if (bg !== undefined) {
                    g.bgColor = bg;
                }
            }
        }
    }

    private setEntryBinary(entry: KdbxEntry, key: string, value: KdbxBinaryOrRef): void {
        if (KdbxBinaries.isKdbxBinaryRef(value)) {
            const found = this.kdbx.binaries.getByRef(value);
            if (found) {
                entry.binaries.set(key, found);
            } else {
                this.pendingEntryBinaries.push({ entry, key, ref: value.ref });
            }
        } else {
            entry.binaries.set(key, value as KdbxBinary);
        }
    }

    private push(frame: Frame): void {
        this.stack.push(frame);
    }

    private pushLeaf(name: string, attrs?: Map<string, string>): void {
        this.stack.push({ kind: 'leaf', leafName: name, leafText: '', leafAttrs: attrs });
    }
}

// ==================== KdbxStreamingXmlLoader（共享流式加载器） ====================

/**
 * 流式 XML 加载协调器：从 ChunkReader 拉取 XML → KdbxModelBuilder 直接构建模型 →
 * computeHashes → resolve pending entry binary refs。
 *
 * 文件加载（KdbxFormat.parseXmlStreaming）与快照加载（KdbxSnapshot.load）共用此入口，
 * 避免逻辑重复。ProtectedValue 边解析边加密（ProtectSaltGenerator 流式 XOR），
 * 无需 DOM 树、无需单独 protectPlainValues 遍历。
 */
export class KdbxStreamingXmlLoader {
    static load(kdbx: Kdbx, ctx: KdbxContext, reader: ChunkReader): Promise<void> {
        const genPromise = KdbxStreamingXmlLoader.tryCreateSaltGenerator(kdbx);
        return genPromise.then((gen) => {
            const builder = new KdbxModelBuilder(kdbx, ctx, gen);
            const parser = new KdbxXmlPullParser(reader, builder);
            return parser.parse().then(() => {
                return kdbx.binaries.computeHashes().then(() => {
                    const pending = builder.pendingEntryBinaries;
                    for (let i = 0; i < pending.length; i++) {
                        const p = pending[i];
                        const found = kdbx.binaries.getByRef({ ref: p.ref });
                        if (found) {
                            p.entry.binaries.set(p.key, found);
                        }
                    }
                });
            });
        });
    }

    /**
     * 创建 ProtectSaltGenerator；header 参数缺失时返回 undefined。
     * 快照格式（ProtectedInMemPlainXml）不需要 generator，header 中不携带 protectedStreamKey；
     * 文件格式（Protected）需要 generator，header 必含 protectedStreamKey。
     */
    private static tryCreateSaltGenerator(kdbx: Kdbx): Promise<ProtectSaltGenerator | undefined> {
        if (!kdbx.header.protectedStreamKey || !kdbx.header.crsAlgorithm) {
            return Promise.resolve(undefined);
        }
        return ProtectSaltGenerator.create(
            kdbx.header.protectedStreamKey,
            kdbx.header.crsAlgorithm
        );
    }
}
