import { PromptAction, Router } from '@kit.ArkUI';
import { FileStorageFactory, StorageType } from '../../services/kdbx/interfaces';
import { WebDAVStorageConfig } from '../../services/kdbx/interfaces/StorageConfig';
import { promptAction } from '@kit.ArkUI';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import ResourceManager from '../../common/utils/ResourceManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'WebDAV';


@Entry
@Component
struct WebDAV {
  @State url: string = 'https://dav.jianguoyun.com/dav/MyFiles/';
  @State username: string = 'aimilin@yeah.net';
  @State password: string = 'a77u9ewde6gyaqxg';
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;

  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.WEBDAV);
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private storageFactory: FileStorageFactory = FileStorageFactory.getInstance();

  // 测试WebDAV连接
  private async testConnection() {
    if (!this.url || !this.username || !this.password) {
      this.connectionStatus = ResourceManager.getString($r('app.string.fill_all_info'));
      this.isErrorStatus = true;
      return;
    }

    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      let storage = this.storageFactory.getStorage(StorageType.WEBDAV);
      storage.init(new WebDAVStorageConfig(this.url, this.username, this.password));
      // 简单测试连接
      storage.exists(this.url).then(result => {
        if(result){
          this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
          this.isErrorStatus = false;
        }else{
          this.connectionStatus = ResourceManager.getString($r('app.string.connection_failed'));
          this.isErrorStatus = true;
          hilog.error(DOMAIN, TAG, 'webdav connection error: %{public}s', this.connectionStatus);
        }
      }).catch((error:Error) =>{
        this.connectionStatus = error.message;
        this.isErrorStatus = true;
        hilog.error(DOMAIN, TAG, 'webdav connection error: %{public}s', this.connectionStatus);
      });
    } finally {
      this.isConnecting = false;
    }
  }

  // 保存WebDAV配置
  private saveConfig() {
    if (!this.url || !this.username || !this.password) {
      this.promptAction.showToast({ message:  ResourceManager.getString($r('app.string.fill_all_info'))});
      return;
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })

        Text('WebDAV')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

      // 主要内容区域
      Scroll() {
        Column() {
          // 服务器URL输入
          Text($r('app.string.url'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({text:this.url, placeholder: $r('app.string.url_placeholder') })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .fontColor($r('app.color.text_primary'))
            .onChange((value: string) => {
              this.url = value;
            })

          // 用户名输入
          Text($r('app.string.username'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({ text:this.username, placeholder: $r('app.string.username_placeholder') })
            .height(40)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.username = value;
            })

          // 密码输入
          Text($r('app.string.password'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)
          TextInput({text:this.password,  placeholder: $r('app.string.password_placeholder') })
            .height(40)
            .type(InputType.Password)
            .margin({ top: 20 })
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r("app.color.card_bg"))
            .onChange((value: string) => {
              this.password = value;
            })

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .margin({ top: 10 })
              .fontColor(this.isErrorStatus ? $r('app.color.danger') : $r('app.color.success'))
          }

          Row(){
            // 测试连接按钮
            Button($r('app.string.test_connection'))
              .height(40)
              .margin({ top: 20 })
              .backgroundColor(Color.Gray)
              .fontColor(Color.White)
              .enabled(!this.isConnecting)
              .onClick(() => {
                this.testConnection();
              })
            Blank()
            // 确定按钮
            Button($r('app.string.confirm_button_text'))
              .height(40)
              .margin({ top: 20 })
              .backgroundColor($r('app.color.button_bg_blue'))
              .fontColor($r('app.color.button_text_blue'))
              .onClick(() => {
                this.saveConfig();
              })
          }
          .width("100%")
        }
        .width('90%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
