# 朋友圈 & 语音/视频通话 —— 交接文档

这份文档记录**已经查证过的事实**和**已经定下来的设计**，方便换一个新的项目/新的 AI 接着做，
不用再重复调研。构建环境、签名、国内网络那堆坑见同目录 `FORK_NOTES.md`。

---

## 一、已经定下来的产品决策

**朋友圈**

- 每人一个「朋友圈房间」，好友之间互相邀请才能看（接近微信，不是共用一个群）
- 第一版功能：发文字 + 最多 9 张图片、点赞（❤️）、评论（显示在动态下面）、删除/撤回自己的动态
- 第一版不做：短视频、分组可见/不给谁看

**语音/视频通话**

- 走 LiveKit（MatrixRTC / Element Call 那套），群聊和 1:1 都用同一套
- 不采用老的 `m.call.*` P2P 方案（上游已删掉它的 UI，且服务器没有 TURN）

---

## 二、已查证的事实（不要再重复调研）

服务器：`https://qmypc.tail7337aa.ts.net`，**Synapse 1.67**

| 探测 | 结果 |
| --- | --- |
| `GET /_matrix/client/versions` | 只声明到 `v1.2`（无 MSC4143 相关 unstable_features） |
| `GET /.well-known/matrix/client` | 只有 `m.homeserver`，**没有** `org.matrix.msc4143.rtc_foci` |
| `GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports` | `400 M_UNRECOGNIZED` |
| `GET /_matrix/client/v3/register` | `400 M_UNRECOGNIZED`（所以注册页只能直接 POST） |
| `POST /_matrix/client/v3/register` + `{"auth":{"type":"m.login.dummy"}}` | `200`，直接建号 |
| `POST .../register`（不带 auth） | `401` + `{"session":...,"flows":[{"stages":["m.login.dummy"]}]}` |

**通话为什么现在没有按钮**：`lib/pages/chat/chat.dart` 的 `_checkMatrixRtcCallSupport()`
调用 `client.getLiveKitServiceUrls()`，取不到地址就把 `supportLiveKitCalls` 留成 `false`，
聊天页 AppBar 就不显示语音/视频按钮。

`getLiveKitServiceUrls()`（`lib/utils/matrix_live_kit_calls/matrix_live_kit_call.dart`）的取址顺序：

1. `/_matrix/client/unstable/org.matrix.msc4143/rtc/transports`（服务器没实现）
2. `.well-known` 的 `org.matrix.msc4143.rtc_foci`（map 或 list 两种格式都支持）
3. **`AppSettings.fallbackLiveKitInstance`**（客户端兜底设置，`lib/config/setting_keys.dart`）

第 3 条意味着：**不改服务器也能让通话按钮出现**，只要给这个设置写个默认值。

拿到地址后，App 请求 `${livekit_service_url}/sfu/get` 换 LiveKit 的 JWT，再
`lk.Room().connect()`。所以那个地址要指向一个 **Element Call 的 lk-jwt-service 兼容服务**，
不是裸的 LiveKit ws 地址。

已有可复用的通话 UI：`lib/pages/call/call_page.dart`、`call_view_model.dart`、`call_tile.dart`、
`lib/widgets/layouts/call_overlay.dart`（已在 `fluffy_chat_app.dart` 里挂载）。
`CallOverlay` 监听 `Matrix.of(context).activeCallRoomId`，把它设成 roomId 就会弹出通话页。

---

## 三、朋友圈（已实现，v1）

> 状态：**已经写完并编译验证**，代码在 `lib/utils/moments/` 和 `lib/pages/moments/`，
> 详细说明见 `FORK_NOTES.md` 的「朋友圈（Moments）」一节。下面是最终采用的数据模型，
> 和最早的草案有两处不同（标了 ✅ 已实现）。

### 数据模型

- **朋友圈房间**：首次发动态时自动创建
  ```
  client.createRoom(
    preset: CreateRoomPreset.privateChat,
    visibility: Visibility.private,
    name: '朋友圈 · <displayName>',
    topic: 'qivchat.moments',   // 邀请（stripped state）里也能认出这是朋友圈
    invite: [],                 // 之后由用户手动邀请好友
    initialState: [ StateEvent(
        type: 'chat.qiv.moments',
        stateKey: '',
        content: {'version': 1},
    ) ],
  )
  ```
  这个自定义 state 事件就是「这是一个朋友圈房间」的标记，不需要服务器支持（普通 state 事件）。
- **发现**：遍历 `client.rooms`，带 `chat.qiv.moments` state（或 topic 是 `qivchat.moments`）的都算。
  自己的房间 = owner 是自己；好友的房间 = 别人邀请自己进去的。
- **动态** ✅：**普通 `m.room.message`**（不是自定义类型，兼容性最好），图片放在自定义字段里：
  ```json
  {"msgtype": "m.text", "body": "文字内容", "qiv.moments.images": ["mxc://..."]}
  ```
  只渲染**房间创建者**发、且不带 `m.relates_to` 的消息（这样房主在评论区回复也不会变成新动态）。
- **点赞** ✅：标准 `m.reaction`，`m.relates_to: {rel_type: "m.annotation", event_id: <动态>, key: "❤️"}`
- **评论** ✅：标准 `m.thread` 回复（`m.relates_to.rel_type = "m.thread"`）
- **删除** ✅：`room.redactEvent(eventId)`（自己的动态/评论）
- **图片** ✅：`client.uploadContent(bytes, filename:)` → mxc，最多 9 张，发布时先按 1600px 压缩

**实测结论（Synapse 1.67）**：自定义 state、topic、消息自定义字段、`m.reaction`、`m.thread`、
redact 全部可用；但 `/relations` 接口**不存在**（400），所以聚合点赞/评论是自己扫房间时间线做的。

### UI

- 入口 ✅：聊天列表左下角相机小 FAB + 左上角头像菜单里的「朋友圈」，路由 `/moments`、`/moments/compose`
- 页面拆三个：

  - `moments_moments_page`：信息流（按 `getTimeline`/`room.getTimeline` 拉，倒序，分页）
  - `moments_compose_page`：输入文字 + 选图 + 发布
  - `moments_detail_page`：单条动态 + 评论列表 + 输入框
- 权限：房主才有「发动态」入口；所有人都能点赞/评论

### 需要注意的坑

- **别开加密**：朋友圈房间建议明文房间（对好友公开性质），否则图片和跨设备密钥共享会很难受。
  如果坚持加密，要处理 `shareKeysWith` 和成员变化时的密钥轮转。
- 房间的 `m.room.power_levels` 默认允许所有成员 `send_message`，评论能直接发；
  但「发动态」要在客户端按 `sender == room.creatorId` 过滤。
- 邀请好友进朋友圈房间 = 「加好友看朋友圈」这个动作，最好在好友资料页/房间成员页加一个
  「邀请他看我朋友圈」的入口，并允许反过来让对方邀请你。

---

## 四、通话（LiveKit）落地步骤

1. 在 `qmypc` 上跑 **livekit-server**（默认 ws 7880、udp 7881）
2. 跑一个 **`/sfu/get` 兼容的令牌服务**：
   - 直接用 Element Call 的 `lk-jwt-service`（Go），或
   - 自己写个小服务：拿 App 传来的 Matrix OpenID token → 调 homeserver 的
     `/_matrix/client/v3/openid/userinfo` 验证 → 用 LiveKit 的 API key/secret 签 JWT 返回
     `{url, jwt}`
3. 用 **Tailscale 证书** 暴露 https（App 里没开 `usesCleartextTraffic`，ws:// 会失败）
4. App 侧二选一：
   - `AppSettings.fallbackLiveKitInstance` 默认值写 `https://<tailscale-host>:<port>`
     （`lib/config/setting_keys.dart`，一行改完就能出按钮），或者
   - 服务器 `.well-known/matrix/client` 加
     `"org.matrix.msc4143.rtc_foci": {"livekit_service_url": "https://..."}`
5. 验证：聊天页出现电话/摄像机按钮 → 两端能互相接通、能开关摄像头/麦克风

> Synapse 1.67 能存 `org.matrix.msc3401.call.member` 这类 state 事件（就是普通 state），
> 所以 1:1 和群通话都不需要升级服务器；真正缺的只是 LiveKit + 令牌服务。

---

## 五、这个分支现在有什么

- 应用内注册（`lib/pages/register/`，单次 `POST /register` + 自动登录，错误显示状态码+原文）
- 品牌：应用名/桌面名 `QIVchat`，新图标，应用内 logo 也换了
- 构建/签名/镜像/代理的一堆坑都写在 `FORK_NOTES.md` 里
