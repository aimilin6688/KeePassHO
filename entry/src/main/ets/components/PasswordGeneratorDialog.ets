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

  public onGenerate: (password: string) => void = () => {};
  private controller: CustomDialogController;

  // 显示时评估密码强度
  onPageShow(): void {
    this.evaluatePasswordStrength();
  }

  /**
   * 生成随机密码
   */
  private generatePassword() {
    let charset = '';
    if (this.useLowercase) charset += 'abcdefghijklmnopqrstuvwxyz';
    if (this.useUppercase) charset += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (this.useNumbers) charset += '0123456789';
    if (this.useSpecial) charset += '!@#$%^&*=+~`|;?><,.';
    if (this.useBrackets) charset += '(){}[]';
    if (this.useMinus) charset += '-';
    if (this.useUnderscore) charset += '_';
    if (this.useSpace) charset += ' ';

    // 确保至少有一种字符类型被选中
    if (charset.length === 0) {
      this.useLowercase = true;
      charset = 'abcdefghijklmnopqrstuvwxyz';
    }

    let password = '';
    for (let i = 0; i < this.passwordLength; i++) {
      const randomIndex = Math.floor(Math.random() * charset.length);
      password += charset.charAt(randomIndex);
    }

    // 更新密码
    this.password = password;

    // 评估密码强度
    this.evaluatePasswordStrength();
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
        Text('密码生成器')
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
        TextInput({ text: this.password })
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .borderRadius(8)
          .width("100%")
          .onChange((value)=>{
            this.password = value;
            this.evaluatePasswordStrength();
          })

        // 密码强度指示器
        Row() {
          Text('密码强度：')
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

          Text(this.passwordStrength === 0 ? '弱' : (this.passwordStrength === 1 ? '中' : '强'))
            .fontSize(12)
            .fontColor(this.passwordStrength === 0 ? '#FF0000' : (this.passwordStrength === 1 ? '#FFCC00' : '#00CC00'))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 8, bottom: 8 })

        // 密码长度滑块
        Row() {
          Text('密码长度：' + this.passwordLength)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Slider({
            value: this.passwordLength,
            min: 1,
            max: 32,
            step: 1,
            style: SliderStyle.OutSet
          })
            .width('60%')
            .onChange((value: number) => {
              this.passwordLength = value;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 8, bottom: 8 })

        // 大写字母选项
        Row() {
          Checkbox({ name: 'uppercase', group: 'passwordOptions' })
            .select(this.useUppercase)
            .onChange((value) => {
              this.useUppercase = value;
            })
          Text('大写字母 (A-Z)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useUppercase = !this.useUppercase;
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
            })
          Text('小写字母 (a-z)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useLowercase = !this.useLowercase;
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
            })
          Text('数字 (0-9)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useNumbers = !this.useNumbers;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 特殊字符选项
        Row() {
          Checkbox({ name: 'special', group: 'passwordOptions'})
            .select(this.useSpecial)
            .onChange((value) => {
              this.useSpecial = value;
            })
          Text('特殊字符 (!@#$%^&*_+~`|;?><,./-=)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useSpecial = !this.useSpecial;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 括号选项
        Row() {
          Checkbox({ name: 'brackets', group: 'passwordOptions'})
            .select(this.useBrackets)
            .onChange((value) => {
              this.useBrackets = value;
            })
          Text('括号 ((){}[])')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useBrackets = !this.useBrackets;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 减号选项
        Row() {
          Checkbox({ name: 'minus', group: 'passwordOptions'})
            .select(this.useMinus)
            .onChange((value) => {
              this.useMinus = value;
            })
          Text('减号 (-)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useMinus = !this.useMinus;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 下划线选项
        Row() {
          Checkbox({ name: 'underscore', group: 'passwordOptions'})
            .select(this.useUnderscore)
            .onChange((value) => {
              this.useUnderscore = value;
            })
          Text('下划线 (_)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useUnderscore = !this.useUnderscore;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })

        // 空格选项
        Row() {
          Checkbox({ name: 'space', group: 'passwordOptions'})
            .select(this.useSpace)
            .onChange((value) => {
              this.useSpace = value;
            })
          Text('空格 ( )')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .onClick(() => {
              this.useSpace = !this.useSpace;
            })
        }
        .width('100%')
        .margin({ top: 4, bottom: 4 })
      }
      .width('100%')
      .margin({ top: 16, bottom: 16 })
      // 底部按钮
      Row() {
        Button(){
            Row() {
              Image($r('app.media.ic_check'))
                .width(24)
                .height(24)
                .margin({ right: 8 })
                .fillColor($r('app.color.text_primary'))
              Text('接受')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
          }
          .width('48%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r("app.color.bg_secondary"))
          .borderRadius(4)
          .onClick(() => {
            this.onGenerate(this.password);
            this.close();
          })

        Button('生成密码')
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
