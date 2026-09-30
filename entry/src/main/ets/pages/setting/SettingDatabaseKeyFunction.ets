import { ByteUtils, Consts, HeaderConst, Int64, VarDictionary } from 'kdbxweb';
import { CommonUtils, KdbxUtils, NavigationManager } from '../../common/utils';
import { FileService } from '../../services/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SaveDatabaseCallback } from '../../workers/callback/SaveDatabaseCallback';
import { SuccessMessage } from '../../workers/WorkerParam';

const DOMAIN = 0x0000;
const TAG = 'SettingDatabaseKeyFunction';

// SettingDatabaseKeyFunction页面的Builder函数
@Builder
export function SettingDatabaseKeyFunctionBuilder(name: string, param: Object): void {
  SettingDatabaseKeyFunctionPage()
}

/**
 * 密钥派生函数页面（与修改主密码一致的页面打开方式）
 */
@Component
struct SettingDatabaseKeyFunctionPage {
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStack()!;

  build() {
    NavDestination() {
      SettingDatabaseKeyFunctionContent({
        onClose: (): void => {
          this.navPathStack.pop();
        }
      })
    }
    .title($r('app.string.Settings_database_encryption_key'))
    .backgroundColor($r("app.color.bg_primary"))
  }
}

@Component
export struct SettingDatabaseKeyFunctionContent {
  // 底部悬浮按钮栏总高度（自身高度 60 + 底部留白 10）
  private readonly BOTTOM_BAR_HEIGHT: number = 70;
  @State isDatabaseValid: boolean = false;
  @State algoType: string = Consts.KdfId.Argon2d;
  @State iteration: number = HeaderConst.DefaultKdfIterations;
  @State memory: string = (HeaderConst.DefaultKdfMemory / 1024 / 1024) + "";
  @State parallelism: number = HeaderConst.DefaultKdfParallelism;
  @State rounds: number = Consts.Defaults.KeyEncryptionRounds;
  onClose?: () => void;
  private keyFunctionOptions: Array<KeyFunctionOption> = [
    {
      value: "Argon2d",
      type: Consts.KdfId.Argon2d,
    },
    {
      value: "Argon2id",
      type: Consts.KdfId.Argon2id,
    },
    {
      value: "AES-KDF",
      type: Consts.KdfId.Aes,
    },
  ];
  private promptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
    if (this.isDatabaseValid) {
      const header = dbFileParam.database.header;
      const kdfParameters = header.kdfParameters;
      if (!kdfParameters) {
        // KDBX3.x：无 kdfParameters，KDF 固定为 AES-KDF，
        // 转换轮数取头部 keyEncryptionRounds（FR-011）
        if (header.versionMajor === 3) {
          this.algoType = Consts.KdfId.Aes;
          this.rounds = header.keyEncryptionRounds ?? Consts.Defaults.KeyEncryptionRounds;
        }
        return;
      }
      this.algoType = ByteUtils.bytesToBase64(kdfParameters.get('$UUID') as ArrayBuffer);
      if (this.isArgon2()) {
        this.iteration = kdfParameters.get('I') as number;
        this.memory = (kdfParameters.get('M') as number / 1024 / 1024) + "";
        this.parallelism = kdfParameters.get('P') as number;
      } else if (this.isAes()) {
        this.rounds = kdfParameters.get('R') as number;
      }
    }
  }

  // 重新加密算法
  private saveAlgoParams() {
    if (!this.isDatabaseValid) {
      CommonUtils.showToast({ message: $r("app.string.database_not_opened") });
      return;
    }
    if (!((this.isArgon2() && this.iteration && this.memory && this.parallelism) || (this.isAes() && this.rounds))) {
      hilog.debug(DOMAIN, TAG, `algoType: ${this.algoType}, iteration: ${this.iteration}, memory: ${this.memory}, parallelism: ${this.parallelism}`);
      CommonUtils.showToast({ message: $r("app.string.Settings_database_not_value") });
      return;
    }
    try {
      const dbFileParam = FileService.getDbFileParam();
      const header = dbFileParam.database.header;
      const kdfParameters = header.kdfParameters;
      const isVersion3: boolean = header.versionMajor === 3;
      if (isVersion3 && this.isArgon2()) {
        // KDBX3.x 选择 Argon2：Argon2 仅 KDBX4 支持，需用户显式确认升级（FR-012）；
        // 取消则不应用任何变更
        this.confirmUpgradeToKdbx4();
        return;
      } else if (isVersion3 && this.isAes()) {
        // KDBX3.x + AES-KDF：直接写头部转换轮数，保持 v3 格式（不创建 kdfParameters）
        header.keyEncryptionRounds = this.rounds;
      } else if (kdfParameters && this.isArgon2()) {
        // 设置内存最大值为512M
        this.memory = this.resetMemory(this.memory, (HeaderConst.DefaultKdfMemory / 1024 / 1024) + "");
        kdfParameters.set('$UUID', VarDictionary.ValueType.Bytes, ByteUtils.base64ToBytes(this.algoType));
        kdfParameters.set('I', VarDictionary.ValueType.UInt64, Int64.from(this.iteration));
        kdfParameters.set('M', VarDictionary.ValueType.UInt64, Int64.from(Number(this.memory) * 1024 * 1024));
        kdfParameters.set('P', VarDictionary.ValueType.UInt32, this.parallelism);
      } else if (kdfParameters && this.algoType === Consts.KdfId.Aes) {
        kdfParameters.set('$UUID', VarDictionary.ValueType.Bytes, ByteUtils.base64ToBytes(this.algoType));
        kdfParameters.set('R', VarDictionary.ValueType.UInt64, Int64.from(this.rounds));
      }
      hilog.debug(DOMAIN, TAG, "saveAlgoParams:%{public}s", JSON.stringify(kdfParameters));
      // 保存数据库
      KdbxUtils.saveDatabase();
    } catch (error) {
      const errorMsg = KdbxUtils.kdbxErrorMessage(error);
      hilog.error(DOMAIN, TAG, 'Failed to save database algo: %{public}s', errorMsg);
      CommonUtils.showToast({ message: errorMsg, duration: 2000 });
    }
  }

  private isArgon2(): boolean {
    return this.algoType === Consts.KdfId.Argon2d || this.algoType === Consts.KdfId.Argon2id;
  }

  private isAes(): boolean {
    return this.algoType === Consts.KdfId.Aes;
  }

  /**
   * KDBX3.x 选择 Argon2d/Argon2id 时弹出"升级为 KDBX4"确认弹窗（FR-012）：
   * 确认 → setVersion(4)+setKdf(所选) 并应用用户输入的参数后保存；
   * 取消 → 不应用任何变更，文件保持 KDBX3 格式
   */
  private confirmUpgradeToKdbx4() {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.kdbx_upgrade_title'),
      message: $r('app.string.kdbx_upgrade_message'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.kdbx_upgrade_cancel'),
        action: () => {
          // 取消：不应用任何变更
        }
      },
      secondaryButton: {
        value: $r('app.string.kdbx_upgrade_confirm'),
        action: () => {
          this.upgradeToKdbx4();
        }
      }
    });
  }

  /**
   * 升级数据库为 KDBX4（设置所选 Argon2 KDF 与用户输入参数）并保存
   */
  private upgradeToKdbx4() {
    try {
      const dbFileParam = FileService.getDbFileParam();
      const header = dbFileParam.database.header;
      // 先升级版本（v3 无 kdfParameters 时由 setVersion 创建默认参数），再设置所选 KDF
      header.setVersion(4);
      header.setKdf(this.algoType);
      // 应用用户输入的 Argon2 参数
      const kdfParameters = header.kdfParameters;
      if (kdfParameters) {
        this.memory = this.resetMemory(this.memory, (HeaderConst.DefaultKdfMemory / 1024 / 1024) + "");
        kdfParameters.set('$UUID', VarDictionary.ValueType.Bytes, ByteUtils.base64ToBytes(this.algoType));
        kdfParameters.set('I', VarDictionary.ValueType.UInt64, Int64.from(this.iteration));
        kdfParameters.set('M', VarDictionary.ValueType.UInt64, Int64.from(Number(this.memory) * 1024 * 1024));
        kdfParameters.set('P', VarDictionary.ValueType.UInt32, this.parallelism);
      }
      hilog.debug(DOMAIN, TAG, 'Upgrade database to KDBX4, kdf: %{public}s', this.algoType);
      // 保存成功后提示升级完成
      const callback: SaveDatabaseCallback = {
        onSuccess: (message: SuccessMessage): void => {
          CommonUtils.showToast({ message: $r('app.string.kdbx_upgrade_success') });
        }
      };
      KdbxUtils.saveDatabase(callback);
    } catch (error) {
      const errorMsg = KdbxUtils.kdbxErrorMessage(error);
      hilog.error(DOMAIN, TAG, 'Failed to upgrade database to KDBX4: %{public}s', errorMsg);
      CommonUtils.showToast({ message: errorMsg, duration: 2000 });
    }
  }

  /**
   * 重置内存大小
   * @param memory 内存大小
   * @returns 结果
   */
  private resetMemory(memory: string, defaultValue: string = ""): string {
    if (memory && !isNaN(Number(memory))) {
      return Math.max(Math.min(Number(memory), 512), 1) + "";
    }
    return memory ? memory : defaultValue;
  }

  build() {
    Column() {
      List() {
        if (this.isDatabaseValid) {
          // 主要内容区域
          ListItemGroup() {
            // 密钥派生函数
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_encryption_key"))
                  .fontSize(16)
                  .flexGrow(1)
                Blank()
                Column() {
                  Select(this.keyFunctionOptions)
                    .value(this.keyFunctionOptions[this.keyFunctionOptions.findIndex((item) => item.type === this.algoType)].value)
                    .font({ size: 16 })
                    .selectedOptionFont({ size: 16 })
                    .optionFont({ size: 16 })
                    .backgroundColor($r("app.color.card_bg"))
                    .onSelect(async (index: number) => {
                      this.algoType = this.keyFunctionOptions[index].type;
                    })
                    .margin({ right: 0 })
                }.width('70%')
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 9,
                bottom: 9
              })
            }

            if (this.isArgon2()) {
              // 加密次数
              ListItem() {
                Row() {
                  Text($r("app.string.Settings_database_encryption_iterations"))
                    .fontSize(16)
                    .flexGrow(1)
                  Blank()
                  Column() {
                    TextInput({ text: this.iteration + "" })
                    .id('input_iterations')
                      .fontSize(16)
                      .type(InputType.Number)
                      .fontColor($r('app.color.text_primary'))
                      .width(70)
                      .onChange((value: string) => {
                        if (this.iteration != Number(value)) {
                          this.iteration = Number(value);
                        }
                      })
                  }
                  .padding({ right: 16 })
                  .width('70%')
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({
                  left: 16,
                  top: 9,
                  bottom: 9
                })
              }

              // 内存MB
              ListItem() {
                Row() {
                  Text($r("app.string.Settings_database_encryption_memory"))
                    .fontSize(16)
                    .flexGrow(1)
                  Blank()
                  Column() {
                    TextInput({ text: this.memory })
                    .id('input_memory')
                      .type(InputType.Number)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .width(70)
                      .onChange((value: string) => {
                        this.memory = this.resetMemory(value);
                      })
                  }
                  .padding({ right: 16 })
                  .width('70%')
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({
                  left: 16,
                  top: 9,
                  bottom: 9
                })
              }

              // 并行处理
              ListItem() {
                Row() {
                  Text($r("app.string.Settings_database_encryption_parallel"))
                    .fontSize(16)
                    .flexGrow(1)
                  Blank()
                  Column() {
                    TextInput({ text: this.parallelism + "" })
                    .id('input_parallelism')
                      .type(InputType.Number)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .width(70)
                      .onChange((value: string) => {
                        if (this.parallelism != Number(value)) {
                          this.parallelism = Number(value);
                        }
                      })
                  }
                  .padding({ right: 16 })
                  .width('70%')
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({
                  left: 16,
                  top: 9,
                  bottom: 9
                })
              }
            }

            if (this.isAes()) {
              // 加密次数
              ListItem() {
                Row() {
                  Text($r("app.string.Settings_database_encryption_rounds"))
                    .fontSize(16)
                    .flexGrow(1)
                  Blank()
                  Column() {
                    TextInput({ text: this.rounds + "" })
                    .id('input_rounds')
                      .fontSize(16)
                      .type(InputType.Number)
                      .fontColor($r('app.color.text_primary'))
                      .width(100)
                      .onChange((value: string) => {
                        if (this.rounds != Number(value)) {
                          this.rounds = Number(value);
                        }
                      })
                  }
                  .padding({ right: 16 })
                  .width('70%')
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({
                  left: 16,
                  top: 9,
                  bottom: 9
                })
              }
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })
        } else {
          ListItem() {
            Text($r('app.string.database_not_opened'))
              .fontSize(16)
              .margin({ top: 20, bottom: 12 })
              .textAlign(TextAlign.Center)
              .width('100%')
              .fontColor($r('app.color.text_secondary'))
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      // 底部按钮为悬浮层，留出等高的内容偏移，保证最后一项能滚动到按钮上方
      .contentEndOffset(this.BOTTOM_BAR_HEIGHT)

      // 操作按钮（样式遵循 docs/ui-bottom-button-spec.md）
      Row() {
        // 取消
        Button($r('app.string.cancel_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor(Color.Gray)
          .id('btn_cancel')
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
          })

        Blank()

        // 保存
        Button($r('app.string.save_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor($r('app.color.button_bg_blue'))
          .id('btn_save')
          .onClick(() => {
            this.saveAlgoParams();
          })
      }
      .width('100%')
      .height(60)
      .backgroundColor(Color.Transparent)
      .padding({
        top: 8,
        bottom: 8,
        left: 16,
        right: 16
      })
      // 脱离文档流悬浮，上移量 = BOTTOM_BAR_HEIGHT
      .position({ x: 0, y: '100%' })
      .translate({ y: -this.BOTTOM_BAR_HEIGHT })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

interface KeyFunctionOption {
  value: ResourceStr;
  type: string;
}