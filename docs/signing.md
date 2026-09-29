# 签名与发布配置

Tappy 是 SwiftPM + Makefile 工程，不依赖 Xcode 自动签名。所有涉及
开发者身份的敏感信息**不存放在仓库内**，本文件记录它们的存放位置、
用途和恢复步骤。

## 仓库内（可公开，可提交）

| 文件 | 内容 |
|---|---|
| `Scripts/bundle.sh` | 打包 + 签名逻辑，默认 Bundle ID `com.github.f2077.tappy` |
| `Scripts/signing.example.sh` | 本地配置模板，不含真实值 |
| 本文档 | 体系说明 |

`.gitignore` 中对 `*.p12`、`*.p8`、`*.provisionprofile`、
`*.certSigningRequest` 的排除只是兜底，正常流程不会把这些文件放进
工程目录。

## 仓库外（仅本机，绝不提交）

| 位置 | 内容 | 权限 |
|---|---|---|
| `~/.config/tappy/signing.sh` | Bundle ID、签名证书身份、profile 路径 | `chmod 600` |
| macOS 钥匙串（登录） | Apple Development 证书 + 私钥、WWDR 中间证书 | 系统管理 |
| `~/Downloads/*.provisionprofile` | 从开发者后台下载的授权文件 | 默认 |

`bundle.sh` 运行时 source `~/.config/tappy/signing.sh`（可用环境变量
`TAPPY_SIGNING_CONFIG` 指向别处）。配置项用 `: "${VAR:=值}"` 形式
赋值，使调用方（如 `make-pkg.sh`）可以通过环境变量覆盖。包含三个
变量：

- `TAPPY_BUNDLE_ID` — 开发者后台注册的 App ID
- `TAPPY_SIGN_IDENTITY` — 证书身份，完整字符串用
  `security find-identity -v -p codesigning` 查看；留空则 ad-hoc 签名
- `TAPPY_PROVISION_PROFILE` — `.provisionprofile` 文件路径，会被嵌入
  app 的 `Contents/embedded.provisionprofile`

上架另需三个变量（`make pkg` 使用）：

- `TAPPY_APPSTORE_IDENTITY` — Mac App Distribution 证书（钥匙串里显示
  为 "3rd Party Mac Developer Application" 或 "Apple Distribution"）
- `TAPPY_INSTALLER_IDENTITY` — Mac Installer Distribution 证书，用于
  给 pkg 安装包签名
- `TAPPY_APPSTORE_PROFILE` — Mac App Store 类型的分发授权文件

`make pkg` 产出 `build/Tappy.pkg`：app 本体用分发证书 + 沙盒
entitlements（`Scripts/Tappy.entitlements`）签名并嵌入分发 profile，
再由 `productbuild` 打包并用安装器证书签名。上传用 Transporter
应用或 `xcrun altool --upload-app`。

**没有配置文件时一切照常工作**：`make app` 产出 ad-hoc 签名的包，
可在本机运行调试。开源贡献者不需要任何配置。

## 证书链排错

钥匙串里证书显示 "not trusted" 时，是缺少签发它的 WWDR 中间证书。
查看证书的 Issuer 字段确认需要哪一代（G3/G4/…），然后从苹果官方页
下载安装：

    https://www.apple.com/certificateauthority/

注意 WWDR 各代同名不同代，必须与 Issuer 对号入座；旧 G3 已于
2023-02 过期，现役 G3 于 2030-02 过期。

## 新机器恢复步骤

1. 钥匙串访问 → 证书助理 → 从证书颁发机构请求证书，生成 CSR
2. 开发者后台创建证书（开发用 Apple Development；上架用
   Mac App Distribution + Mac Installer Distribution），下载安装
3. 按上节安装匹配的 WWDR 中间证书
4. 后台下载 `.provisionprofile` 到本机
5. 参考 `Scripts/signing.example.sh` 写
   `~/.config/tappy/signing.sh`，`chmod 600`
6. `make app` 验证：`codesign -dvv build/Tappy.app` 应显示正确的
   Identifier 和 Authority 链

## 将来 CI 发布（GitHub Actions）

上述本机配置对应到仓库的 GitHub Secrets（Settings → Secrets and
variables → Actions），fork PR 默认读不到 secrets，开源仓库可安全
使用：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE_P12` | 证书+私钥导出的 base64 |
| `MACOS_CERTIFICATE_PASSWORD` | p12 导出密码 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码 |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` | App Store Connect API 密钥 |

CI 脚本从 secrets 还原出钥匙串和同样的环境变量后，`bundle.sh`
无需改动即可复用。
