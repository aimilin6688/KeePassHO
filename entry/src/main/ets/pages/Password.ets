import { PromptAction, Router } from '@kit.ArkUI';
import { Kdbx, KdbxCredentials, KdbxError, ProtectedValue } from 'kdbxweb';
import { FileParam , DbFileParam} from '../services/TypeDefined';

@Entry
@Component
struct Password {
  @State password: string = '';
  @State isLoading: boolean = false;
  @State fileName: string = '';

  private filePath: string = '';
  private fileContent: ArrayBuffer | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear() {
    // 获取从LocalFile页面传递的参数
    const params = this.router.getParams() as FileParam;
    this.filePath = params?.filePath ?? '';
    this.fileContent = params?.fileContent ?? null;
    this.fileName = params?.fileName ?? '未知文件';

    if (!this.filePath || !this.fileContent) {
      this.promptAction.showToast({
        message: '无效的数据文件',
        duration: 2000
      });
      this.router.back();
    }
  }

  /**
   * 加载并解密数据库
   */
  private async loadDatabase(): Promise<Kdbx | null> {
    try {
      if (!this.fileContent) {
        throw new Error('文件内容为空');
      }

      // 使用kdbxweb库加载数据库
      const credentials = new KdbxCredentials(ProtectedValue.fromString(this.password));
      const database = await Kdbx.load(this.fileContent, credentials);
      console.info('数据库加载成功');
      return database;
    } catch (error) {
      console.error(`加载数据库失败: ${error}`);
      let errorMessage = '加载数据库失败';

      if (error instanceof KdbxError) {
        if (error.code === 'InvalidKey') {
          errorMessage = '密码错误，请重试';
        } else {
          errorMessage = `数据库错误: ${error.message}`;
        }
      }

      this.promptAction.showToast({
        message: errorMessage,
        duration: 2000
      });
      return null;
    }
  }

  /**
   * 验证密码并打开数据库
   */
  async verifyAndOpenDatabase() {
    if (!this.password) {
      this.promptAction.showToast({
        message: '请输入密码',
        duration: 2000
      });
      return;
    }

    this.isLoading = true;
    try {
      // 加载并验证数据库
      const database = await this.loadDatabase();
      if (!database) {
        return;
      }

      // 验证成功，跳转到数据库展示页面
      this.router.pushUrl({
        url: 'pages/DatabaseShow',
        params: {
          filePath: this.filePath,
          password: this.password,
          fileName: this.fileName,
          database: database
        } as DbFileParam
      });
    } catch (error) {
      this.promptAction.showToast({
        message: `数据库加载失败: ${error}`,
        duration: 2000
      });
    } finally {
      this.isLoading = false;
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
            this.router.back();
          })

        Text('解锁数据库')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_background'))

      // 主要内容区域
      Column() {
        // 文件名显示
        Text(this.fileName)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 24, bottom: 32 })
          .textAlign(TextAlign.Center)
          .width('80%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 密码输入框
        Row() {
          TextInput({ placeholder: '请输入密码' })
            .type(InputType.Password)
            .placeholderColor($r('app.color.text_secondary'))
            .placeholderFont({ size: 16 })
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .width('100%')
            .height(48)
            .onChange((value) => {
              this.password = value;
            })
        }
        .width('90%')
        .padding({ left: 16, right: 16 })
        .border({
          width: { bottom: 1 },
          color: $r('app.color.divider')
        })

        // 确认按钮
        Button(this.isLoading ? '验证中...' : '确认')
          .width('90%')
          .height(48)
          .margin({ top: 32 })
          .enabled(!this.isLoading)
          .onClick(() => {
            this.verifyAndOpenDatabase();
          })

        if (this.isLoading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .margin({ top: 16 })
            .color($r('app.color.text_primary'))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background_primary'))
      .padding({ top: 16 })
    }
    .width('100%')
    .height('100%')
  }
}
