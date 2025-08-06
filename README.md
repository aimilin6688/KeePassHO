# KeePassHO

KeePassHO：安全管理您的密码，随时随地访问

KeePassHO是一款免费、开源且广受赞誉的密码管理软件。它的核心优势在于本地存储和极致安全。您的所有密码都存储在一个加密的数据库中（通常为.kdbx文件），该文件仅保存在您自己的设备上（如电脑、移动设备），不依赖云端服务器，从根本上规避了云端泄露风险。

![KeePassHO Logo](entry/src/main/resources/base/media/startIcon.png)

## 功能特点

**核心要点：**

- 免费开源： 免费使用，代码透明可审计。
- 本地存储： 密码数据库文件（.kdbx）仅保存在用户本地设备，不上云。
- 强加密： 使用AES-256等顶级算法加密数据库，主密码是钥匙。
- 安全自主： 用户完全掌控自己的密码数据和安全策略。
- 功能完备： 密码生成、管理、填充、搜索等基础功能齐全。
- 可扩展： 通过插件支持浏览器集成、云同步（自控）等。
- 目标用户： 重视隐私、安全，希望完全自主管理密码的用户。

## 安装

### 从应用市场安装

1. 在HarmonyOS设备上打开AppGallery（华为应用市场）
2. 搜索"KeePassHO"
3. 点击安装

### 从源代码构建

1. 克隆仓库
   ```bash
   git clone https://gitee.com/milin/kee-pass-ho.git
   ```

2. 使用DevEco Studio打开项目

3. 构建并运行应用

## 使用方法

### 创建新数据库

1. 打开KeePassHO应用
2. 点击"创建新数据库"
3. 设置主密码和/或密钥文件
4. 选择保存位置
5. 开始添加密码条目

### 打开现有数据库

1. 打开KeePassHO应用
2. 点击"打开数据库"
3. 选择.kdbx文件
4. 输入密码和/或选择密钥文件
5. 访问您的密码

## 项目结构

```
KeePassHO/
├── AppScope/            # 应用级配置
├── entry/               # 应用入口模块
│   └── src/
│       ├── main/        # 主要源代码
│       │   ├── ets/     # ArkTS代码
│       │   └── resources/ # 资源文件
│       └── test/        # 测试代码
├── kdbxweb/             # KeePass数据库处理库
└── oh-package.json5     # 项目配置文件
```

## 技术栈

- HarmonyOS ArkTS
- HarmonyOS UI组件
- kdbxweb库（用于处理KeePass数据库）

### 主要特性

- 在浏览器或Node.js中运行
- 无原生插件依赖
- 使用WebCrypto进行快速加密
- 完全支持Kdbx功能
- 受保护的值在内存中以XOR方式存储
- 支持无冲突合并
- 高代码覆盖率
- 严格的TypeScript支持

更多关于kdbxweb库的信息，请参见[kdbxweb目录](./kdbxweb/README.md)。

## 贡献指南

我们欢迎所有形式的贡献，包括但不限于：

- 报告问题
- 提交功能请求
- 提交代码修复
- 改进文档
- 提交新功能

### 贡献步骤

1. Fork项目
2. 创建您的特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交您的更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 打开Pull Request

## 许可证

本项目采用MIT许可证 - 详情请参见[LICENSE](LICENSE)文件。

## 致谢
1. [kdbxweb](https://github.com/keeweb/kdbxweb)

2. [Font-Awesome](https://github.com/FortAwesome/Font-Awesome/tree/7.x)



## 联系方式

- 项目维护者: [艾米林](mailto:aimilin@yeah.net)
- 项目主页: [Gitee仓库](https://gitee.com/milin/kee-pass-ho/)

---

**KeePassHO** - 安全管理您的密码，随时随地访问
