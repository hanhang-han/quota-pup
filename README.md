# 余粮 · Quota Pup

一只住在 macOS 菜单栏里的像素小狗，用姿态和动画表达 Codex 剩余额度。

![五种额度状态的像素小狗](Assets/preview.gif)

菜单栏只显示小狗。点开后可以看到放大的小狗、剩余百分比和额度恢复时间。

## 五种状态

| 剩余额度 | 姿态 | 循环动画 |
| --- | --- | --- |
| 大于 70% | 精力满满 | 摇尾、探头、偶尔眨眼 |
| 大于 40%，不超过 70% | 状态不错 | 慢摇尾、眨眼 |
| 大于 15%，不超过 40% | 慢慢来 | 坐着摆尾、抖耳 |
| 大于 0%，不超过 15% | 快到休息时间了 | 趴着呼吸、轻摆尾 |
| 0% | 睡一觉再来 | 慢呼吸、偶尔动耳朵 |

五态共 46 帧，共用 24×18 像素网格。菜单栏使用系统单色模板图，面板显示暖色版本，自动适配深浅外观。系统开启“减少动态效果”时显示静态姿态。

## 环境要求

- macOS 14 或更新版本。
- Xcode 或可用的 Xcode Command Line Tools / Swift 工具链。
- Python 3，用于构建时生成独立的 HTML 设计预览。
- 已安装 [CodexBar](https://github.com/steipete/CodexBar)，且 Codex 已使用 ChatGPT 账号登录。

**当前版本通过 CodexBar 的内置 CLI 读取实际额度**，不是完整 CodexBar 的 fork。CLI 默认路径：

```text
/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI
```

CodexBar 可按其官方说明安装：

```bash
brew install --cask codexbar
```

## 构建与运行

```bash
git clone https://github.com/hanhang-han/quota-pup.git
cd quota-pup
./build.sh
open "build/余粮.app"
```

构建不需要下载 Swift 第三方依赖。输出为本地 ad-hoc 签名的应用，尚未进行 Apple 公证，也尚未提供正式发行安装包。

默认启动后展开小狗面板。只在菜单栏后台运行：

```bash
open "build/余粮.app" --args --background
```

点开右上角的“更多”，可刷新额度、查看最近读数或退出。没有自动安装开机启动项。

## 如何读取额度

每分钟调用一次：

```bash
/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI usage --provider codex --source oauth --format json --no-credits
```

原型本身不读取或保存登录令牌，凭证处理委托给 CodexBar。读取失败时显示问号并标明上次读数；未知状态不会当成零额度。

若同时报告多个额度窗口，使用剩余百分比最少的窗口；恢复时间也来自该窗口。按窗口长度判断周期，不假设 primary 一定是短时额度。该工具展示 Codex 服务报告的额度，不代表 ChatGPT 所有模型的聊天次数。

动画按每帧到期时间调度并缓存菜单栏图标，长停顿期间不会固定频率轮询。当前同步结果写入本机 build/runtime-status.json，只含百分比、窗口、造型和时间，不含账号或令牌；此文件不纳入 Git。

## 源码与素材

```text
Sources/main.swift       AppKit 菜单栏、面板、动画与额度读取
Assets/sprites.json      五态的完整原始像素网格与动画帧时长
Assets/preview.gif       动画展示
Assets/poses.png         五种姿态概览
preview.template.html    交互设计稿的可编辑源码
preview.html             已生成、可离线打开的交互预览
build.sh                 校验素材、生成预览、编译并签名
docs/design-notes.md     造型与动画参数
REFERENCES.md            设计参考
```

修改 Assets/sprites.json 后重新运行 ./build.sh，原生资源和 HTML 预览会一起更新。
直接在浏览器打开 preview.html 可体验五档、深浅外观和断网状态；滑杆使用演示数据，与实际账号额度独立。

## 当前状态

这是可运行的早期原型，已在开发机完成 Swift 编译、真实额度同步与浏览器预览检查。尚未完成长期稳定性和多设备验收。
GitHub Actions 构建只验证源码和素材可构建，不验证真实账号或线上额度接口。

## 许可证与设计参考

源码与本仓库原创像素素材采用 [MIT](LICENSE) 许可证。
造型与动作参考 [pixelpets](https://github.com/JOhnsonKC201/pixelpets) 和 [oneko.js](https://github.com/adryd325/oneko.js)，像素网格为本次重新绘制。详见 [REFERENCES.md](REFERENCES.md)。
CodexBar 是单独安装的上游项目，按其自身许可证分发。本仓库不包含其二进制或源码，也不隶属于 OpenAI。
