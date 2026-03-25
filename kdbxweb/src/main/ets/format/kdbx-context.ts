import * as XmlUtils from '../utils/xml-utils';
import { Kdbx } from './kdbx';
import { KdbxEntry } from './kdbx-entry';
import { KdbxGroup } from './kdbx-group';
import { Node } from '@xmldom/xmldom';

export class KdbxContext {
    readonly kdbx: Kdbx;
    exportXml: boolean;
    private _entryMap?: Map<string, KdbxEntry>;

    constructor(opts: { kdbx: Kdbx; exportXml?: boolean }) {
        this.kdbx = opts.kdbx;
        this.exportXml = !!opts.exportXml;
    }

    setXmlDate(node: Node, dt: Date | undefined): void {
        const isBinary = this.kdbx.versionMajor >= 4 && !this.exportXml;
        XmlUtils.setDate(node, dt, isBinary);
    }

    /**
     * 构建Entry索引映射
     * 用于快速查找Entry，支持字段引用解析
     */
    buildEntryMap(): void {
        this._entryMap = new Map<string, KdbxEntry>();
        this.kdbx.groups.forEach(group => {
            this.buildEntryMapForGroup(group);
        });
    }

    /**
     * 为指定Group构建Entry索引
     * @param group 要遍历的Group
     */
    private buildEntryMapForGroup(group: KdbxGroup): void {
        // 索引当前Group的所有Entry
        group.entries.forEach(entry => {
            this._entryMap!.set(entry.uuid.id, entry);
        });

        // 递归索引子Group
        group.groups.forEach(subgroup => {
            this.buildEntryMapForGroup(subgroup);
        });
    }

    /**
     * 通过UUID查找Entry
     * @param uuid Entry UUID
     * @returns Entry对象或undefined
     */
    getEntryByUuid(uuid: import('./kdbx-uuid').KdbxUuid): KdbxEntry | undefined {
        if (!this._entryMap) {
            this.buildEntryMap();
        }
        return this._entryMap?.get(uuid.id);
    }

    /**
     * 通过UUID字符串查找Entry
     * @param uuidStr UUID字符串（Base64编码）
     * @returns Entry对象或undefined
     */
    getEntryByUuidString(uuidStr: string): KdbxEntry | undefined {
        if (!this._entryMap) {
            this.buildEntryMap();
        }
        return this._entryMap?.get(uuidStr);
    }

    /**
     * 清除Entry索引映射
     * 在修改数据库结构后调用
     */
    clearEntryMap(): void {
        this._entryMap = undefined;
    }
}
