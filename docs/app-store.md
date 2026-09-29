# App Store 上架合规清单

付费上架（预计 ¥1）+ 源码公开（MIT）双轨模式的合规要点。代码与素材的
许可状态见根目录 `LICENSE` 与 `NOTICE`。

## 素材合规（已落实）

| 素材 | 许可 | 义务 | 落点 |
|---|---|---|---|
| Twemoji 实体矢量图 | CC-BY 4.0 | 署名 + 许可链接 + 标明修改 | 设置页致谢行、各包 `NOTICE.txt`、App 内 `NOTICE.txt`、本页商店描述文案 |
| OpenGameArt 音效 | CC0 | 无 | 各包 `sounds/NOTICE.txt`（自愿保留出处） |
| 合成音效 | 自有（`Scripts/synth-*.swift`） | 无 | — |
| SwiftDraw 依赖 | zlib | 保留版权声明 | `NOTICE` / App 内 `NOTICE.txt` |
| 应用图标 | AI 生成（OpenAI 输出权利让渡） | 无 | `NOTICE` 有说明 |
| SF Symbols 兜底字形 | Apple 许可 | 仅限 Apple 平台运行时引用 | 见 `docs/resource-packs.md` |

## 商店描述需要附的署名文案

CC-BY 4.0 要求署名"对该媒介合理"。App 内致谢已加，商店描述再附一段
（英文，放描述末尾即可）：

```
Artwork: Twemoji, copyright 2019-2024 Twitter, Inc. and other
contributors, licensed under CC-BY 4.0
(https://creativecommons.org/licenses/by/4.0/). Some sound effects from
OpenGameArt.org contributors (CC0). SVG rendering by SwiftDraw
(copyright Simon Whitty, zlib license).
```

## 上架前自查

- [x] **商标**："Tappy" 已有同名应用 → 商店名定为 **Pat-a-Pet**
      （敲敲小世界），仓库与二进制保持 Tappy 不变
- [ ] **隐私清单**：App 不联网、不收集数据，App Store Connect 隐私
      问卷全选"不收集"；未触碰 required-reason API，无需
      `PrivacyInfo.xcprivacy`
- [x] **类别**：主要类别"教育"——macOS 无"儿童"类别（iOS 专有，
      上传校验 90249 实测拒绝 `public.app-category.kids`）；年龄分级
      4+ 不变。承诺不含第三方广告/分析（当前代码满足），家长门
      （设置长按 P 两秒）符合"家长内容隔离"要求
- [x] **截图与预览**：`Scripts/capture-screens.sh` 生成中英两套
      Retina 截图（`build/screens/`，2880×1800 无 alpha）
- [x] **开源联动**：源码 MIT 公开于 GitHub，商店页支持 URL 链到
      仓库，隐私政策 URL 链到 `PRIVACY.md`，不影响付费销售

## 为什么 MIT 而不是 GPL

GPL 与 App Store 的分发条款冲突（Apple 的 DRM 属于 GPL 禁止的"进一步
限制"）。作为唯一版权人时可以双许可绕过，但一旦接受外部 PR，所有
贡献者都持有版权，再想上架就需要全员同意。MIT 没有这个问题：
任何人都可以编译免费用，商店版卖的是便利，这是成熟模式。
