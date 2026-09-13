# 签名配置

stable 和 testing 工作流在启用相应 GUI 构建时需要签名凭据。请在以下位置保存所有凭据：

`仓库 Settings` → `Secrets and variables` → `Actions` → `New repository secret`

不要把证书、私钥、密钥库、密码或它们的 Base64 副本提交到此仓库。

## Windows GUI

桌面客户端使用 P12/PFX 格式的自签名 Authenticode 证书。证书必须：

- 包含私钥；
- 包含代码签名增强型密钥用法（`1.3.6.1.5.5.7.3.3`）；
- 尚未过期。

自签名证书不会被其他 Windows 设备自动信任，安装程序仍可能显示“未知发布者”和 Microsoft Defender SmartScreen 警告。工作流不会把该证书导入 GitHub runner 的根证书存储，以免触发无法操作的安全确认窗口。

在 Windows PowerShell 中生成一个与 reF1nd 类似的 RSA 3072 位、有效期 10 年的自签名代码签名证书：

```powershell
$certificate = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject "CN=你的发布者名称 Windows Code Signing" `
  -FriendlyName "sing-box Windows Code Signing" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyAlgorithm RSA `
  -KeyLength 3072 `
  -HashAlgorithm SHA256 `
  -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(10)

$password = Read-Host "设置 P12 密码" -AsSecureString
Export-PfxCertificate `
  -Cert $certificate `
  -FilePath .\windows-signing.p12 `
  -Password $password
Export-Certificate `
  -Cert $certificate `
  -FilePath ".\windows-signing-$($certificate.Thumbprint).cer"

$certificate | Format-List Subject, Issuer, Thumbprint, NotBefore, NotAfter
```

请妥善保存 `windows-signing.p12`、P12 密码和输出的证书指纹。`.cer` 只包含公钥，可以公开分发。

将 P12 转换为 Base64 并直接复制到剪贴板：

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes((Resolve-Path .\windows-signing.p12))
) | Set-Clipboard
```

创建以下仓库 Secrets：

- `WINDOWS_CERTIFICATES_P12`：上一步复制的 Base64 文本。
- `WINDOWS_P12_PASSWORD`：导出 P12/PFX 时设置的密码。

工作流会在打包前检查 P12 是否包含私钥、代码签名用途以及是否过期。实际签名由桌面客户端的 Electron Builder 配置执行，不再额外校验安装程序的 Authenticode 状态。x64 构建还会上传 `windows-signing-指纹.cer` 公钥证书并随 GitHub Release 发布。

最终用户只有在确认公钥证书来源和指纹无误后，才能选择手动信任：

```powershell
Import-Certificate `
  -FilePath .\windows-signing-指纹.cer `
  -CertStoreLocation "Cert:\CurrentUser\Root"
Import-Certificate `
  -FilePath .\windows-signing-指纹.cer `
  -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher"
```

导入后，该用户账户会信任所有由此证书签署且签名有效的程序。不要要求用户信任未经安全渠道核对指纹的证书。

## Linux GUI

工作流使用同一个 OpenPGP 密钥完成以下签名：

- 在每个 DEB 包中嵌入 `origin` 签名；
- 在每个 RPM 包中嵌入签名；
- 为每个 Pacman `.pkg.tar.zst` 包生成独立的 `.sig` 签名文件。

在可信设备上创建专用签名密钥：

```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format LONG
```

建议使用支持签名的 RSA 4096 位密钥，设置强密码，并记录完整的 40 位指纹。然后导出私钥和公钥：

```bash
gpg --armor --export-secret-keys 完整指纹 > linux-signing-private.asc
gpg --armor --export 完整指纹 > linux-signing-public.asc
```

创建以下仓库 Secrets：

- `GPG_KEY`：`linux-signing-private.asc` 的完整内容，包括 BEGIN/END 行。
- `GPG_KEY_ID`：完整的 40 位密钥指纹。
- `GPG_PASSPHRASE`：私钥密码。

配置 GitHub 后，应将 `linux-signing-private.asc` 离线保存。工作流会把公钥以 `GPG-完整指纹.asc` 的名称发布，并在上传前验证三种 Linux 包的签名。

下载 Release 后可按以下方式验证 Pacman 和 RPM 包：

```bash
gpg --import GPG-完整指纹.asc
gpg --verify SFL-版本-架构.pkg.tar.zst.sig SFL-版本-架构.pkg.tar.zst
sudo rpm --import GPG-完整指纹.asc
rpm --checksig SFL-版本-架构.rpm
```

DEB 包可以使用以下命令验证：

```bash
debsig-verify SFL-版本-架构.deb
```

`debsig-verify` 还要求本机安装信任该公钥的策略文件。CI 验签过程中会自动创建一个隔离的临时策略。

## Android GUI

Android 构建继续使用 reF1nd 原有的 keystore 签名机制。发布密钥库只应生成一次并永久保留，以后的 APK 更新必须使用相同密钥。

```powershell
keytool -genkeypair -v `
  -keystore release.keystore `
  -alias release `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000

[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes((Resolve-Path .\release.keystore))
) | Set-Clipboard
```

创建以下仓库 Secrets：

- `RELEASE_KEYSTORE_FILE`：`release.keystore` 的 Base64 文本。
- `RELEASE_KEYSTORE_PASSWORD`：密钥库密码。
- `RELEASE_KEY_ALIAS`：密钥别名，例如 `release`。
- `RELEASE_KEY_PASSWORD`：私钥密码。

## 不再需要的 Secrets

`GITHUB_TOKEN` 由 GitHub 自动提供。仅发布到 GitHub 的工作流不再需要 Telegram 凭据，也不需要对独立 sing-box 源码仓库具有写权限的令牌。

如果此前配置过以下 Secrets，可以将其删除：

- `CHAT_ID`
- `BOT_TOKEN`
- `API_ID`
- `API_HASH`
- `SING_BOX_REPOSITORY_TOKEN`
