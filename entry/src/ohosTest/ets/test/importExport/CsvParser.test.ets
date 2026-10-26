import { describe, expect, it } from '@ohos/hypium';
import { CsvParser } from '../../../../main/ets/services/importExport/csvimport/CsvParser';

/**
 * CsvParser 单元测试
 * 语义对齐 KeePassXC CsvParser（RFC4180 风格状态机）：
 * 1. 引号字段内的分隔符 / 换行原样保留
 * 2. 引号内 "" 转义为一个引号
 * 3. CRLF / CR 统一归一为 LF
 * 4. 全空行跳过；短行补齐到最大列数
 * 5. 未闭合引号置 isGood = false 但保留已解析内容
 */
export default function CsvParserTest() {
  describe('CsvParser', () => {
    describe('basicParsing', () => {
      it('shouldParseSimpleCommaSeparatedLine', 0, () => {
        const result = new CsvParser().parse('a,b,c');
        expect(result.rows.length).assertEqual(1);
        expect(result.rows[0].length).assertEqual(3);
        expect(result.rows[0][0]).assertEqual('a');
        expect(result.rows[0][1]).assertEqual('b');
        expect(result.rows[0][2]).assertEqual('c');
        expect(result.columnCount).assertEqual(3);
        expect(result.isGood).assertTrue();
      });

      it('shouldParseMultipleLines', 0, () => {
        const result = new CsvParser().parse('a,b\nc,d');
        expect(result.rows.length).assertEqual(2);
        expect(result.rows[0][0]).assertEqual('a');
        expect(result.rows[1][0]).assertEqual('c');
        expect(result.rows[1][1]).assertEqual('d');
      });

      it('shouldPreserveTrailingEmptyField', 0, () => {
        const result = new CsvParser().parse('a,');
        expect(result.rows.length).assertEqual(1);
        expect(result.rows[0].length).assertEqual(2);
        expect(result.rows[0][0]).assertEqual('a');
        expect(result.rows[0][1]).assertEqual('');
      });

      it('shouldPreserveEmptyFieldInTheMiddle', 0, () => {
        const result = new CsvParser().parse('a,,c');
        expect(result.rows[0].length).assertEqual(3);
        expect(result.rows[0][1]).assertEqual('');
      });

      it('shouldSupportCustomSeparator', 0, () => {
        const result = new CsvParser(';').parse('a;b;c');
        expect(result.rows[0].length).assertEqual(3);
        expect(result.rows[0][1]).assertEqual('b');
      });
    });

    describe('quotedFields', () => {
      it('shouldHandleQuotedFieldWithComma', 0, () => {
        const result = new CsvParser().parse('"hello, world",b');
        expect(result.rows[0][0]).assertEqual('hello, world');
        expect(result.rows[0][1]).assertEqual('b');
      });

      it('shouldUnescapeDoubledQuotes', 0, () => {
        const result = new CsvParser().parse('"say ""hi""",x');
        expect(result.rows[0][0]).assertEqual('say "hi"');
        expect(result.rows[0][1]).assertEqual('x');
      });

      it('shouldHandleNewlineInsideQuotes', 0, () => {
        const result = new CsvParser().parse('a,"line1\nline2",b');
        expect(result.rows.length).assertEqual(1);
        expect(result.rows[0].length).assertEqual(3);
        expect(result.rows[0][1]).assertEqual('line1\nline2');
        expect(result.rows[0][2]).assertEqual('b');
      });

      it('shouldHandleSeparatorInsideQuotes', 0, () => {
        const result = new CsvParser().parse('"a,b,c",d');
        expect(result.rows[0].length).assertEqual(2);
        expect(result.rows[0][0]).assertEqual('a,b,c');
        expect(result.rows[0][1]).assertEqual('d');
      });

      it('shouldFlagUnclosedQuoteButKeepContent', 0, () => {
        const result = new CsvParser().parse('"unclosed,x');
        expect(result.isGood).assertFalse();
        expect(result.rows.length).assertEqual(1);
        expect(result.rows[0][0]).assertEqual('unclosed,x');
      });

      it('shouldKeepGoodFlagForWellFormedQuotes', 0, () => {
        const result = new CsvParser().parse('"a","b"\n"c","d"');
        expect(result.isGood).assertTrue();
        expect(result.rows.length).assertEqual(2);
      });
    });

    describe('newlineNormalization', () => {
      it('shouldNormalizeCrlfLineEndings', 0, () => {
        const result = new CsvParser().parse('a,b\r\nc,d');
        expect(result.rows.length).assertEqual(2);
        expect(result.rows[0][1]).assertEqual('b');
        expect(result.rows[1][0]).assertEqual('c');
        expect(result.rows[1][1]).assertEqual('d');
      });

      it('shouldNormalizeCrLineEndings', 0, () => {
        const result = new CsvParser().parse('a,b\rc,d');
        expect(result.rows.length).assertEqual(2);
        expect(result.rows[0][1]).assertEqual('b');
        expect(result.rows[1][0]).assertEqual('c');
      });

      it('shouldStripUtf8Bom', 0, () => {
        const result = new CsvParser().parse('\uFEFFa,b');
        expect(result.rows.length).assertEqual(1);
        expect(result.rows[0][0]).assertEqual('a');
        expect(result.rows[0][1]).assertEqual('b');
      });
    });

    describe('rowSkippingAndPadding', () => {
      it('shouldSkipEmptyLines', 0, () => {
        const result = new CsvParser().parse('a,b\n\n\nc,d');
        expect(result.rows.length).assertEqual(2);
      });

      it('shouldSkipRowsWhereAllFieldsEmpty', 0, () => {
        const result = new CsvParser().parse(',,\n,,\na,b');
        expect(result.rows.length).assertEqual(1);
        expect(result.rows[0][0]).assertEqual('a');
        expect(result.columnCount).assertEqual(2);
      });

      it('shouldKeepRowWithAtLeastOneNonEmptyField', 0, () => {
        const result = new CsvParser().parse('a,,c');
        expect(result.rows.length).assertEqual(1);
      });

      it('shouldPadShortRowsToMaxColumnCount', 0, () => {
        const result = new CsvParser().parse('a,b,c\nd,e');
        expect(result.columnCount).assertEqual(3);
        expect(result.rows[1].length).assertEqual(3);
        expect(result.rows[1][2]).assertEqual('');
      });
    });

    describe('emptyInput', () => {
      it('shouldReturnNoRowsForEmptyText', 0, () => {
        const result = new CsvParser().parse('');
        expect(result.rows.length).assertEqual(0);
        expect(result.columnCount).assertEqual(0);
        expect(result.isGood).assertTrue();
      });

      it('shouldReturnNoRowsForWhitespaceOnlyText', 0, () => {
        const result = new CsvParser().parse('\n\n');
        expect(result.rows.length).assertEqual(0);
      });
    });

    describe('parseFirstRecord', () => {
      it('shouldReturnFirstNonEmptyRow', 0, () => {
        const row = CsvParser.parseFirstRecord('\na,b\nc,d');
        expect(row).not().assertUndefined();
        expect(row?.length).assertEqual(2);
        expect(row?.[0]).assertEqual('a');
        expect(row?.[1]).assertEqual('b');
      });

      it('shouldReturnUndefinedForEmptyText', 0, () => {
        const row = CsvParser.parseFirstRecord('');
        expect(row).assertUndefined();
      });

      it('shouldParseQuotedFirstRecord', 0, () => {
        const row = CsvParser.parseFirstRecord('"x,y",z\n1,2');
        expect(row?.length).assertEqual(2);
        expect(row?.[0]).assertEqual('x,y');
      });
    });
  });
}
