# Pocket App

网页版 [ZCode Pocket](../zcode-pocket) 的 iPhone 原生壳：WebView 加载 Pocket 页面 +
**双通道后台任务通知**（借鉴 limaoswag-wq/ZCodeMobile 的机制，数据源换成 Pocket 自己的接口）。

## 功能

1. **WebView 壳**：首启填一次带 token 的 Pocket 地址（支持局域网/隧道任意地址），设置页可改
2. **桥接通道**：退后台每 20s 轮询电脑 `/api/all_tasks`，任务完成/出错弹系统横幅，点通知直达会话
3. **官方中继通道**：粘贴电脑 ZCode「远程控制」链接配对，退后台自动接管中继连接，
   走 zcode.z.ai 云收桌面任务通知——**任何网络可用**（协议五件套原样复用 ZCodeMobile）
4. **云派任务**：顶栏云朵按钮 → 选桌面工作区 + 输一句话 → 经官方云派出，桌面 ZCode 执行
5. **静音保活**：0 音量极短 WAV 循环（UIBackgroundModes: audio），后台不易被杀

两条通道都有 5 分钟去重闸，同一个任务不会响两遍。

## 构建

Codemagic workflow：`pocket-unsigned-ipa`，产物 `Pocket.ipa`，巨魔安装。

```bash
python3 scripts/gen_xcodeproj.py   # 生成 Xcode 工程
```

## 安装

TrollStore → + → 选择/输入 IPA 地址 → Install（需先在 TrollStore Settings 装 ldid）。

## 目录

```
App/PocketApp.swift            入口 + 通知点击路由
App/AppState.swift             全局状态 + 前后台策略
App/RootView.swift             主页/首启设置/设置页
App/WebView.swift              WKWebView 容器（_blank 链接站内打开）
App/TaskWatcher.swift          桥接通道：轮询 /api/all_tasks
App/RelayMonitor.swift         官方中继通道：配对 + 状态 diff → 通知
App/LocalNotify.swift          本地通知 + 去重闸
App/SilentAudio.swift          静音保活
App/Session/*                  官方中继协议（复用自 ZCodeMobile）
scripts/gen_xcodeproj.py       生成 Xcode 工程
scripts/package_ipa.sh         ldid 伪签 + 打包 IPA
```
