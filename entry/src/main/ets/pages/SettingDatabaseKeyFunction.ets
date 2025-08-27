import { Router } from '@kit.ArkUI';
import { ByteUtils, Consts, HeaderConst, Int64, VarDictionary } from 'kdbxweb';
import KdbxUtils from '../common/utils/KdbxUtils';
import { FileService } from '../services/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SettingDatabaseKeyFunction';

@Entry
@Component
struct SettingDatabaseKeyFunction {
  @State isDatabaseValid: boolean = false;
  @State algoType: string = Consts.KdfId.Argon2d;
  @State iteration: number = HeaderConst.DefaultKdfIterations;
  @State memory: number = HeaderConst.DefaultKdfMemory;
  @State parallelism: number = HeaderConst.DefaultKdfParallelism;
  @State rounds: number = Consts.Defaults.KeyEncryptionRounds;
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
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

  onPageShow(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
    if (this.isDatabaseValid) {
      const kdfParameters = dbFileParam.database.header.kdfParameters;
      if (!kdfParameters) {
        return;
      }
      this.algoType = ByteUtils.bytesToBase64(kdfParameters.get('$UUID') as ArrayBuffer);
      if (this.isArgon2()) {
        this.iteration = kdfParameters.get('I') as number;
        this.memory = kdfParameters.get('M') as number / 1024 / 1024;
        this.parallelism = kdfParameters.get('P') as number;
      } else if (this.isAes()) {
        this.rounds = kdfParameters.get('R') as number;
      }
    }
  }

  // 重新加密算法
  private saveAlgoParams() {
    if (!this.isDatabaseValid) {
      this.promptAction.showToast({ message: $r("app.string.database_not_opened") });
      return;
    }
    if (!((this.isArgon2() && this.iteration && this.memory && this.parallelism) || (this.isAes() && this.rounds))) {
      hilog.debug(DOMAIN, TAG, `algoType: ${this.algoType}, iteration: ${this.iteration}, memory: ${this.memory}, parallelism: ${this.parallelism}`);
      return;
    }
    try {
      const dbFileParam = FileService.getDbFileParam();
      const kdfParameters = dbFileParam.database.header.kdfParameters;
      if (kdfParameters && this.isArgon2()) {
        kdfParameters.set('$UUID', VarDictionary.ValueType.Bytes, ByteUtils.base64ToBytes(this.algoType));
        kdfParameters.set('I', VarDictionary.ValueType.UInt64, Int64.from(this.iteration));
        kdfParameters.set('M', VarDictionary.ValueType.UInt64, Int64.from(this.memory * 1024 * 1024));
        kdfParameters.set('P', VarDictionary.ValueType.UInt32, this.parallelism);
      } else if (kdfParameters && this.algoType === Consts.KdfId.Aes) {
        kdfParameters.set('$UUID', VarDictionary.ValueType.Bytes, ByteUtils.base64ToBytes(this.algoType));
        kdfParameters.set('R', VarDictionary.ValueType.UInt64, Int64.from(this.rounds));
      }
      hilog.debug(DOMAIN, TAG, "saveAlgoParams:%{public}s", JSON.stringify(kdfParameters));
      // 保存数据库
      KdbxUtils.saveDatabase({
        onSuccess: () => {
          this.promptAction.showToast({ message: $r("app.string.save_success"), duration: 2000 });
        },
        onError: (errorMessage: string) => {
          this.promptAction.showToast({ message: $r('app.string.save_failed_message', errorMessage), duration: 2000 });
        }
      });
    } catch (error) {
      const errorMsg = KdbxUtils.kdbxErrorMessage(error);
      hilog.error(DOMAIN, TAG, 'Failed to save database algo: %{public}s', errorMsg);
      this.promptAction.showToast({ message: errorMsg, duration: 2000 });
    }
  }

  private isArgon2(): boolean {
    return this.algoType === Consts.KdfId.Argon2d || this.algoType === Consts.KdfId.Argon2id;
  }

  private isAes(): boolean {
    return this.algoType === Consts.KdfId.Aes;
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
        Text($r("app.string.Settings_database_encryption_key"))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))


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
                      this.saveAlgoParams();
                    })
                    .margin({ right: 0 })
                }.width('70%')
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding({
                left: 16,
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
                      .fontSize(16)
                      .type(InputType.Number)
                      .fontColor($r('app.color.text_primary'))
                      .width(70)
                      .onChange((value: string) => {
                        if (this.iteration != Number(value)) {
                          this.iteration = Number(value);
                          this.saveAlgoParams();
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
                    TextInput({ text: this.memory + "" })
                      .type(InputType.Number)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .width(70)
                      .onChange((value: string) => {
                        if (this.memory != Number(value)) {
                          this.memory = Number(value);
                          this.saveAlgoParams();
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

              // 并行处理
              ListItem() {
                Row() {
                  Text($r("app.string.Settings_database_encryption_parallel"))
                    .fontSize(16)
                    .flexGrow(1)
                  Blank()
                  Column() {
                    TextInput({ text: this.parallelism + "" })
                      .type(InputType.Number)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .width(70)
                      .onChange((value: string) => {
                        if (this.parallelism != Number(value)) {
                          this.parallelism = Number(value);
                          this.saveAlgoParams();
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
                      .fontSize(16)
                      .type(InputType.Number)
                      .fontColor($r('app.color.text_primary'))
                      .width(100)
                      .onChange((value: string) => {
                        if (this.rounds != Number(value)) {
                          this.rounds = Number(value);
                          this.saveAlgoParams();
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
      .height('auto')
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 12 })
      .padding({ left: 12, right: 12 })
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