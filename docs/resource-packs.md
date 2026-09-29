# 资源包（Resource Packs）

Tappy 的全部内容——角色（动物、车辆、人物……）、场景、音效、多语言名称、语音触发词、游行编排——都由**资源包**提供。
框架是通用的"宝宝键盘敲击乐园"，主题是资源包：小动物、工程车辆、海洋动物、人物职业……
新主题**不需要改代码**，做一个资源包就行（这也是未来 App Store 订阅内容的载体）。

## 包的形态

一个资源包 = 一个 `pack.json` 清单 + 素材文件，两种形态等效：

1. **目录**：`MyPack.tappypack/`（开发调试用，改完重启 App 生效）
2. **压缩包**：把目录 zip 后改名为 `MyPack.tappypack`（分发形态）
   ```sh
   ditto -c -k --keepParent MyPack.tappypack MyPack.tappypack.zip && mv MyPack.tappypack{.zip,}
   ```
   运行时自动解压到 `~/Library/Caches/Tappy/Packs/`；压缩包更新后（大小/mtime 变化）自动重新解压。

## 加载位置与优先级

1. 应用内置：`Contents/Resources/Tappy_TappyCore.bundle/Packs/*.tappypack`（随 App 发布）
2. 用户目录：`~/Library/Application Support/Tappy/Packs/*.tappypack`（免签名、免重装）

按文件名排序依次加载；**后加载的同 id 条目覆盖先前的**（用户包可以只覆盖内置包里的某一个角色或场景）。

一次只玩一个主题：设置页有**主题选择器**（装了多个包时出现，菜单式，数量不限，显示包的本地化 `names`），随机生成、语音匹配、场景列表都只作用于当前主题的包；**切换主题会清空屏幕上已有的角色**；主题选择持久化（`tappy.activePack`），包被移除后回退到第一个已加载的包。触发词列表只显示当前主题的角色，数量不限，列表滚动。

## 目录结构

```
MyPack.tappypack/
  pack.json          # 清单（必需）
  animals/*.svg      # 角色矢量图（可选，缺了用 SF Symbol 兜底）
  sounds/*.wav       # 音效（可选，缺了用系统音兜底）
```

## pack.json 格式

```jsonc
{
  "format": 1,
  "id": "my-pack",
  "names": {                    // 可选：主题选择器里显示的包名（缺省用 id）
    "en": "My Pack", "zh-Hans": "我的主题包"
  },
  "entities": [                 // 角色：动物、卡车、职业人物……都叫 entity
    {
      "id": "panda",                    // 必填，持久化数据按它关联
      "art": "animals/panda.svg",       // 可选：包内相对路径
      "sound": "sounds/panda.wav",      // 可选
      "symbol": "pawprint.fill",        // 可选：无 art 时的 SF Symbol 兜底
                                        // 注意：SF Symbol 仅限 Apple 平台 App 内
                                        // 运行时按名引用，不可打包进图标/素材，
                                        // 移植到其他平台时兜底字形不可用
      "color": "#FF9500",               // 可选：兜底图标的着色
      "systemSound": "Pop",             // 可选：无 sound 时的系统音
      "sizeScale": 1.4,                 // 可选：真实比例感，1.0 ≈ 猫
      "names": {                        // 各语言显示名，至少给 "en"
        "en": "Panda", "zh-Hans": "大熊猫"
      }
    }
  ],
  "scenes": [
    {
      "id": "candySky",
      "names": { "en": "Candy Sky", "zh-Hans": "糖果天空" },
      "idleAction": "sway",             // hop | sway
      "accentSound": "sounds/accent-candy.wav",   // 可选：游行开始等提示音
      "scene": {                        // 通用背景（不写 renderer 时生效）
        "gradient": ["#87CEEB", "#FFE4E1"],       // 天空渐变，上→下
        "ground": { "color": "#90EE90", "height": 0.18 },  // 可选
        "decorations": [                // 可选：摆放包内 SVG
          { "art": "animals/candy.svg", "x": 0.2, "y": 0.8,
            "scale": 1.2, "motion": "sway" }      // none|sway|drift|pulse
        ],
        "particles": { "kind": "fireflies", "count": 8 }   // fireflies|mist
      },
      "parade": {                       // 可选：游行编排
        "style": "lanes",               // lanes（多道蹦跳）| graze（单行缓行）
        "speed": 0.06,                  // 每秒走过的屏宽比例
        "laneY": [0.70, 0.86],          // 各跑道高度（归一化）；奇数道反向
        "amplitude": 20,                // 蹦跳/起伏幅度（点）
        "waveLength": 45                // 波形水平密度
      }
    }
  ]
}
```

所有字段除 `id` 外都可省略；缺什么用什么兜底。
清单解析失败只会跳过这一个包并写日志（`log show --info --predicate 'subsystem == "local.tappy.app"'`），不会崩。

## 内置特殊渲染器

场景清单里写 `"renderer": "mushroomForest"` 或 `"mistyMeadow"` 可复用 App 内置的手绘背景；
不写 `renderer` 则使用上面的数据驱动通用背景（内置 `Vehicles` 包的两个场景就是这样做的）。新场景一律走通用背景，无需写代码。

## 语言代码

`names` 的键：`en`、`zh-Hans`、`ja`、`ko`、`es`、`fr`、`de`。
查找顺序：当前语言 → `en` → 任意可用语言。

## 家长自定义优先级

- 音效：`~/Library/Application Support/Tappy/Sounds/<角色id>.wav` 可覆盖任何包内音效（`default.<ext>` 为通配）。
