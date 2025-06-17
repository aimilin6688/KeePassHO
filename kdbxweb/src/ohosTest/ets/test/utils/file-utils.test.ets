/**
 * Test for FileUtils class
 */
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { readFileToString } from '../test-support/file-utils';
import { TestResources } from '../test-support/test-resources';


export default function FileUtilsTest() {
  describe('FileUtils', () => {

    it('exists() should return true for existing file', 0, async () => {
      // 读取文件内容
      const content = readFileToString('test-file.txt');
      // 验证结果
      expect(content).not().assertNull();
      expect(content).assertContain('Hello World!');
      console.info(`[Test] File content: ${content}`);
    });

    it('read kdbx demo', 0, async () => {
      const content = TestResources.demoKdbx;
      expect(content).not().assertNull();
    });


  });
}

