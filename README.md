# ![KeePassHO Logo](entry/src/main/resources/base/media/startIcon.png) 
# KeePassHO

KeePassHO：安全管理您的密码，随时随地访问

KeePassHO是一款免费、开源的密码管理软件，完全兼容KeePass数据库格式（.kdbx），支持与KeePass各平台客户端无缝协作。

**核心特性：**

- 🔐 **本地存储** - 密码数据库仅保存在用户本地设备，不依赖云端服务器，从根本上规避云端泄露风险
- 🛡️ **强加密保护** - 采用AES-256等顶级加密算法，主密码+密钥文件双重保护
- 🔄 **KeePass兼容** - 完全兼容KeePass数据库格式，可与其他KeePass客户端共享同一数据库
- 🔑 **密码生成** - 内置强密码生成器，支持自定义密码规则
- 📁 **分类管理** - 支持文件夹分组、标签分类，快速组织密码条目
- 🔍 **智能搜索** - 快速检索密码条目，支持多条件筛选
- 🌐 **可扩展** - 支持浏览器集成（开发中）、云同步（需自行配置）等能力


## 安装

鸿蒙手机扫码安装：  
<a href="https://appgallery.huawei.com/app/detail?id=com.aimilin.keepassho&channelId=SHARE&source=appshare" target="_blank">
    <img src="install.png" width="200" alt="WeChat Support">
</a>

[鸿蒙应用市场](https://appgallery.huawei.com/app/detail?id=com.aimilin.keepassho&channelId=SHARE&source=appshare)

其他平台支持：
<a href="https://keepass.info/download.html" target="_blank">Windows、Mac、Linux、Android、Iphone</a>

## 编译构建
- 在window中编译指令
```bash
 hvigorw  --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```
- 在mac中使用编译指令

```bash
hvigorw  --mode module -p product=mac_debug -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
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

KeePassHO is a free, open-source password manager that is fully compatible with the KeePass database format (.kdbx), enabling seamless collaboration with KeePass clients across various platforms.

**Core Features:**

- 🔐 **Local Storage** - Password databases are stored only on your local devices without relying on cloud servers, fundamentally eliminating cloud leakage risks
- 🛡️ **Strong Encryption** - Protected by top-tier encryption algorithms like AES-256, with dual protection from master password and key file
- 🔄 **KeePass Compatible** - Fully compatible with KeePass database format, allowing you to share the same database with other KeePass clients
- 🔑 **Password Generation** - Built-in strong password generator with customizable password rules
- 📁 **Category Management** - Supports folder grouping and tag classification for quick organization of password entries
- 🔍 **Smart Search** - Quickly search password entries with multi-condition filtering
- 🌐 **Extensible** - Supports browser integration (in development), cloud sync (self-configured), and more capabilities


## Installation

Scan the QR code with your HarmonyOS phone to install:  
<a href="https://appgallery.huawei.com/app/detail?id=com.aimilin.keepassho&channelId=SHARE&source=appshare" target="_blank">
    <img src="install.png" width="200" alt="Install">
</a>

Other Platform：<a href="https://keepass.info/download.html" target="_blank">Windows、Mac、Linux、Android、Iphone</a>

## Build

- windows build
```bash
 hvigorw  clean --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --parallel --incremental --enable-build-script-type-check --daemon
```

- mac build
```bash
hvigorw  clean --mode module -p product=mac_debug -p buildMode=debug assembleHap --analyze=normal --parallel --incremental --enable-build-script-type-check --daemon
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
