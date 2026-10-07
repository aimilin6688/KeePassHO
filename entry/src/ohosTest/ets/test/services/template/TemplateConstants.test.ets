import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TemplateConstants } from '../../../../../main/ets/services/template/TemplateConstants';
import { TemplateCategory, IPresetTemplate } from '../../../../../main/ets/services/template/TemplateTypes';
import { Icons } from '../../../../../main/ets/services/TypeDefined';

/**
 * TemplateConstants 单元测试
 * 覆盖率目标：所有预置模板定义 + 查询方法（getAllTemplates/getTemplateById/getTemplatesByCategory/getAllCategories）
 */
export default function TemplateConstantsTest() {
  describe('TemplateConstants', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    describe('getAllTemplates', () => {
      it('shouldReturnAllPresetTemplates', 0, () => {
        const templates: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        expect(templates.length).assertEqual(25);
      });

      it('shouldReturnNewArrayInstanceEachCall', 0, () => {
        const a: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        const b: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        expect(a === b).assertFalse();
        expect(a.length).assertEqual(b.length);
      });

      it('shouldContainGeneralFirst', 0, () => {
        const templates: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        expect(templates[0].id).assertEqual('general');
      });

      it('shouldContainAccessCardLast', 0, () => {
        const templates: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        expect(templates[templates.length - 1].id).assertEqual('access_card');
      });

      it('shouldHaveUniqueIds', 0, () => {
        const templates: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        const ids: Set<string> = new Set<string>();
        for (let i = 0; i < templates.length; i++) {
          ids.add(templates[i].id);
        }
        expect(ids.size).assertEqual(templates.length);
      });

      it('shouldHaveValidIconIdForEveryTemplate', 0, () => {
        const templates: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        for (let i = 0; i < templates.length; i++) {
          const iconId = templates[i].iconId;
          expect(typeof iconId === 'number').assertTrue();
        }
      });

      it('shouldHaveCustomFieldsArrayForEveryTemplate', 0, () => {
        const templates: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        for (let i = 0; i < templates.length; i++) {
          expect(templates[i].customFields).not().assertNull();
        }
      });
    });

    describe('getTemplateById', () => {
      it('shouldReturnTemplateForKnownId', 0, () => {
        const t: IPresetTemplate | undefined = TemplateConstants.getTemplateById('general');
        expect(t).not().assertUndefined();
        expect(t?.id).assertEqual('general');
      });

      it('shouldReturnGeneralTemplate', 0, () => {
        const t: IPresetTemplate | undefined = TemplateConstants.getTemplateById('website');
        expect(t?.id).assertEqual('website');
        expect(t?.category).assertEqual(TemplateCategory.GENERAL);
      });

      it('shouldReturnBankCardTemplate', 0, () => {
        const t: IPresetTemplate | undefined = TemplateConstants.getTemplateById('bank_card');
        expect(t?.id).assertEqual('bank_card');
        expect(t?.category).assertEqual(TemplateCategory.FINANCE);
      });

      it('shouldReturnSshKeyTemplate', 0, () => {
        const t: IPresetTemplate | undefined = TemplateConstants.getTemplateById('ssh_key');
        expect(t?.id).assertEqual('ssh_key');
        expect(t?.category).assertEqual(TemplateCategory.DEVELOPMENT);
      });

      it('shouldReturnUndefinedForUnknownId', 0, () => {
        const t: IPresetTemplate | undefined = TemplateConstants.getTemplateById('nonexistent_id');
        expect(t).assertUndefined();
      });

      it('shouldReturnUndefinedForEmptyId', 0, () => {
        const t: IPresetTemplate | undefined = TemplateConstants.getTemplateById('');
        expect(t).assertUndefined();
      });

      it('shouldLookupEveryTemplateById', 0, () => {
        const all: IPresetTemplate[] = TemplateConstants.getAllTemplates();
        for (let i = 0; i < all.length; i++) {
          const found = TemplateConstants.getTemplateById(all[i].id);
          expect(found).not().assertUndefined();
          expect(found?.id).assertEqual(all[i].id);
        }
      });
    });

    describe('getTemplatesByCategory', () => {
      it('shouldReturnGeneralCategoryTemplates', 0, () => {
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(TemplateCategory.GENERAL);
        expect(list.length).assertEqual(3);
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('general')).assertTrue();
        expect(ids.includes('website')).assertTrue();
        expect(ids.includes('email')).assertTrue();
      });

      it('shouldReturnIdentityCategoryTemplates', 0, () => {
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(TemplateCategory.IDENTITY);
        expect(list.length).assertEqual(4);
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('id_card')).assertTrue();
        expect(ids.includes('passport')).assertTrue();
        expect(ids.includes('driver_license')).assertTrue();
        expect(ids.includes('social_security')).assertTrue();
      });

      it('shouldReturnFinanceCategoryTemplates', 0, () => {
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(TemplateCategory.FINANCE);
        expect(list.length).assertEqual(4);
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('bank_card')).assertTrue();
        expect(ids.includes('credit_card')).assertTrue();
        expect(ids.includes('membership')).assertTrue();
        expect(ids.includes('crypto_wallet')).assertTrue();
      });

      it('shouldReturnNetworkCategoryTemplates', 0, () => {
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(TemplateCategory.NETWORK);
        expect(list.length).assertEqual(5);
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('wifi')).assertTrue();
        expect(ids.includes('vpn')).assertTrue();
        expect(ids.includes('ftp')).assertTrue();
        expect(ids.includes('remote_desktop')).assertTrue();
        expect(ids.includes('router')).assertTrue();
      });

      it('shouldReturnDevelopmentCategoryTemplates', 0, () => {
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(TemplateCategory.DEVELOPMENT);
        expect(list.length).assertEqual(7);
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('ssh_key')).assertTrue();
        expect(ids.includes('database')).assertTrue();
        expect(ids.includes('server')).assertTrue();
        expect(ids.includes('api_key')).assertTrue();
        expect(ids.includes('software_license')).assertTrue();
        expect(ids.includes('digital_signature')).assertTrue();
        expect(ids.includes('git_repository')).assertTrue();
      });

      it('shouldReturnOtherCategoryTemplates', 0, () => {
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(TemplateCategory.OTHER);
        expect(list.length).assertEqual(2);
        const ids: string[] = list.map((t: IPresetTemplate) => t.id);
        expect(ids.includes('security_question')).assertTrue();
        expect(ids.includes('access_card')).assertTrue();
      });

      it('shouldReturnEmptyForUnknownCategoryValue', 0, () => {
        const fake: TemplateCategory = 'unknown' as TemplateCategory;
        const list: IPresetTemplate[] = TemplateConstants.getTemplatesByCategory(fake);
        expect(list.length).assertEqual(0);
      });

      it('shouldSumToTotalAcrossCategories', 0, () => {
        const cats: TemplateCategory[] = TemplateConstants.getAllCategories();
        let sum: number = 0;
        for (let i = 0; i < cats.length; i++) {
          sum += TemplateConstants.getTemplatesByCategory(cats[i]).length;
        }
        expect(sum).assertEqual(TemplateConstants.getAllTemplates().length);
      });
    });

    describe('getAllCategories', () => {
      it('shouldReturnSixCategories', 0, () => {
        const cats: TemplateCategory[] = TemplateConstants.getAllCategories();
        expect(cats.length).assertEqual(6);
      });

      it('shouldReturnCategoriesInOrder', 0, () => {
        const cats: TemplateCategory[] = TemplateConstants.getAllCategories();
        expect(cats[0]).assertEqual(TemplateCategory.GENERAL);
        expect(cats[1]).assertEqual(TemplateCategory.IDENTITY);
        expect(cats[2]).assertEqual(TemplateCategory.FINANCE);
        expect(cats[3]).assertEqual(TemplateCategory.NETWORK);
        expect(cats[4]).assertEqual(TemplateCategory.DEVELOPMENT);
        expect(cats[5]).assertEqual(TemplateCategory.OTHER);
      });
    });

    describe('specificTemplateProperties', () => {
      it('shouldHaveGeneralWithKeyIconAndEmptyCustomFields', 0, () => {
        expect(TemplateConstants.GENERAL.iconId).assertEqual(Icons.Key);
        expect(TemplateConstants.GENERAL.customFields.length).assertEqual(0);
        expect(TemplateConstants.GENERAL.standardFields.username).assertEqual('');
        expect(TemplateConstants.GENERAL.standardFields.password).assertEqual('');
      });

      it('shouldHaveEmailWithFourCustomFields', 0, () => {
        expect(TemplateConstants.EMAIL.customFields.length).assertEqual(4);
        expect(TemplateConstants.EMAIL.customFields[0].key).assertEqual('smtp_server');
        expect(TemplateConstants.EMAIL.customFields[1].key).assertEqual('smtp_port');
        expect(TemplateConstants.EMAIL.customFields[1].value).assertEqual('465');
        expect(TemplateConstants.EMAIL.customFields[2].key).assertEqual('imap_server');
        expect(TemplateConstants.EMAIL.customFields[3].key).assertEqual('imap_port');
        expect(TemplateConstants.EMAIL.customFields[3].value).assertEqual('993');
      });

      it('shouldHaveBankCardWithProtectedBankCardNumber', 0, () => {
        const fields = TemplateConstants.BANK_CARD.customFields;
        expect(fields.length).assertEqual(8);
        const bankCardField = fields[0];
        expect(bankCardField.key).assertEqual('bank_card_number');
        expect(bankCardField.isProtected).assertTrue();
      });

      it('shouldHaveBankCardWithProtectedCvv', 0, () => {
        const fields = TemplateConstants.BANK_CARD.customFields;
        const cvvField = fields.find((f) => f.key === 'cvv');
        expect(cvvField).not().assertUndefined();
        expect(cvvField?.isProtected).assertTrue();
      });

      it('shouldHaveIdCardWithProtectedIdNumber', 0, () => {
        const fields = TemplateConstants.ID_CARD.customFields;
        expect(fields.length).assertEqual(6);
        expect(fields[0].key).assertEqual('id_number');
        expect(fields[0].isProtected).assertTrue();
      });

      it('shouldHaveSshKeyWithPrivateKeyProtected', 0, () => {
        const fields = TemplateConstants.SSH_KEY.customFields;
        const privateKeyField = fields.find((f) => f.key === 'private_key');
        expect(privateKeyField?.isProtected).assertTrue();
      });

      it('shouldHaveWifiWithRequiredSsid', 0, () => {
        const fields = TemplateConstants.WIFI.customFields;
        const ssidField = fields.find((f) => f.key === 'ssid');
        expect(ssidField?.required).assertTrue();
      });

      it('shouldHaveFtpWithDefaultPort21', 0, () => {
        const fields = TemplateConstants.FTP.customFields;
        const portField = fields.find((f) => f.key === 'port');
        expect(portField?.value).assertEqual('21');
      });

      it('shouldHaveDatabaseWithDefaultPort3306', 0, () => {
        const fields = TemplateConstants.DATABASE.customFields;
        const portField = fields.find((f) => f.key === 'port');
        expect(portField?.value).assertEqual('3306');
      });

      it('shouldHaveRemoteDesktopWithDefaultPort3389', 0, () => {
        const fields = TemplateConstants.REMOTE_DESKTOP.customFields;
        const portField = fields.find((f) => f.key === 'port');
        expect(portField?.value).assertEqual('3389');
      });

      it('shouldHaveRouterWithDefaultAdminAddress', 0, () => {
        const fields = TemplateConstants.ROUTER.customFields;
        const adminField = fields.find((f) => f.key === 'admin_address');
        expect(adminField?.value).assertEqual('192.168.1.1');
      });

      it('shouldHaveSshKeyWithDefaultPort22', 0, () => {
        const fields = TemplateConstants.SSH_KEY.customFields;
        const portField = fields.find((f) => f.key === 'port');
        expect(portField?.value).assertEqual('22');
      });

      it('shouldHaveSoftwareLicenseWithRequiredLicenseKey', 0, () => {
        const fields = TemplateConstants.SOFTWARE_LICENSE.customFields;
        const licenseKeyField = fields.find((f) => f.key === 'license_key');
        expect(licenseKeyField?.isProtected).assertTrue();
        expect(licenseKeyField?.required).assertTrue();
      });

      it('shouldHaveCreditCardWithElevenCustomFields', 0, () => {
        expect(TemplateConstants.CREDIT_CARD.customFields.length).assertEqual(11);
      });

      it('shouldHaveDriverLicenseWithTenCustomFields', 0, () => {
        expect(TemplateConstants.DRIVER_LICENSE.customFields.length).assertEqual(10);
      });

      it('shouldHaveGitRepositoryWithDefaultBranchMain', 0, () => {
        const fields = TemplateConstants.GIT_REPOSITORY.customFields;
        const branchField = fields.find((f) => f.key === 'default_branch');
        expect(branchField?.value).assertEqual('main');
      });

      it('shouldHaveMembershipWithNotesStandardField', 0, () => {
        expect(TemplateConstants.MEMBERSHIP.standardFields.notes).assertEqual('');
      });

      it('shouldHaveCryptoWalletWithMnemonicProtected', 0, () => {
        const fields = TemplateConstants.CRYPTO_WALLET.customFields;
        const mnemonicField = fields.find((f) => f.key === 'mnemonic');
        expect(mnemonicField?.isProtected).assertTrue();
      });

      it('shouldHaveSecurityQuestionWithThreeAnswerPairs', 0, () => {
        const fields = TemplateConstants.SECURITY_QUESTION.customFields;
        expect(fields.length).assertEqual(6);
        const answers = fields.filter((f) => f.key.startsWith('answer'));
        expect(answers.length).assertEqual(3);
      });
    });
  });
}
