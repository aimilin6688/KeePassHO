import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ITemplateStrategy } from '../../../../../../main/ets/services/template/strategies/ITemplateStrategy';
import {
  ITemplate,
  IPresetTemplate,
  IUserTemplate,
  ITemplateField,
  TemplateApplyOptions
} from '../../../../../../main/ets/services/template/TemplateTypes';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';
import { TestUtils } from '../../../importExport/TestUtils';

/**
 * 录制型策略桩：记录调用次数并在 entry 上写入标记字段
 */
class RecordingStrategy implements ITemplateStrategy {
  private templateName: string;
  private iconId: number | string;
  private supported: boolean;
  private templatesList: ITemplate[];
  public applyCallCount: number = 0;
  public supportsCallCount: number = 0;
  public lastOptions: TemplateApplyOptions | undefined = undefined;

  constructor(
    templateName: string,
    iconId: number | string,
    supported: boolean,
    templatesList: ITemplate[]
  ) {
    this.templateName = templateName;
    this.iconId = iconId;
    this.supported = supported;
    this.templatesList = templatesList;
  }

  getTemplates(kdbx?: Kdbx): ITemplate[] {
    return this.templatesList;
  }

  applyTemplate(entry: KdbxEntry, template: ITemplate, options?: TemplateApplyOptions): void {
    this.applyCallCount++;
    this.lastOptions = options;
    entry.fields.set('_recordingApplied', this.templateName);
  }

  supports(template: ITemplate): boolean {
    this.supportsCallCount++;
    return this.supported;
  }

  getTemplateName(template: ITemplate): string {
    return this.templateName;
  }

  getTemplateIconId(template: ITemplate): number | string {
    return this.iconId;
  }
}

/**
 * 计数型策略桩：仅统计 supports 调用，applyTemplate 设置字段
 */
class CountingStrategy implements ITemplateStrategy {
  public supportsCount: number = 0;
  public applyCount: number = 0;

  getTemplates(kdbx?: Kdbx): ITemplate[] {
    return [];
  }

  applyTemplate(entry: KdbxEntry, template: ITemplate, options?: TemplateApplyOptions): void {
    this.applyCount++;
    entry.fields.set('Title', 'CountedTitle');
  }

  supports(template: ITemplate): boolean {
    this.supportsCount++;
    return true;
  }

  getTemplateName(template: ITemplate): string {
    return 'Counted';
  }

  getTemplateIconId(template: ITemplate): number | string {
    return 0;
  }
}

/**
 * ITemplateStrategy 接口契约测试
 * 通过手写桩类验证接口的多态使用与方法的可替换性
 */
export default function ITemplateStrategyTest() {
  describe('ITemplateStrategy', () => {
    let db: Kdbx;
    let rootGroup: KdbxGroup;

    beforeAll(async () => {
      db = await TestUtils.createTestDatabase('ITemplateStrategy Test DB');
      rootGroup = db.getDefaultGroup();
    });

    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    describe('RecordingStrategy', () => {
      it('shouldImplementAllInterfaceMethods', 0, () => {
        const stub: ITemplateStrategy = new RecordingStrategy('A', 1, true, []);
        expect(stub.getTemplates().length).assertEqual(0);
        expect(stub.getTemplateName({} as ITemplate)).assertEqual('A');
        expect(stub.getTemplateIconId({} as ITemplate)).assertEqual(1);
        expect(stub.supports({} as ITemplate)).assertTrue();
      });

      it('shouldReturnConfiguredTemplatesList', 0, () => {
        const preset: IPresetTemplate = {
          id: 'p1', name: 'P1', iconId: 0, standardFields: {}, customFields: []
        };
        const list: ITemplate[] = [preset as ITemplate];
        const stub: ITemplateStrategy = new RecordingStrategy('A', 1, true, list);
        expect(stub.getTemplates().length).assertEqual(1);
        expect(stub.getTemplates() === list).assertTrue();
      });

      it('shouldApplyTemplateAndMutateEntry', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const stub: RecordingStrategy = new RecordingStrategy('Rec', 0, true, []);
        stub.applyTemplate(entry, {} as ITemplate);
        expect(stub.applyCallCount).assertEqual(1);
        expect(entry.fields.get('_recordingApplied')).assertEqual('Rec');
      });

      it('shouldPassOptionsThroughApplyTemplate', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const stub: RecordingStrategy = new RecordingStrategy('Rec', 0, true, []);
        const opts: TemplateApplyOptions = {
          overwriteExisting: true,
          copyTags: false,
          copyIcon: true,
          copyExpiry: false
        };
        stub.applyTemplate(entry, {} as ITemplate, opts);
        expect(stub.lastOptions).not().assertUndefined();
        expect(stub.lastOptions?.overwriteExisting).assertTrue();
        expect(stub.lastOptions?.copyTags).assertFalse();
      });

      it('shouldAllowUndefinedOptions', 0, () => {
        const entry: KdbxEntry = db.createEntry(rootGroup);
        const stub: RecordingStrategy = new RecordingStrategy('Rec', 0, true, []);
        stub.applyTemplate(entry, {} as ITemplate);
        expect(stub.lastOptions).assertUndefined();
      });

      it('shouldTrackSupportsCallCount', 0, () => {
        const stub: RecordingStrategy = new RecordingStrategy('Rec', 0, true, []);
        stub.supports({} as ITemplate);
        stub.supports({} as ITemplate);
        expect(stub.supportsCallCount).assertEqual(2);
      });

      it('shouldReturnConfiguredSupportsFalse', 0, () => {
        const stub: RecordingStrategy = new RecordingStrategy('Rec', 0, false, []);
        expect(stub.supports({} as ITemplate)).assertFalse();
      });
    });

    describe('CountingStrategy', () => {
      it('shouldCountApplyCalls', 0, () => {
        const stub: CountingStrategy = new CountingStrategy();
        const entry: KdbxEntry = db.createEntry(rootGroup);
        stub.applyTemplate(entry, {} as ITemplate);
        stub.applyTemplate(entry, {} as ITemplate);
        expect(stub.applyCount).assertEqual(2);
      });

      it('shouldSetTitleOnApply', 0, () => {
        const stub: CountingStrategy = new CountingStrategy();
        const entry: KdbxEntry = db.createEntry(rootGroup);
        stub.applyTemplate(entry, {} as ITemplate);
        expect(entry.fields.get('Title')).assertEqual('CountedTitle');
      });

      it('shouldAlwaysSupport', 0, () => {
        const stub: CountingStrategy = new CountingStrategy();
        expect(stub.supports({} as ITemplate)).assertTrue();
      });
    });

    describe('polymorphism', () => {
      it('shouldUseStrategiesThroughInterfaceType', 0, () => {
        const strategies: ITemplateStrategy[] = [
          new RecordingStrategy('A', 1, true, []),
          new CountingStrategy()
        ];
        for (let i = 0; i < strategies.length; i++) {
          const entry: KdbxEntry = db.createEntry(rootGroup);
          strategies[i].applyTemplate(entry, {} as ITemplate);
          expect(strategies[i].supports({} as ITemplate)).assertTrue();
        }
      });

      it('shouldPickFirstSupportingStrategy', 0, () => {
        const strategies: ITemplateStrategy[] = [
          new RecordingStrategy('NoSupport', 0, false, []),
          new RecordingStrategy('Support', 1, true, [])
        ];
        let picked: ITemplateStrategy | null = null;
        for (let i = 0; i < strategies.length; i++) {
          if (strategies[i].supports({} as ITemplate)) {
            picked = strategies[i];
            break;
          }
        }
        expect(picked).not().assertNull();
        expect(picked?.getTemplateName({} as ITemplate)).assertEqual('Support');
      });

      it('shouldReturnNullWhenNoStrategySupports', 0, () => {
        const strategies: ITemplateStrategy[] = [
          new RecordingStrategy('A', 0, false, []),
          new RecordingStrategy('B', 0, false, [])
        ];
        let picked: ITemplateStrategy | null = null;
        for (let i = 0; i < strategies.length; i++) {
          if (strategies[i].supports({} as ITemplate)) {
            picked = strategies[i];
            break;
          }
        }
        expect(picked).assertNull();
      });

      it('shouldApplyDifferentStrategiesToDifferentEntries', 0, () => {
        const s1: ITemplateStrategy = new RecordingStrategy('S1', 0, true, []);
        const s2: ITemplateStrategy = new CountingStrategy();
        const e1: KdbxEntry = db.createEntry(rootGroup);
        const e2: KdbxEntry = db.createEntry(rootGroup);
        s1.applyTemplate(e1, {} as ITemplate);
        s2.applyTemplate(e2, {} as ITemplate);
        expect(e1.fields.get('_recordingApplied')).assertEqual('S1');
        expect(e2.fields.get('Title')).assertEqual('CountedTitle');
      });
    });

    describe('interfaceContract', () => {
      it('shouldReturnConsistentNameAcrossCalls', 0, () => {
        const stub: ITemplateStrategy = new RecordingStrategy('Consistent', 0, true, []);
        expect(stub.getTemplateName({} as ITemplate)).assertEqual('Consistent');
        expect(stub.getTemplateName({} as ITemplate)).assertEqual('Consistent');
      });

      it('shouldReturnConsistentIconAcrossCalls', 0, () => {
        const stub: ITemplateStrategy = new RecordingStrategy('A', 77, true, []);
        expect(stub.getTemplateIconId({} as ITemplate)).assertEqual(77);
      });

      it('shouldAllowStringIconId', 0, () => {
        const stub: ITemplateStrategy = new RecordingStrategy('A', 'icon-uuid-string', true, []);
        const icon: number | string = stub.getTemplateIconId({} as ITemplate);
        expect(typeof icon === 'string').assertTrue();
        expect(icon).assertEqual('icon-uuid-string');
      });

      it('shouldAcceptPresetTemplate', 0, () => {
        const preset: IPresetTemplate = {
          id: 'p', name: 'P', iconId: 0, standardFields: {}, customFields: []
        };
        const stub: ITemplateStrategy = new RecordingStrategy('A', 0, true, []);
        expect(stub.supports(preset as ITemplate)).assertTrue();
      });

      it('shouldAcceptUserTemplate', 0, () => {
        const user: IUserTemplate = {
          uuid: new KdbxUuid(),
          name: 'U',
          iconId: 0,
          standardFields: {},
          customFields: [],
          createdAt: new Date(),
          updatedAt: new Date()
        };
        const stub: ITemplateStrategy = new RecordingStrategy('A', 0, true, []);
        expect(stub.supports(user as ITemplate)).assertTrue();
      });
    });
  });
}
