import { describe, expect, it } from '@ohos/hypium';
import { KdbxUuid } from 'kdbxweb';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { IconUtils } from '../../../../main/ets/common/utils/IconUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { Icons } from '../../../../main/ets/services/TypeDefined';

/**
 * 修改主密码闪退回归测试：
 *
 * ChangePassword.handlePasswordChange 先 FileService.close()（database 置空）再
 * navPathStack.clear()，DatabaseView 卸载重渲染时 getIcon 回退读 database.meta，
 * 崩溃：TypeError: Cannot read property meta of undefined（KdbxUtils.getIcon）。
 *
 * 修复后 getIcon / getIconResourcePath 在 database 为 undefined 时须优雅回退、不得抛错。
 */
export default function KdbxUtilsIconGuardTest() {
  describe('KdbxUtilsIconGuardTest', () => {
    it('getIcon does not throw when database is closed', 0, () => {
      const savedParam = FileService.getDbFileParam();
      try {
        FileService.close();
        const defaultIcon = $r('app.media.ic_folder_open');

        // 分组/条目标准图标：database 关闭后应回退到系统图标资源而不是抛错
        const groupIcon = KdbxUtils.getIcon(Icons.FolderOpen, undefined, defaultIcon);
        expect(groupIcon).not().assertNull();
        const entryIcon = KdbxUtils.getIcon(Icons.Key, undefined, defaultIcon);
        expect(entryIcon).not().assertNull();

        // 自定义图标：database 关闭后 meta 不可用，不应抛错，回退默认资源或标准图标
        const customIcon = KdbxUtils.getIcon(undefined, KdbxUuid.random(), defaultIcon);
        expect(customIcon).not().assertNull();
        const customWithIconId = KdbxUtils.getIcon(Icons.Folder, KdbxUuid.random(), defaultIcon);
        expect(customWithIconId).not().assertNull();

        // 图标 id 与自定义图标均为空：直接返回默认资源
        const noneIcon = KdbxUtils.getIcon(undefined, undefined, defaultIcon);
        expect(noneIcon).not().assertNull();

        // 字符串自定义图标 id：IconUtils.getIconResourcePath 同样不得抛错，回退默认目录图标
        const strIcon = IconUtils.getIconResourcePath(KdbxUuid.random().toString());
        expect(strIcon).not().assertNull();
      } finally {
        FileService.setDbFileParam(savedParam);
      }
    });
  });
}
