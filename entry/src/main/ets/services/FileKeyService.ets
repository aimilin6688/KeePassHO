import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import DateUtils from '../common/utils/DateUtils';
import { StorageType } from './kdbx/interfaces';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { ByteUtils, KdbxCredentials } from 'kdbxweb';
import { CommonUtils } from '../common/utils/CommonUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CreateDatabase';

export class FileKeyService {
  /**
   * 创建密钥文件
   * @param context
   */
  public static createKeyFile(context: common.UIAbilityContext) {
    let fileName = `key_${DateUtils.getCurrentDate()}.key`;
    // 使用文件选择器让用户选择保存位置
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = ['.key'];

    // 显示文件保存对话框
    documentPicker.save(options).then(async (result) => {
      if (result && result.length > 0) {
        let filePath = result[0];
        KdbxCredentials.createRandomKeyFile().then(keyContent => {
          new KdbxFileManager(StorageType.LOCAL).writeFile(filePath, ByteUtils.bytesToBuffer(keyContent)).then(async () => {
            CommonUtils.showToast($r("app.string.save_success"));
          }).catch((error: Error) => {
            hilog.error(DOMAIN, TAG, `Failed to create new key file: ${error.message}`, error.stack);
            CommonUtils.showToast($r('app.string.save_failed_message', error.message));
          });
        })
      }else{
        hilog.error(DOMAIN, TAG, `Failed not select file save path`);
        CommonUtils.showToast($r('app.string.not_select_file_path'));
      }
    })
  }
}