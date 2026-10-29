# 造型与动作参考

## pixelpets

- 仓库：https://github.com/JOhnsonKC201/pixelpets
- 原理说明：https://github.com/JOhnsonKC201/pixelpets/blob/main/docs/architecture.md
- 小狗实现：https://github.com/JOhnsonKC201/pixelpets/blob/main/src/dog-sprite.js

参考其宠物比例、分角色着色、局部动作与固定头脚的表现：让大头短腿更亲切，眨眼和尾巴有不同节奏；身体呼吸时不缩放整张像素图。

## oneko.js

- 仓库：https://github.com/adryd325/oneko.js
- 实现：https://github.com/adryd325/oneko.js/blob/main/oneko.js

参考其低分辨率单色轮廓、分段停顿与慢速睡眠切帧。彩色图与菜单栏模板图共享像素网格，保留眼睛、口鼻的负空间。

本项目的像素网格为本次重新绘制，未引入以上项目的图片、精灵表或运行时依赖。参考链接用于说明设计来源。

## CodexBar 额度读取

- 上游：https://github.com/steipete/CodexBar
- 参考模块：CodexOAuthCredentials.swift、CodexOAuthUsageFetcher.swift。
- 仅抽取并精简本机 OAuth 文件读取、官方 HTTPS 请求和窗口解析到 Sources/QuotaClient.swift。无 CodexBar 应用、CLI 或其他 provider 运行时依赖。
- 共享令牌只读，不复制上游庞大的刷新、浏览器或账号管理模块。
- MIT 声明见 [ThirdPartyNotices/CodexBar.txt](ThirdPartyNotices/CodexBar.txt)。
