import ThemeManager from '../common/utils/ThemeManager';
import { Router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  private router: Router = this.getUIContext().getRouter();
  aboutToAppear() {
    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
  }

  aboutToDisappear() {
    // 移除主题变化监听
    ThemeManager.getInstance().removeThemeChangeListenerAll();
  }

  onThemeChanged() {
  }

  @State private updateUI: boolean = false;

  @Builder
  MainButton(icon: Resource, text: string, onClick: () => void){
    Button() {
      Row() {
        Image(icon)
          .width(24)
          .height(24)
          .margin({ right: 8 })
        Text(text)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width('80%')
    .height(56)
    .borderRadius(28)
    .backgroundColor($r('app.color.card_background'))
    .onClick(onClick)
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('KeePassHO')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
        Blank()
        Image($r('app.media.ic_settings'))
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .onClick(() => {
            this.router.pushUrl({ url: 'pages/Settings' })
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_background'))

      // 主要内容区域
      Column() {
        // Logo或应用图标
        Image($r('app.media.startIcon'))
          .width(120)
          .height(120)
          .margin({ top: 60, bottom: 40 })

        // 欢迎文本
        Text('欢迎使用 KeePassHO')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 8 })
          .fontColor($r('app.color.text_primary'))

        Text('安全管理您的密码')
          .fontSize(16)
          .opacity(0.6)
          .margin({ bottom: 60 })
          .fontColor($r('app.color.text_primary'))

        // 主要操作按钮
        this.MainButton($r('app.media.ic_folder_open'), '打开数据库', () => {
          this.router.pushUrl({ url: 'pages/open/OpenDatabase' })
        })

        // 添加间距
        Column() {
          this.MainButton($r('app.media.ic_add_file'), '创建新的数据库', () => {
            this.router.pushUrl({ url: 'pages/open/CreateDatabase' })
          })
        }
        .margin({ top: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .height('100%')
  }
}
