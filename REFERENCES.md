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
