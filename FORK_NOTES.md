# FluffyChat 注册版（个人分支说明）

这是 [krille-chan/fluffychat](https://github.com/krille-chan/fluffychat) 的个人分叉，
在上游代码基础上**新增了「应用内注册」**，并针对自己的服务器做了默认值调整。

上游 FluffyChat 本身**没有**注册页面：`/home/sign_up` 只是让你选服务器，然后跳转到
该服务器的网页注册。本分支直接在 App 里调用 Matrix 的
`POST /_matrix/client/v3/register`，注册成功后顺手把会话接上，直接进 App。

分支名：`register`

---

## 1. 改了什么

| 文件 | 改动 |
| --- | --- |
| `lib/pages/register/register.dart` | **新增**：注册页控制器（校验用户名/密码、查注册流程、注册、自动登录） |
| `lib/pages/register/register_view.dart` | **新增**：注册页界面（Logo、服务器、用户名、密码、确认密码、错误提示） |
| `lib/config/routes.dart` | 新增 `/home/register` 与 `/rooms/settings/addaccount/register` 路由 |
| `lib/pages/login/login_view.dart` | 登录页底部加「还没有账号？注册」入口 |
| `lib/pages/login/login.dart` | 新增 `openRegister()`（按当前路由层级跳到注册页） |
| `lib/utils/sign_in_flows/check_homeserver.dart` | 「创建新账户」不再跳网页，而是进入本 App 的注册页 |
| `lib/config/setting_keys.dart` | 默认服务器改为 `qmypc.tail7337aa.ts.net`（只影响预选，仍可手动填别的） |
| `lib/l10n/intl_en.arb` / `intl_zh.arb` | 注册相关文案（英文 + 中文） |
| `android/app/build.gradle.kts` | `applicationId` 改为 `chat.fluffy.fluffychat.reg`，可与官方版共存 |
| `android/app/src/main/AndroidManifest.xml` | 应用名改为「FluffyChat 注册版」 |
| `pubspec.yaml` | `hooks.user_defines.sqlite3.url_pattern` 走 GitHub 镜像（见第 4 节） |

### 注册流程（实现要点）

1. `GET /client/v3/register` 读取服务器支持的注册流程；
2. 只支持「只要求 `m.login.dummy`」的开放注册。有验证码 / 条款 / 邮箱验证的服务器会明确
   提示「请去网页注册」，不会假装成功；
3. `client.register(...)`（matrix-dart-sdk 16.x）一次性完成注册并**直接连上会话**，
   不用再登录一次、也不会留下多余的设备；如果服务器仍返回 `401 + session`，会带上
   session 再试一次；
4. 注册成功后跳 `/backup`（密钥备份引导页），与正常登录后的流程一致。

> 多账户能力保留：设置 → 添加账户 → 创建新账户 走的也是这个注册页。

### 注册请求（重要，踩过的坑）

这台 Synapse（1.67）**不支持** `GET /_matrix/client/v3/register`：

```
GET  → 400 {"errcode":"M_UNRECOGNIZED","error":"Unrecognized request"}
POST → 200（body 带 "auth":{"type":"m.login.dummy"}，直接注册成功）
```

所以注册页**不能**先去 GET 探测注册流程（早期版本就是这么写的，结果页面上显示
"Unrecognized request"），现在的做法是：

1. 用 `http` 包直接 POST `https://<homeserver>/_matrix/client/v3/register`
   （URL 自己拼，不依赖 SDK 的路径拼接；`debugPrint` 会打印 `REGISTER URL = ...`
   和 `REGISTER RESP = <status> <body>`）；
2. body 里带 `auth: {type: m.login.dummy}` 和 `inhibit_login: true`，
   避免注册时多出一个没人用的设备、也避免 access_token 出现在日志里；
3. 200 → 拿响应里的 `user_id`，再用同一套凭据 `client.login(...)`，让 SDK 接管会话；
4. 非 200 → 错误框里显示「状态码 + 服务器原文」，还会附一句人话解释
   （用户名被占/密码太弱/未开放注册/需要网页验证等），下次出问题一眼能看出来。

---

## 2. 构建环境（这台电脑已经装好）

| 组件 | 位置 / 版本 |
| --- | --- |
| Flutter | `C:\flutter`（**3.47.9**，与仓库 `.fvmrc` 一致） |
| Dart | 3.13.7（随 Flutter） |
| Rust | rustup + `aarch64-linux-android` target（rsproxy 镜像） |
| Android SDK | `C:\Users\QMYU\Documents\deepseek-harness\default-workspace\.android-sdk` |
| 平台 / build-tools / NDK | `android-37.0`、`android-37.2`、`android-36`、`android-35`、`android-34`、`37.0.0`、NDK `28.2.13676358` |
| JDK | `C:\Program Files\Java\jdk-21.0.10` |

已持久化的用户环境变量：

```
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
FLUTTER_ROOT=C:\flutter
PATH += C:\flutter\bin
PATH += <workspace>\tools\gh\bin
```

Rust 镜像：`%USERPROFILE%\.cargo\config.toml` → `sparse+https://rsproxy.cn/index/`
（注意：**不要**同时定义 `[source.rsproxy]` 和 `[source.rsproxy-sparse]`，
cargo 会报 "source ... already defined"，构建直接失败。）

### 构建命令

```powershell
cd C:\fluffychat-reg
$env:ANDROID_HOME='C:\Users\QMYU\Documents\deepseek-harness\default-workspace\.android-sdk'
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
$env:JAVA_HOME='C:\Program Files\Java\jdk-21.0.10'
flutter pub get
flutter build apk --release --target-platform android-arm64
```

产物：`build\app\outputs\flutter-apk\app-release.apk`（约 100 MB，
只带 arm64 的 Dart 本体；装到 arm64 手机上即可）

构建好的包已经另存一份在：
`<workspace>\release\FluffyChat-register-2.11.6-arm64.apk`

> `pubspec.lock` 保持上游版本没有提交改动，本机 `flutter pub get` 会重新解析
> （版本会比上游锁文件略新，属于正常现象，`git status` 里看到它变化不用管）。

---

## 3. 国内网络：构建时踩过的三个坑

1. **Gradle 发行包**：`services.gradle.org` 直连很慢（≈250 KB/s，224 MB 要十几分钟）。
   已把解压好的 9.3.1 发行包塞进 wrapper 缓存，构建会直接命中、不再下载：
   ```
   %USERPROFILE%\.gradle\wrapper\dists\gradle-9.3.1-all\<hash>\gradle-9.3.1\
   %USERPROFILE%\.gradle\wrapper\dists\gradle-9.3.1-all\<hash>\gradle-9.3.1-all.zip.ok
   ```
   如果哪天清了 `~\.gradle`，可以在 `android/gradle/wrapper/gradle-wrapper.properties`
   里把 `distributionUrl` 临时换成
   `https\://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`（**本机适配，不要提交**）。
2. **livekit_ffi 预编译库**：`livekit_ffi` 的 native-assets hook 会从 GitHub Releases
   下载 `build-aarch64-linux-android.zip`，直连必挂。已下载好并放进 pub 缓存：
   ```
   C:\Users\QMYU\AppData\Local\Pub\Cache\hosted\pub.flutter-io.cn\livekit_ffi-0.15.0\liblivekit_ffi.so
   ```
   hook 检测到包根目录有这个文件就走本地模式，不再联网。
   原始 zip 备份在 `C:\Users\QMYU\Documents\fluffychat-reg-deps\`。
   ⚠️ 这个 .so 是 **arm64** 的：要构建 armv7 / x86_64 时先把它删掉，
   否则会把 arm64 的库打进别的 ABI。
3. **sqlite3 的 SQLCipher 库**：同样从 GitHub Releases 下载。已在 `pubspec.yaml` 里
   用官方支持的 `hooks.user_defines.sqlite3.url_pattern` 改走镜像：
   ```yaml
   hooks:
     user_defines:
       sqlite3:
         source: sqlcipher
         url_pattern: https://gh-proxy.com/https://github.com/simolus3/sqlite3.dart/releases/download/$RELEASE_TAG/$FILENAME
   ```
   如果哪天 `gh-proxy.com` 也不通，换成其它 GitHub 镜像（或删掉这行、开代理再构建）。

> 有代理/VPN 时不用以上任何绕行；直接 `flutter build apk` 即可，
> Dart 的下载 hook 会读 `HTTPS_PROXY` 环境变量。

---

## 4. 签名

自用签名（**务必备份**，丢了之后同一 applicationId 无法覆盖升级）：

```
keystore : C:\Users\QMYU\Documents\fluffychat-reg-keystore\fluffy-release.jks
alias    : fluffyreg
密码     : 见同目录 password.txt
```

`android/key.properties`（已被 `.gitignore` 忽略）：

```
storeFile=C:/Users/QMYU/Documents/fluffychat-reg-keystore/fluffy-release.jks
storePassword=...
keyAlias=fluffyreg
keyPassword=...
```

### 与官方版共存

`applicationId` 是 `chat.fluffy.fluffychat.reg`，所以**可以**和官方 FluffyChat 同时安装，
不用卸载官方版。代价：它是另一个 App，本地数据库 / 登录状态互不相干。

想覆盖官方版？那需要官方私钥签名，办不到。

---

## 5. 以后加新功能怎么改

1. 新页面放 `lib/pages/<功能名>/`，参照 `lib/pages/register/` 的三件套写法：
   `Xxx extends StatefulWidget` + `XxxController extends State<Xxx>` + `XxxView`；
2. 路由加在 `lib/config/routes.dart`（注意 `/home` 和 `/rooms/settings/addaccount`
   两处各有一套登录相关子路由）；
3. 文案加 `lib/l10n/intl_en.arb`（模板）+ `lib/l10n/intl_zh.arb`，然后
   `flutter gen-l10n`（`lib/l10n/*.dart` 是生成物，已 gitignore）；
4. 改完 `flutter analyze` 要干净，再 `flutter build apk`。

### 同步上游

```powershell
git remote add upstream https://github.com/krille-chan/fluffychat.git   # 只需一次
git fetch upstream
git switch register
git merge upstream/main      # 冲突一般只在本分支改过的那几个文件
```

---

## 6. Git / GitHub

- `origin` = `https://github.com/qmy666999/fluffychat`（fork），`upstream` = 上游官方仓库；
- 本仓库提交身份：`qmy666999 <149899855+qmy666999@users.noreply.github.com>`；
- `gh` CLI：`<workspace>\tools\gh\bin\gh.exe`（已加进 PATH），当前登录账号 `qmy666999`；
  - **再加一个 GitHub 账号**：`gh auth login`（浏览器设备码），
  - 切账号：`gh auth switch`，看当前：`gh auth status`。
- 直连 github.com 不稳定时，本仓库 `.git/config` 里已经写了
  `http.proxy = http://127.0.0.1:7897`（Clash）；代理没开就把这行删掉：
  `git config --unset http.proxy`
