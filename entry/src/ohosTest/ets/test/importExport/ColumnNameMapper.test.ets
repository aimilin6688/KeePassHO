import { describe, expect, it } from '@ohos/hypium';
import { CsvTargetField } from '../../../../main/ets/services/importExport/csvimport/CsvImportModels';
import { ColumnNameMapper } from '../../../../main/ets/services/importExport/csvimport/ColumnNameMapper';

/**
 * ColumnNameMapper 单元测试
 * 同义词字典移植自 KeePass 2.x ImportUtil.MapNameToStandardField（精确匹配 + 模糊子串匹配），
 * 并扩展 KeePassXC CSV 导入目标字段（Group/TOTP/Tags/Icon/Last Modified/Created）。
 */
export default function ColumnNameMapperTest() {
  describe('ColumnNameMapper', () => {
    describe('standardFields', () => {
      it('shouldMapStandardKeePassHeaders', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('Title')).assertEqual(CsvTargetField.TITLE);
        expect(ColumnNameMapper.mapToTargetField('UserName')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('Password')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('URL')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('Notes')).assertEqual(CsvTargetField.NOTES);
        expect(ColumnNameMapper.mapToTargetField('Group')).assertEqual(CsvTargetField.GROUP);
      });

      it('shouldBeCaseAndWhitespaceInsensitive', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('  username ')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('NOTES')).assertEqual(CsvTargetField.NOTES);
        expect(ColumnNameMapper.mapToTargetField('password')).assertEqual(CsvTargetField.PASSWORD);
      });
    });

    describe('keePassSynonyms', () => {
      it('shouldMapTitleSynonyms', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('account')).assertEqual(CsvTargetField.TITLE);
        expect(ColumnNameMapper.mapToTargetField('item name')).assertEqual(CsvTargetField.TITLE);
        expect(ColumnNameMapper.mapToTargetField('subject')).assertEqual(CsvTargetField.TITLE);
        expect(ColumnNameMapper.mapToTargetField('service')).assertEqual(CsvTargetField.TITLE);
        expect(ColumnNameMapper.mapToTargetField('type')).assertEqual(CsvTargetField.TITLE);
        expect(ColumnNameMapper.mapToTargetField('itemname')).assertEqual(CsvTargetField.TITLE);
      });

      it('shouldMapUsernameSynonyms', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('user')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('name')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('login')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('email')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('e-mail')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('userid')).assertEqual(CsvTargetField.USERNAME);
      });

      it('shouldMapPasswordSynonyms', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('pass')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('pwd')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('pw')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('pin')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('passphrase')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('secret')).assertEqual(CsvTargetField.PASSWORD);
      });

      it('shouldMapUrlSynonyms', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('hyperlink')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('link')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('website')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('site')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('hostname')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('server')).assertEqual(CsvTargetField.URL);
      });

      it('shouldMapNotesSynonyms', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('comment')).assertEqual(CsvTargetField.NOTES);
        expect(ColumnNameMapper.mapToTargetField('memo')).assertEqual(CsvTargetField.NOTES);
        expect(ColumnNameMapper.mapToTargetField('description')).assertEqual(CsvTargetField.NOTES);
      });

      it('shouldMapGroupSynonyms', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('grouping')).assertEqual(CsvTargetField.GROUP);
        expect(ColumnNameMapper.mapToTargetField('folder')).assertEqual(CsvTargetField.GROUP);
        expect(ColumnNameMapper.mapToTargetField('category')).assertEqual(CsvTargetField.GROUP);
      });
    });

    describe('extendedTargets', () => {
      it('shouldMapTotpHeaders', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('TOTP')).assertEqual(CsvTargetField.TOTP);
        expect(ColumnNameMapper.mapToTargetField('otp')).assertEqual(CsvTargetField.TOTP);
        expect(ColumnNameMapper.mapToTargetField('TOTP Seed')).assertEqual(CsvTargetField.TOTP);
      });

      it('shouldMapTagsIconAndTimeHeaders', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('Tags')).assertEqual(CsvTargetField.TAGS);
        expect(ColumnNameMapper.mapToTargetField('tag')).assertEqual(CsvTargetField.TAGS);
        expect(ColumnNameMapper.mapToTargetField('Icon')).assertEqual(CsvTargetField.ICON);
        expect(ColumnNameMapper.mapToTargetField('Last Modified')).assertEqual(CsvTargetField.LAST_MODIFIED);
        expect(ColumnNameMapper.mapToTargetField('lastmodified')).assertEqual(CsvTargetField.LAST_MODIFIED);
        expect(ColumnNameMapper.mapToTargetField('Created')).assertEqual(CsvTargetField.CREATED);
        expect(ColumnNameMapper.mapToTargetField('creation time')).assertEqual(CsvTargetField.CREATED);
      });
    });

    describe('fuzzyMatching', () => {
      it('shouldMapBySubstringWhenNoExactMatch', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('vb_login_password')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('form_pw')).assertEqual(CsvTargetField.PASSWORD);
        expect(ColumnNameMapper.mapToTargetField('login_username')).assertEqual(CsvTargetField.USERNAME);
        expect(ColumnNameMapper.mapToTargetField('my_url_field')).assertEqual(CsvTargetField.URL);
        expect(ColumnNameMapper.mapToTargetField('entry_comment_extra')).assertEqual(CsvTargetField.NOTES);
      });

      it('shouldPreferExactMatchOverFuzzy', 0, () => {
        // itemname 精确命中 Title 同义词表，不会被 'name' 子串误判为 UserName
        expect(ColumnNameMapper.mapToTargetField('itemname')).assertEqual(CsvTargetField.TITLE);
        // pin 精确命中 Password 同义词表
        expect(ColumnNameMapper.mapToTargetField('pin')).assertEqual(CsvTargetField.PASSWORD);
      });

      it('shouldCheckPasswordSubstrBeforeUsername', 0, () => {
        // KeePass 2.x 顺序：先 password 子串，再 username 子串
        expect(ColumnNameMapper.mapToTargetField('user password')).assertEqual(CsvTargetField.PASSWORD);
      });
    });

    describe('unknownHeaders', () => {
      it('shouldReturnUndefinedForUnknownHeader', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('xyzzy')).assertUndefined();
      });

      it('shouldReturnUndefinedForEmptyHeader', 0, () => {
        expect(ColumnNameMapper.mapToTargetField('')).assertUndefined();
        expect(ColumnNameMapper.mapToTargetField('   ')).assertUndefined();
      });
    });
  });
}
