import { AddGroupDialog } from '../components/AddGroupDialog';
import ThemeManager from '../common/utils/ThemeManager';
import { Kdbx, KdbxGroup, KdbxUuid, KdbxTimes, ProtectedValue, KdbxError,KdbxCredentials } from 'kdbxweb';
import { KdbxDbFile } from '../services/TypeDefined';
import { PromptAction, Router } from '@kit.ArkUI';

@Entry
@Component
struct DatabaseShow {
  @State newGroupName: string | undefined = "";
  @State editingGroupIndex: number = -1;
  @State isLoading: boolean = true;
  @State fileName: string = '';
  @State data: Array<KdbxGroup> = [];

  private filePath: string = '';
  private fileContent: ArrayBuffer | null = null;
  private password: string = '';
  private database: Kdbx | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  dialogController: CustomDialogController = new CustomDialogController({
    builder: AddGroupDialog({
      newGroupName: this.newGroupName,
      editingGroupIndex: this.editingGroupIndex,
      onConfirm: (): void => this.handleAddGroup(),
      onCancel: (): void => {
        this.newGroupName = "";
        this.editingGroupIndex = -1;
      }
    }),
    alignment: DialogAlignment.Default,
    autoCancel: true
  })

  aboutToAppear() {
    // 获取从Password页面传递的参数
    const params = this.router.getParams() as KdbxDbFile;
    this.filePath = params?.filePath ?? '';
    this.fileContent = params?.fileContent ?? null;
    this.password = params?.password ?? '';
    this.fileName = params?.fileName ?? '未知数据库';

    if (!this.filePath || !this.fileContent || !this.password) {
      this.promptAction.showToast({
        message: '无效的数据库信息',
        duration: 2000
      });
      this.router.back();
      return;
    }

    // 加载数据库
    this.loadDatabase();

    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
  }

  /**
   * 加载并解密数据库
   */
  async loadDatabase() {
    this.isLoading = true;
    try {
      if (!this.fileContent) {
        throw new Error('文件内容为空');
      }

      // 使用kdbxweb库加载数据库
      const credentials = new KdbxCredentials(ProtectedValue.fromString(this.password));

      this.database = await Kdbx.load(this.fileContent, credentials);
      console.info('数据库加载成功');

      // 获取根分组下的所有子分组
      if (this.database.groups && this.database.groups.length > 0) {
        const rootGroup = this.database.getDefaultGroup();
        if (rootGroup && rootGroup.groups) {
          this.data = rootGroup.groups;
        }
      }

      console.info(`加载了 ${this.data.length} 个分组`);
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

      // 返回到密码输入页面
      setTimeout(() => {
        this.router.back();
      }, 2000);
    } finally {
      this.isLoading = false;
    }
  }

  @Builder
  SwipeActionButtons(index: number) {
    Row() {
      Button("编辑", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.accent'))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          this.editingGroupIndex = index
          this.newGroupName = this.data[index].name;
          this.dialogController.open()
        })

      Button("删除", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.danger'))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          AlertDialog.show({
            title: '确认删除',
            message: '确定要删除这个分组吗？',
            primaryButton: {
              value: '取消',
              action: () => {
              }
            },
            secondaryButton: {
              value: '删除',
              action: () => {
                if (this.database) {
                  // 从数据库中删除分组
                  const group = this.data[index];
                  group.parentGroup?.groups.splice(group.parentGroup.groups.indexOf(group), 1);

                  // 更新UI
                  this.data.splice(index, 1);

                  // 保存数据库
                  this.database.save().then(savedDb => {
                    console.info('数据库已更新');
                    // TODO: 保存数据库到文件
                  }).catch((error:Error) => {
                    console.error(`保存数据库失败: ${error}`);
                  });
                } else {
                  this.data.splice(index, 1);
                }
              }
            }
          })
        })
    }
  }

  handleAddGroup() {
    if (this.newGroupName === undefined || !this.newGroupName.trim()) {
      return;
    }

    if (this.database) {
      if (this.editingGroupIndex >= 0 && this.editingGroupIndex < this.data.length) {
        // 编辑现有分组
        const group = this.data[this.editingGroupIndex];
        group.name = this.newGroupName.trim();
        group.times.lastModTime = new Date();

        // 更新UI
        this.data = [...this.data];

        // 保存数据库
        this.database.save().then(savedDb => {
          console.info('数据库已更新');
          // TODO: 保存数据库到文件
        }).catch((error:Error) => {
          console.error(`保存数据库失败: ${error}`);
        });
      } else {
        // 添加新分组
        const rootGroup = this.database.getDefaultGroup();
        if (rootGroup) {
          const newGroup = this.database.createGroup(rootGroup, this.newGroupName.trim());

          // 更新UI
          this.data.push(newGroup);

          // 保存数据库
          this.database.save().then(savedDb => {
            console.info('数据库已更新');
            // TODO: 保存数据库到文件
          }).catch((error:Error) => {
            console.error(`保存数据库失败: ${error}`);
          });
        }
      }
    } else {
      // 如果数据库对象不可用，仅更新UI
      if (this.editingGroupIndex >= 0 && this.editingGroupIndex < this.data.length) {
        let oldData = this.data[this.editingGroupIndex];
        // 编辑现有分组
        this.data.splice(this.editingGroupIndex, 1, {
          'uuid': oldData.uuid,
          'name': this.newGroupName.trim(),
          'icon': oldData.icon,
          'times': {
            creationTime: oldData.times.creationTime,
            lastModTime: new Date(),
          } as KdbxTimes
        } as KdbxGroup);
      } else {
        // 添加新分组
        this.data.push({
          uuid: KdbxUuid.random(),
          name: this.newGroupName.trim(),
          'times': {
            creationTime: new Date(),
            lastModTime: new Date(),
          } as KdbxTimes
        } as KdbxGroup);
      }
    }

    // 重置状态
    this.newGroupName = "";
    this.editingGroupIndex = -1;
  }

  aboutToDisappear() {
    // 移除主题变化监听
    ThemeManager.getInstance().removeThemeChangeListenerAll();
  }

  onThemeChanged() {
    // 强制组件刷新以应用新主题
    this.data = [...this.data];
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text(this.fileName)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 16 })
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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

        if (this.isLoading) {
          // 加载中状态
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary'))

            Text('正在加载数据库...')
              .fontSize(16)
              .margin({ top: 16 })
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.background_primary'))
        } else {
          // 数据库内容
          List({ space: 8 }) {
            ForEach(this.data, (itemGroup: KdbxGroup, index: number) => {
              ListItem() {
                Row() {
                  Image($r('app.media.ic_folder'))
                    .width(40)
                    .height(40)
                    .margin(10)
                    .fillColor($r('app.color.text_primary'))
                  Text(itemGroup.name)
                    .fontSize(20)
                    .textAlign(TextAlign.Start)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .margin({ right: 10 })
                    .fillColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(60)
                .borderRadius(8)
                .backgroundColor($r('app.color.card_background'))
                .padding({ left: 10, right: 10 })
              }
              .swipeAction({
                end: {
                  builder: this.SwipeActionButtons(index)
                }
              })
            }, (item: KdbxGroup, index: number) => `${index}-${item.name}`)
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_primary'))
          .padding({ left: 12, right: 12, top: 12 })
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')

      Button() {
        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundColor($r('app.color.accent'))
      .position({ right: 12, bottom: 12 })
      .enabled(!this.isLoading)
      .opacity(this.isLoading ? 0.5 : 1)
      .onClick(() => {
        this.editingGroupIndex = -1
        this.newGroupName = ""
        this.dialogController.open()
      })
    }
    .width('100%')
    .height('100%')
  }
}
