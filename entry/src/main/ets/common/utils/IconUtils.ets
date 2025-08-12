import { FileService } from '../../services/FileService';
import { IconResource, Icons } from '../../services/TypeDefined';
import KdbxUtils from './KdbxUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'IconUtils';

/**
 * 图标工具类
 */
export default class IconUtils {
  /**
   * 获取图标资源路径
   * @param iconId 图标ID
   * @returns 图标资源路径
   */
  static getIconResourcePath(iconId: number | string): ResourceStr {
    // 默认图标
    let iconResource: Resource = $r('app.media.C48_Folder');

    if (typeof iconId === 'string') {
      let icon = KdbxUtils.getCustomIcon(iconId, FileService.getInstance().getDbFileParam().database.meta);
      if (icon) {
        return icon;
      }
    }
    // 根据图标ID获取对应的图标资源
    switch (iconId) {
      case Icons.Key:
        iconResource = $r('app.media.C00_Key');
        break;
      case Icons.World:
        iconResource = $r('app.media.C01_World');
        break;
      case Icons.Warning:
        iconResource = $r('app.media.C02_Warning');
        break;
      case Icons.NetworkServer:
        iconResource = $r('app.media.C03_NetworkServer');
        break;
      case Icons.MarkedDirectory:
        iconResource = $r('app.media.C04_MarkedDirectory');
        break;
      case Icons.UserCommunication:
        iconResource = $r('app.media.C05_UserCommunication');
        break;
      case Icons.Parts:
        iconResource = $r('app.media.C06_Parts');
        break;
      case Icons.Notepad:
        iconResource = $r('app.media.C07_Notepad');
        break;
      case Icons.WorldSocket:
        iconResource = $r('app.media.C08_WorldSocket');
        break;
      case Icons.Identity:
        iconResource = $r('app.media.C09_Identity');
        break;
      case Icons.PaperReady:
        iconResource = $r('app.media.C10_PaperReady');
        break;
      case Icons.Digicam:
        iconResource = $r('app.media.C11_Digicam');
        break;
      case Icons.IRCommunication:
        iconResource = $r('app.media.C12_IRCommunication');
        break;
      case Icons.MultiKeys:
        iconResource = $r('app.media.C13_MultiKeys');
        break;
      case Icons.Energy:
        iconResource = $r('app.media.C14_Energy');
        break;
      case Icons.Scanner:
        iconResource = $r('app.media.C15_Scanner');
        break;
      case Icons.WorldStar:
        iconResource = $r('app.media.C16_WorldStar');
        break;
      case Icons.CDRom:
        iconResource = $r('app.media.C17_CDRom');
        break;
      case Icons.Monitor:
        iconResource = $r('app.media.C18_Monitor');
        break;
      case Icons.EMail:
        iconResource = $r('app.media.C19_EMail');
        break;
      case Icons.Configuration:
        iconResource = $r('app.media.C20_Configuration');
        break;
      case Icons.ClipboardReady:
        iconResource = $r('app.media.C21_ClipboardReady');
        break;
      case Icons.PaperNew:
        iconResource = $r('app.media.C22_PaperNew');
        break;
      case Icons.Screen:
        iconResource = $r('app.media.C23_Screen');
        break;
      case Icons.EnergyCareful:
        iconResource = $r('app.media.C24_EnergyCareful');
        break;
      case Icons.EMailBox:
        iconResource = $r('app.media.C25_EMailBox');
        break;
      case Icons.Disk:
        iconResource = $r('app.media.C26_Disk');
        break;
      case Icons.Drive:
        iconResource = $r('app.media.C27_Drive');
        break;
      case Icons.PaperQ:
        iconResource = $r('app.media.C28_PaperQ');
        break;
      case Icons.TerminalEncrypted:
        iconResource = $r('app.media.C29_TerminalEncrypted');
        break;
      case Icons.Console:
        iconResource = $r('app.media.C30_Console');
        break;
      case Icons.Printer:
        iconResource = $r('app.media.C31_Printer');
        break;
      case Icons.ProgramIcons:
        iconResource = $r('app.media.C32_ProgramIcons');
        break;
      case Icons.Run:
        iconResource = $r('app.media.C33_Run');
        break;
      case Icons.Settings:
        iconResource = $r('app.media.C34_Settings');
        break;
      case Icons.WorldComputer:
        iconResource = $r('app.media.C35_WorldComputer');
        break;
      case Icons.Archive:
        iconResource = $r('app.media.C36_Archive');
        break;
      case Icons.Homebanking:
        iconResource = $r('app.media.C37_Homebanking');
        break;
      case Icons.DriveWindows:
        iconResource = $r('app.media.C38_DriveWindows');
        break;
      case Icons.Clock:
        iconResource = $r('app.media.C39_Clock');
        break;
      case Icons.EMailSearch:
        iconResource = $r('app.media.C40_EMailSearch');
        break;
      case Icons.PaperFlag:
        iconResource = $r('app.media.C41_PaperFlag');
        break;
      case Icons.Memory:
        iconResource = $r('app.media.C42_Memory');
        break;
      case Icons.TrashBin:
        iconResource = $r('app.media.C43_TrashBin');
        break;
      case Icons.Note:
        iconResource = $r('app.media.C44_Note');
        break;
      case Icons.Expired:
        iconResource = $r('app.media.C45_Expired');
        break;
      case Icons.Info:
        iconResource = $r('app.media.C46_Info');
        break;
      case Icons.Package:
        iconResource = $r('app.media.C47_Package');
        break;
      case Icons.Folder:
        iconResource = $r('app.media.C48_Folder');
        break;
      case Icons.FolderOpen:
        iconResource = $r('app.media.C49_FolderOpen');
        break;
      case Icons.FolderPackage:
        iconResource = $r('app.media.C50_FolderPackage');
        break;
      case Icons.LockOpen:
        iconResource = $r('app.media.C51_LockOpen');
        break;
      case Icons.PaperLocked:
        iconResource = $r('app.media.C52_PaperLocked');
        break;
      case Icons.Checked:
        iconResource = $r('app.media.C53_Checked');
        break;
      case Icons.Pen:
        iconResource = $r('app.media.C54_Pen');
        break;
      case Icons.Thumbnail:
        iconResource = $r('app.media.C55_Thumbnail');
        break;
      case Icons.Book:
        iconResource = $r('app.media.C56_Book');
        break;
      case Icons.List:
        iconResource = $r('app.media.C57_List');
        break;
      case Icons.UserKey:
        iconResource = $r('app.media.C58_UserKey');
        break;
      case Icons.Tool:
        iconResource = $r('app.media.C59_Tool');
        break;
      case Icons.Home:
        iconResource = $r('app.media.C60_Home');
        break;
      case Icons.Star:
        iconResource = $r('app.media.C61_Star');
        break;
      case Icons.Tux:
        iconResource = $r('app.media.C62_Tux');
        break;
      case Icons.Feather:
        iconResource = $r('app.media.C63_Feather');
        break;
      case Icons.Apple:
        iconResource = $r('app.media.C64_Apple');
        break;
      case Icons.Wiki:
        iconResource = $r('app.media.C65_Wiki');
        break;
      case Icons.Money:
        iconResource = $r('app.media.C66_Money');
        break;
      case Icons.Certificate:
        iconResource = $r('app.media.C67_Certificate');
        break;
      case Icons.BlackBerry:
        iconResource = $r('app.media.C68_BlackBerry');
        break;
      default:
        iconResource = $r('app.media.C48_Folder');
        break;
    }

    return iconResource;
  }

  /**
   * 获取所有图标
   * @returns 所有图标的ID和资源路径
   */
  public static getAllIcons(onlyCustom?: boolean): Array<IconResource> {
    onlyCustom = onlyCustom || false;
    const icons: Array<IconResource> = [];
    // 遍历所有系统图标ID
    if(!onlyCustom){
      for (let i = 0; i <= 68; i++) {
        icons.push({
          id: i,
          resource: IconUtils.getIconResourcePath(i)
        });
      }
    }
    // 用户自定义图标返回
    try {
      let kdbx = FileService.getInstance().getDbFileParam().database;
      for (let key of kdbx.meta.customIcons) {
        let icon = KdbxUtils.toImgBase64Url(key[1].data)
        if (icon != null) {
          icons.push({
            id: key[0].toString(),
            resource: icon
          });
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getAllIcons error: %{public}s', e.message);
    }

    return icons;
  }
}
