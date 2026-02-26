# ![KeePassHO Logo](entry/src/main/resources/base/media/startIcon.png) 
# KeePassHO

KeePassHO：安全管理您的密码，随时随地访问

KeePassHO是一款免费、开源的密码管理软件。它的核心优势在于本地存储和极致安全。您的所有密码都存储在一个加密的数据库中（通常为.kdbx文件），该文件仅保存在您自己的设备上（如电脑、移动设备），不依赖云端服务器，从根本上规避了云端泄露风险。

数据库采用强大的加密算法（如AES-256）保护，只需记住一个高强度主密码（或结合密钥文件）即可解锁访问。KeePassHO支持自动生成强密码、分类管理、搜索等便捷功能，并拥有活跃社区和丰富插件生态，可扩展浏览器集成（开发中）、云同步（需自行配置）等能力。





## 功能特点

**核心要点：**

- 免费开源： 免费使用，代码透明可审计。
- 本地存储： 密码数据库文件（.kdbx）仅保存在用户本地设备，不上云。
- 强加密： 使用AES-256等顶级算法加密数据库，主密码是钥匙。
- 安全自主： 用户完全掌控自己的密码数据和安全策略。
- 功能完备： 密码生成、管理、填充、搜索等基础功能齐全。
- 可扩展： 通过插件支持浏览器集成（开发中）、云同步（自控）等。
- 目标用户： 重视隐私、安全，希望完全自主管理密码的用户。

## 安装

鸿蒙手机扫码安装：  
<a href="https://appgallery.huawei.com/app/detail?id=com.aimilin.keepassho&channelId=SHARE&source=appshare" target="_blank">
    <img src="install.png" width="200" alt="WeChat Support">
</a>

[鸿蒙应用市场](https://appgallery.huawei.com/app/detail?id=com.aimilin.keepassho&channelId=SHARE&source=appshare)

其他平台支持：
<a href="https://keepass.info/download.html" target="_blank">Windows、Mac、Linux、Android、Iphone</a>

## 编译构建
```bash
 hvigorw  clean --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --parallel --incremental --enable-build-script-type-check --daemon
```


## 技术栈

- HarmonyOS ArkTS
- HarmonyOS UI组件

## 贡献指南

我们欢迎所有形式的贡献，包括但不限于：

- 报告问题
- 提交功能请求
- 提交代码修复
- 改进文档
- 提交新功能

## 许可证

本项目采用GPL-3.0许可证 - 详情请参见[GPL-3.0](LICENSE)文件。

## 致谢
1. [kdbxweb](https://github.com/keeweb/kdbxweb)

2. [Font-Awesome](https://github.com/FortAwesome/Font-Awesome/tree/7.x)

3. [keepass](https://keepass.info/index.html)


## 联系方式

- 联系作者: [艾米林 aimilin@yeah.net](mailto:aimilin@yeah.net)
- 项目主页: [Gitee](https://gitee.com/milin/kee-pass-ho/)  [Github](https://github.com/aimilin6688/KeePassHO)

## 捐赠
微信支持  
<img src="entry/src/main/resources/base/media/pay_wechat.png" width="150" alt="WeChat Support">

支付宝支持   
<img src="entry/src/main/resources/base/media/pay_ali.png" width="150" alt="Alipay Support">
---

**KeePassHO** - 安全管理您的密码，随时随地访问

---

# KeePassHO - Securely manage your passwords, access them anywhere

KeePassHO is a free and open-source password management software. Its core advantage lies in local storage and maximum security. All your passwords are stored in an encrypted database (typically a .kdbx file), which is kept only on your own devices (such as computers, mobile devices), without relying on cloud servers, fundamentally avoiding cloud leakage risks.

The database is protected by powerful encryption algorithms (such as AES-256), and you only need to remember a strong master password (or combine it with a key file) to unlock and access it. KeePassHO supports convenient features such as automatic strong password generation, category management, and search, and has an active community and a rich plugin ecosystem. It can be extended with browser integration (in development), cloud synchronization (requires self-configuration), and other capabilities.

## Features

**Key Points:**

- **Free and Open Source**: Free to use, with transparent and auditable code.
- **Local Storage**: Password database files (.kdbx) are stored only on the user's local devices, not uploaded to the cloud.
- **Strong Encryption**: Uses top-tier algorithms like AES-256 to encrypt the database, with the master password as the key.
- **Security Autonomy**: Users have complete control over their password data and security policies.
- **Comprehensive Features**: Complete basic functions including password generation, management, filling, and search.
- **Extensible**: Supports browser integration (in development), cloud synchronization (self-controlled), etc. through plugins.
- **Target Users**: Users who value privacy and security and want complete autonomous password management.

## Installation

Scan the QR code with your HarmonyOS phone to install:  
<a href="https://appgallery.huawei.com/app/detail?id=com.aimilin.keepassho&channelId=SHARE&source=appshare" target="_blank">
    <img src="install.png" width="200" alt="Install">
</a>

Other Platform：<a href="https://keepass.info/download.html" target="_blank">Windows、Mac、Linux、Android、Iphone</a>

## Build
```bash
 hvigorw  clean --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --parallel --incremental --enable-build-script-type-check --daemon
```

## Tech Stack

- HarmonyOS ArkTS
- HarmonyOS UI Components

## Contributing

We welcome all forms of contributions, including but not limited to:

- Reporting issues
- Submitting feature requests
- Submitting code fixes
- Improving documentation
- Submitting new features

## License

This project is licensed under GPL-3.0 license - see the [GPL-3.0](LICENSE) file for details.

## Acknowledgments
1. [kdbxweb](https://github.com/keeweb/kdbxweb)

2. [Font-Awesome](https://github.com/FortAwesome/Font-Awesome/tree/7.x)

3. [keepass](https://keepass.info/index.html)

## Contact

- Contact Author: [Aimilin aimilin@yeah.net](mailto:aimilin@yeah.net)
- Project Homepage: [Gitee](https://gitee.com/milin/kee-pass-ho/)  [Github](https://github.com/aimilin6688/KeePassHO)

## Donate
WeChat Support  
<img src="entry/src/main/resources/base/media/pay_wechat.png" width="150" alt="WeChat Support">

Alipay Support   
<img src="entry/src/main/resources/base/media/pay_ali.png" width="150" alt="Alipay Support">
---

**KeePassHO** - Securely manage your passwords, access them anywhere
