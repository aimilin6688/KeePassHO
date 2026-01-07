import HashMap from '@ohos.util.HashMap';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'PasswordGeneratorDialog';

/**
 * 密码生成器对话框组件
 */
@CustomDialog
export struct PasswordGeneratorDialog {
  @State password: string = '';
  @State passwordStrength: number = 0;
  @State passwordLength: number = 16; // 密码生成长度
  @State useUppercase: boolean = true; // 使用大写字母
  @State useLowercase: boolean = true; // 使用小写字母
  @State useNumbers: boolean = true; // 使用数字
  @State useSpecial: boolean = true; // 使用特殊字符
  @State useBrackets: boolean = true; // 使用括号
  @State useMinus: boolean = false; // 使用减号
  @State useUnderscore: boolean = false; // 使用下划线
  @State useSpace: boolean = false; // 使用空格
  @State ensureEachType: boolean = true; // 确保每种选中的字符类型至少包含一个
  @State isAcceptable: boolean = false; // 密码是否可接受
  @State minLength: number = 0;
  @State maxLength: number = 128;
  public onGenerate: (password: string) => void = () => {
  };
  private controller: CustomDialogController;

  // 显示时评估密码强度
  aboutToAppear(): void {
    this.resetPassword();
    this.evaluatePasswordStrength();
  }

  /**
   * 重新对密码进行设置
   */
  resetPassword() {
    if (this.password !== '') {
      this.passwordLength = this.password.length;
      this.evaluatePasswordStrength();
      return;
    }
    this.generatePassword();
  }

  /**
   * 生成随机密码
   */
  private generatePassword() {
    if (this.passwordLength === 0) {
      this.password = '';
      this.evaluatePasswordStrength();
      return;
    }

    // 定义字符集
    const charsets = new HashMap<string, string>();
    try {
      charsets.set("lowercase", 'abcdefghijklmnopqrstuvwxyz');
      charsets.set("uppercase", 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
      charsets.set("numbers", '0123456789');
      charsets.set("special", '!@#$%^&*=+~`|;?><,.');
      charsets.set("brackets", '(){}[]');
      charsets.set("minus", '-');
      charsets.set("underscore", '_');
      charsets.set("space", ' ');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'charsets map set error', e.message);
      CommonUtils.showToast(e.message);
      return;
    }

    // 收集选中的字符集
    const selectedCharsets = new Array<string>();
    let fullCharset = '';

    try {
      if (this.useLowercase) {
        const chats = charsets.get("lowercase");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useUppercase) {
        const chats = charsets.get("uppercase");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useNumbers) {
        const chats = charsets.get("numbers");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useSpecial) {
        const chats = charsets.get("special");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useBrackets) {
        const chats = charsets.get("brackets");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useMinus) {
        const chats = charsets.get("minus");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useUnderscore) {
        const chats = charsets.get("underscore");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
      if (this.useSpace) {
        const chats = charsets.get("space");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }

      // 确保至少有一种字符类型被选中
      if (fullCharset.length === 0) {
        this.useLowercase = true;
        const chats = charsets.get("lowercase");
        selectedCharsets.push(chats);
        fullCharset += chats;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'charsets map get error', e.message);
      CommonUtils.showToast(e.message);
      return;
    }

    let password = '';

    // 如果启用"每种符号至少一种"且密码长度足够
    if (this.ensureEachType && selectedCharsets.length > 0 && this.passwordLength >= selectedCharsets.length) {
      // 首先为每种选中的字符类型添加一个字符
      for (const charset of selectedCharsets) {
        const randomIndex = Math.floor(Math.random() * charset.length);
        password += charset.charAt(randomIndex);
      }

      // 填充剩余长度
      const remainingLength = this.passwordLength - selectedCharsets.length;
      for (let i = 0; i < remainingLength; i++) {
        const randomIndex = Math.floor(Math.random() * fullCharset.length);
        password += fullCharset.charAt(randomIndex);
      }
      // 打乱密码字符顺序，确保随机性
      password = this.shuffleString(password);
    } else {
      // 原有的随机生成逻辑
      for (let i = 0; i < this.passwordLength; i++) {
        const randomIndex = Math.floor(Math.random() * fullCharset.length);
        password += fullCharset.charAt(randomIndex);
      }
    }

    // 更新密码
    this.password = password;
    // 设置接受密码为可用
    this.isAcceptable = true;
    // 评估密码强度
    this.evaluatePasswordStrength();
  }

  /**
   * 打乱字符串顺序
   */
  private shuffleString(str: string): string {
    const arr = str.split('');
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      let GeneratedDestructArray_1 = [arr[j], arr[i]];
      arr[i] = GeneratedDestructArray_1[0];
      arr[j] = GeneratedDestructArray_1[1];
    }
    return arr.join('');
  }

  /**
   * 评估密码强度
   */
  private evaluatePasswordStrength() {
    if (!this.password) {
      this.passwordStrength = 0;
      return;
    }

    let score = 0;

    // 长度评分
    if (this.password.length >= 12) {
      score += 2;
    } else if (this.password.length >= 8) {
      score += 1;
    }

    // 复杂度评分
    const hasLower = /[a-z]/.test(this.password);
    const hasUpper = /[A-Z]/.test(this.password);
    const hasNumber = /[0-9]/.test(this.password);
    const hasSpecial = /[^A-Za-z0-9]/.test(this.password);

    const complexity = (hasLower ? 1 : 0) +
      (hasUpper ? 1 : 0) +
      (hasNumber ? 1 : 0) +
      (hasSpecial ? 1 : 0);

    score += complexity;

    // 设置密码强度
    if (score >= 5) {
      this.passwordStrength = 2; // 强
    } else if (score >= 3) {
      this.passwordStrength = 1; // 中
    } else {
      this.passwordStrength = 0; // 弱
    }
  }

  /**
   * 关闭对话框
   */
  private close() {
    this.controller.close();
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.PasswordGenerator_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
        Blank()
        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.close();
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 密码生成器内容
      Column() {
        TextArea({ text: this.password })
          .lineHeight(24)
          .padding({ top: 12, bottom: 12 })
          .fontSize(16)
          .height(52)
          .fontColor($r('app.color.text_primary'))
          .borderRadius(8)
          .width("100%")
          .onChange((value) => {
            this.password = value;
            this.evaluatePasswordStrength();
          })

        // 密码强度指示器
        Row() {
          Text($r('app.string.PasswordGenerator_strength'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 8 })

          Row() {
            Row()
              .width(24)
              .height(6)
              .backgroundColor(this.passwordStrength >= 0 ? '#FF0000' : '#EEEEEE')
              .borderRadius(3)

            Row()
              .width(24)
              .height(6)
              .backgroundColor(this.passwordStrength >= 1 ? '#FFCC00' : '#EEEEEE')
              .borderRadius(3)
              .margin({ left: 2, right: 2 })

            Row()
              .width(24)
              .height(6)
              .backgroundColor(this.passwordStrength >= 2 ? '#00CC00' : '#EEEEEE')
              .borderRadius(3)
          }

          Text(this.passwordStrength === 0 ? $r('app.string.PasswordGenerator_weak') :
            (this.passwordStrength === 1 ? $r('app.string.PasswordGenerator_medium') : $r('app.string.PasswordGenerator_strong')))
            .fontSize(12)
            .fontColor(this.passwordStrength === 0 ? '#FF0000' : (this.passwordStrength === 1 ? '#FFCC00' : '#00CC00'))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 8, bottom: 8 })

        // 密码长度滑块
        Row() {
          Text($r('app.string.PasswordGenerator_length'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          TextInput({ text: this.passwordLength + "" })
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width(70)
            .onChange((value: string) => {
              if (value !== this.passwordLength + "") {
                this.passwordLength = parseInt(value) || 0;
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 8, bottom: 4 })

        Row() {
          Text(this.minLength + "")
            .fontSize($r('sys.float.Caption_L'))
            .clip(true)
            .textAlign(TextAlign.Center)
            .fontColor($r('app.color.text_primary'))
          Slider({
            value: this.passwordLength,
            min: this.minLength,
            max: this.maxLength,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('90%')
            .onChange((value: number) => {
              this.passwordLength = value;
              this.generatePassword();
            })
          Text(this.maxLength + "")
            .fontSize($r('sys.float.Caption_L'))
            .clip(true)
            .textAlign(TextAlign.Center)
            .fontColor($r('app.color.text_primary'))
        }.width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 4 })

        Row() {
          Button('6', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => {
            this.passwordLength = 6;
            this.generatePassword();
          }).width(40);
          Button('8', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => {
            this.passwordLength = 8;
            this.generatePassword();
          }).width(40);
          Button('16', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => {
            this.passwordLength = 16;
            this.generatePassword();
          }).width(40);
          Button('32', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => {
            this.passwordLength = 32;
            this.generatePassword();
          }).width(40);
          Button('64', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => {
            this.passwordLength = 64;
            this.generatePassword();
          }).width(40);
          Button('128', { controlSize: ControlSize.SMALL, buttonStyle: ButtonStyleMode.NORMAL }).onClick(() => {
            this.passwordLength = 128;
            this.generatePassword();
          }).width(40);
        }.width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 8 })

        // 大写字母选项
        Row() {
          Checkbox({ name: 'uppercase', group: 'passwordOptions' })
            .select(this.useUppercase)
            .onChange((value) => {
              this.useUppercase = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_uppercase'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useUppercase = !this.useUppercase;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 小写字母选项
        Row() {
          Checkbox({ name: 'lowercase', group: 'passwordOptions' })
            .select(this.useLowercase)
            .onChange((value) => {
              this.useLowercase = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_lowercase'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useLowercase = !this.useLowercase;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 数字选项
        Row() {
          Checkbox({ name: 'numbers', group: 'passwordOptions' })
            .select(this.useNumbers)
            .onChange((value) => {
              this.useNumbers = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_numbers'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useNumbers = !this.useNumbers;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 特殊字符选项
        Row() {
          Checkbox({ name: 'special', group: 'passwordOptions' })
            .select(this.useSpecial)
            .onChange((value) => {
              this.useSpecial = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_special'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useSpecial = !this.useSpecial;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 括号选项
        Row() {
          Checkbox({ name: 'brackets', group: 'passwordOptions' })
            .select(this.useBrackets)
            .onChange((value) => {
              this.useBrackets = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_brackets'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useBrackets = !this.useBrackets;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 减号选项
        Row() {
          Checkbox({ name: 'minus', group: 'passwordOptions' })
            .select(this.useMinus)
            .onChange((value) => {
              this.useMinus = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_minus'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useMinus = !this.useMinus;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 下划线选项
        Row() {
          Checkbox({ name: 'underscore', group: 'passwordOptions' })
            .select(this.useUnderscore)
            .onChange((value) => {
              this.useUnderscore = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_underscore'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useUnderscore = !this.useUnderscore;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 空格选项
        Row() {
          Checkbox({ name: 'space', group: 'passwordOptions' })
            .select(this.useSpace)
            .onChange((value) => {
              this.useSpace = value;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
          Text($r('app.string.PasswordGenerator_space'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useSpace = !this.useSpace;
              if (this.ensureEachType) {
                this.generatePassword();
              }
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 每种符号至少一种选项
        Row() {
          Checkbox({ name: 'ensureEachType', group: 'passwordOptions' })
            .select(this.ensureEachType)
            .shape(CheckBoxShape.ROUNDED_SQUARE)
            .onChange((value) => {
              this.ensureEachType = value;
              this.generatePassword(); // 选项改变时重新生成密码
            })
          Text($r('app.string.PasswordGenerator_ensureEachType'))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.ensureEachType = !this.ensureEachType;
              this.generatePassword(); // 选项改变时重新生成密码
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })
      }
      .width('100%')
      .margin({ top: 16, bottom: 16 })

      // 底部按钮
      Row() {
        Button() {
          Row() {
            Image($r('app.media.ic_check'))
              .width(24)
              .height(24)
              .margin({ right: 8 })
              .fillColor($r('app.color.button_text'))
            Text($r('app.string.PasswordGenerator_accept'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.button_text'))
          }
        }
        .width('48%')
        .height(40)
        .fontSize(16)
        .fontColor($r('app.color.button_text'))
        .enabled(this.isAcceptable)
        .backgroundColor($r("app.color.button_bg_blue"))
        .borderRadius(4)

        .onClick(() => {
          this.onGenerate(this.password);
          this.close();
        })

        Button($r('app.string.PasswordGenerator_generate'))
          .width('48%')
          .height(40)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(Color.Gray)
          .borderRadius(4)
          .onClick(() => {
            this.generatePassword();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ bottom: 16 })
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .padding({ left: 24, right: 24, bottom: 16 })
  }
}