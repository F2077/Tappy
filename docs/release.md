# 直接下载发布(GitHub Release + 公证 DMG)

中国大陆等不在 App Store 上架的区域,走 GitHub Release 直接下载。为了
让下载者的 Mac **不被 Gatekeeper 拦截**(不显示"已损坏"/"无法验证开发者"),
DMG 必须经过三道工序,缺一不可:

1. **Developer ID Application 签名**(带 hardened runtime)
2. **Apple 公证**(notarization,上传 Apple 扫描)
3. **Staple**(把公证票据钉进 DMG,离线也能验证)

> 注意:App Store 用的 "Apple Distribution" 证书**不能**用于直接下载
> 分发——用错证书 Gatekeeper 照样拦截。必须是 "Developer ID
> Application"。两者都包含在付费开发者账号里,无需额外购买。

## 一次性准备

### 1. 创建 Developer ID Application 证书

1. 打开 <https://developer.apple.com/account/resources/certificates> →
   **+** → 选 **Developer ID Application**
2. 按提示上传 CSR(钥匙串访问 → 证书助理 → 从证书颁发机构请求证书)
3. 下载 `.cer` 双击导入钥匙串
4. 验证:`security find-identity -v -p codesigning` 应能看到
   `Developer ID Application: …`

### 2. 导出 p12(供 CI 使用)

钥匙串访问 → 找到该证书(连同私钥一起选中)→ 右键导出 → `.p12`,
设置一个导出密码。

### 3. 创建 App Store Connect API 密钥(供公证使用)

1. <https://appstoreconnect.apple.com> → 用户和访问 → 集成(Integrations)
   → App Store Connect API → 团队密钥 → **+**(角色选 Developer 即可)
2. 记录 **Key ID** 和 **Issuer ID**,下载 `AuthKey_XXX.p8`
   (**只能下载一次**,妥善保管在仓库外)

### 4. 配置 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions,添加:

| Secret | 内容 |
|---|---|
| `TAPPY_DEVELOPER_ID_P12_BASE64` | `base64 -i dev-id.p12 \| pbcopy` 的结果 |
| `TAPPY_DEVELOPER_ID_P12_PASSWORD` | 导出 p12 时设的密码 |
| `TAPPY_NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXX.p8 \| pbcopy` 的结果 |
| `TAPPY_NOTARY_KEY_ID` | 第 3 步的 Key ID |
| `TAPPY_NOTARY_ISSUER_ID` | 第 3 步的 Issuer ID |

CI 里证书身份(含 Team ID)是从钥匙串动态发现的,不写死在仓库里。

## 发布一个版本

```sh
git tag v1.0.0
git push origin v1.0.0
```

或在 Actions 页面手动触发 "release" 工作流并填版本号。流水线会:
release 构建 → Developer ID 签名 → 打 DMG → 公证 + staple →
`spctl` 验证 → 创建 GitHub Release 并附上 `Tappy.dmg`(版本号/构建号
取自 tag 与 run number)。注:CI 上暂不跑 `make test`——TappyChecks
在 runner 镜像上启动即崩(疑似运行库差异),发版前请本地跑过
`make test` 与 `make smoke`。

首次公证可能要 5–15 分钟,之后通常 1–2 分钟。

## 本地产出同样的 DMG

在 `~/.config/tappy/signing.sh` 里配置(见 `Scripts/signing.example.sh`):

```sh
TAPPY_DEVELOPER_ID_IDENTITY="Developer ID Application: …"
TAPPY_NOTARY_KEY=$HOME/Documents/AuthKey_XXX.p8
TAPPY_NOTARY_KEY_ID=…
TAPPY_NOTARY_ISSUER_ID=…
```

然后 `make release-dmg`。产物 `build/Tappy.dmg` 与 CI 完全一致。

## 验证下载者看到什么

本地下载(或 `curl -L` release 资产)后:

```sh
spctl -a -vv Tappy.dmg        # 期望: accepted, source=Notarized Developer ID
```

双击打开应**无任何警告**。如果显示"已损坏",说明签错证书;
显示"无法验证开发者",说明没公证或没 staple。
