# App Store Connect 文案清单（直接粘贴版）

按字段组织，中英各一份。对应 ASC「1.0 准备提交」页的输入框。
仓库已开源（MIT）：<https://github.com/F2077/Tappy>。

- **支持 URL**：`https://github.com/F2077/Tappy`
- **隐私政策 URL**：`https://github.com/F2077/Tappy/blob/main/PRIVACY.md`

---

## 简体中文（zh-Hans，首发主语言之外的第二本地化）

**名称**：敲敲小世界
**副标题**：爸爸写给女儿的小世界
**宣传文本**（170 字内，可随时更新）：拍一下，世界就回应。

**描述**：

敲敲小世界（Pat-a-Pet）是一款为幼儿设计的启蒙互动应用：拍一拍键盘、点一点鼠标，屏幕上就蹦出一只小动物或一辆小车，带着它的名字和叫声。

它起源于一位爸爸为 15 个月大的女儿写的小程序：她拍一下，世界就回应一下；名字和故事，由爸爸妈妈来讲。

【孩子会获得什么】
· 动物与交通工具认知：名字、叫声、按真实比例缩放的大小对比——蚂蚁真的很小
· 因果感知：每个动作都有回应，鼓励主动探索
· 两大主题（小动物 / 交通工具）、四个场景，主题包持续扩展

【为家长设计】
· 幼儿锁定：全屏防误触，宝宝乱按也出不去；长按 Esc 1.5 秒退出
· 长按 P 两秒进入家长设置，宝宝的小手指做不到
· 无广告、无内购、不联网、不收集任何数据
· 合成语音朗读默认关闭——念名字这件事，留给你

素材致谢：Artwork: Twemoji, copyright 2019-2024 Twitter, Inc. and other contributors, licensed under CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Some sound effects from OpenGameArt.org contributors (CC0). SVG rendering by SwiftDraw (copyright Simon Whitty, zlib license).

**关键词**（100 字符内）：宝宝,幼儿,早教,认知,亲子,动物,声音,启蒙,拍拍,玩具
**What's New**：首次发布。
**版权**：2026 F2077

---

## 英文（en，主语言）

**Name**: Pat-a-Pet
**Subtitle**: For my daughter, and yours
**Promotional Text**: A world that answers every tap.

**Description**:

Pat-a-Pet (敲敲小世界) is an early-learning app for toddlers: tap the
keyboard or click the mouse, and an animal or vehicle pops up with its
name and real sounds.

It began as a dad's gift to his 15-month-old daughter: she taps, the
world answers, and the naming is left to mom and dad.

[What kids get]
· Animal & vehicle vocabulary: names, sounds, and true-to-life size
  contrast — the ant really is tiny
· Cause and effect: every action gets a response
· Two themes (animals / vehicles), four scenes, more coming as packs

[Designed for parents]
· Toddler lock: full-screen child-safe mode — banging keys can't
  escape; hold Esc 1.5 s to quit
· Hold P 2 s for parent settings — tiny fingers can't do it
· No ads, no in-app purchases, no internet, no data collection
· Voice narration is off by default — saying the names is your part

Artwork: Twemoji, copyright 2019-2024 Twitter, Inc. and other
contributors, licensed under CC-BY 4.0
(https://creativecommons.org/licenses/by/4.0/). Some sound effects from
OpenGameArt.org contributors (CC0). SVG rendering by SwiftDraw
(copyright Simon Whitty, zlib license).

**Keywords** (≤100 chars): toddler,baby,early learning,animals,sounds,cognitive,parent,child,interactive,kinetic
**What's New**: First release.
**Copyright**: 2026 F2077

---

## 截图（build/screens/，已按 ASC 规格生成）

| 文件 | 用途 | 规格 |
|---|---|---|
| `01-playfield` | 主打图：游玩画面 + 名称标签 | 2880×1800 |
| `02-second-scene` | 第二场景（朝雾草原） | 2880×1800 |
| `03-settings` | 家长设置（幼儿锁定/隐私承诺可见） | 2880×1800 |
| `04-about` | 关于页（背景故事 + 开源致谢） | 2880×1800 |

`zh-Hans/` 与 `en/` 各一套。重新生成：`Scripts/capture-screens.sh`。
上传顺序建议：01 → 02 → 03 → 04（教育定位的印象递进）。
若想加营销排版（渐变底、大字标题），用 Figma 把原图垫底重排，
导出尺寸不变即可；不排版直接传也完全合规。

## 其他字段

- **SKU**：laptap-macos（建记录时已填）
- **Bundle ID**：Tappy - com.github.f2077.tappy
- **主要类别**：儿童 → 5 岁及以下；次要类别：教育
- **支持 URL**：`https://github.com/F2077/Tappy`；**营销 URL**：可空
- **隐私政策 URL**：`https://github.com/F2077/Tappy/blob/main/PRIVACY.md`（必填）
- **年龄分级**：4+ · 面向儿童 · 5 岁及以下（已配置）
- **定价**：¥1（Tier 1）

## 隐私政策文本

正式文本见仓库根目录 `PRIVACY.md`（中英双语），其 GitHub 页面即
ASC 填写的隐私政策 URL。修改隐私文本时两边是同一文件，无需同步。
