# 小米电视 MiTV4-ANSM0 精简记录

> **只想快速回顾 → 看 [`SUMMARY.md`](SUMMARY.md)**（一页纸）
> **想直接动手 → 看 [`GUIDE.md`](GUIDE.md)**（固定操作流程，照着做即可）
> 本文件是原理说明与实测记录，遇到怪问题再来查。

设备：小米电视4A 55"（`MiTV4-ANSM0`，代号 `xmen`）
系统：Android 6.0.1，固件 `22.2.8.3108`
设备：2 台，`192.168.1.23` / `192.168.1.253`

---

## 一、这台机器能做什么、不能做什么

在固件 `22.2.8.3108` 上实测的结果，和网上大多数教程不一样：

| 操作 | 结果 | 说明 |
|---|---|---|
| `adb root` | ❌ | `adbd cannot run as root in production builds` |
| `pm disable-user --user 0` | ❌ | shell 缺少 `CHANGE_COMPONENT_ENABLED_STATE` |
| `pm hide` | ❌ | shell 缺少 `MANAGE_USERS` |
| `am set-inactive` | ❌ | 静默忽略，`Idle=false` |
| `pm uninstall --user 0` | ✅ 但很慢 | 约 2 分钟，执行完 adbd 会掉线 |
| `pm install` / `install-existing` | ❌ | 挂死；`install-existing` 命令不存在 |
| 会话式 `install-create/write/commit` | ⚠️ | 报 Success，但包在 user 0 仍是已卸载 |
| `settings put` | ✅ | 正常 |
| `appops set` | ✅ | 正常 |

**结论：能卸不能装。卸载是单向操作，唯一回滚是恢复出厂设置。**

之所以恢复出厂能救回来：这 76 个包全部来自 `pm list packages -s`（系统应用），
`/data/app` 里只是它们的更新版本，重置后 `/system` 里的原始版本会重新注册。

---

## 二、已经生效的改动

### 1. 设置层（零风险、可逆）

```bash
./mitv.sh tune
```

- `3rd_app_show_loading_page` 清空 → 干掉第三方视频 App 的 15 秒开屏广告
- `upload_log_pref = 0` → 关闭日志上报
- 6 个广告相关包的 `SYSTEM_ALERT_WINDOW` 设为 deny

### 2. 卸载（不可逆）

```bash
./mitv.sh uninstall <包名...>     # 内部调用 batch-uninstall.sh
```

记录写在 `backup/uninstalled.log`。

**第一批已完成（7 个，2026-10-24）：**

```
com.miui.systemAdSolution                广告 SDK
com.miui.tv.analytics                    观看行为分析
com.mitv.cloudcontrol                    云端推广位下发
com.xm.webcontent                        H5 推广内容
com.duokan.videodaily                    视频日报推荐
com.xiaomi.mitv.tvpush.tvpushservice     推送服务
com.xiaomi.mitv.shop                     小米商城
```

卸载后包总数 84 → 79，桌面正常在前台，无崩溃记录。

---

## 三、开机广告

`/system/media/` 下有：

```
bootanimation.zip          2.0 MB   正常开机动画
bootanimation_rec.zip      730 KB   推荐/广告动画
bootanimation_redmi.zip    2.3 MB
```

`bootanimation_rec.zip` 就是开机广告，在只读分区，**无 root 改不了**。
DNS 拦截也无效——它是本地文件，不走网络。

---

## 四、目录说明

```
mitv.sh                    主脚本
batch-uninstall.sh         逐包卸载（设备端后台执行 + 轮询确认）
packages.candidates.txt    按 4 档分级的包清单
backup/system-*.txt        卸载前的完整包列表
backup/uninstalled.log     已卸载记录
apk/                       拉下来的 APK（万一以后有恢复手段）
```

---

## 五、Aerial TV 桌面（app.orchard.tv）

替换小米 PatchWall 桌面的开源方案（MIT，无广告）。
仓库：https://github.com/pengchujin/aerial-tv

### 这台机器上的特殊情况

小米把 HOME 权限用签名级权限锁死了：

```
am start -a MAIN -c HOME
→ SecurityException: requires com.mitv.tvhome.permission.HOME_STATE
```

`standard` 包装上后，`android.intent.category.HOME` 声明会被 MIUI 剥掉（dumpsys 里 0 条），
所以必须用 **guard 版**：它不声明 HOME，改用无障碍服务 `HomeGuardService` 抢占。

### 已执行的配置

```bash
# 装 guard 版（session 方式，adb install 在本机会挂）
# 权限
pm grant app.orchard.tv android.permission.ACCESS_FINE_LOCATION
pm grant app.orchard.tv android.permission.WRITE_SECURE_SETTINGS
appops set app.orchard.tv SYSTEM_ALERT_WINDOW allow
appops set app.orchard.tv WRITE_SETTINGS allow
# ★ 关键：守护靠 UsageStats 判断前台应用，漏了这条 Home 键永远不接管
appops set app.orchard.tv GET_USAGE_STATS allow
appops set app.orchard.tv android:get_usage_stats allow
# 无障碍（追加，不覆盖原有服务）
settings put secure enabled_accessibility_services "<原有>:app.orchard.tv/app.orchard.tv.guard.HomeGuardService"
settings put secure accessibility_enabled 1
# 通知监听（待机被杀后快速恢复）
settings put secure enabled_notification_listeners app.orchard.tv/app.orchard.tv.guard.RevivalListener
# 自动恢复 ADB（重启后 ADB 被关掉时自动开回来）
am broadcast -a app.orchard.tv.CONFIG -n app.orchard.tv/.guard.ConfigReceiver --ez keep_adb true
```

> **`GET_USAGE_STATS` 是必须的**。第二台电视第一次配的时候漏了这条，
> 现象是：进程正常、守护显示已绑定、但按 Home 30 秒都不回来，
> `AerialDiag` 日志显示 `state CREATED, shown false`。
> 补上授权并重启应用后，5 秒正常接管。

### 实测行为

- 按 Home：先闪 4–5 秒小米桌面，然后 Aerial 接管（稳定复现）
- 待机唤醒后可能需要 30–60 秒才回来（小米会强杀后台，靠同步适配器兜底）
- 守护失灵时：`./mitv.sh home` 强制拉回

### 开机验证（2026-10-24）

重启后实测：

```
前台      app.orchard.tv/.MainActivity   ← 开机直接进 Aerial
进程      u0_a37  3204                   ← 正常运行
守护      已绑定
ADB       5555 自动打开                  ← 当时判断为 keep_adb 生效
按 Home   5 秒后回到 Aerial
```

### ⚠️ 更正：keep_adb 并不能保证重启后 ADB 可用

第二台（`.253`，固件 3352）重启后 **5555 是关的**，查源码后确认原因：

`GuardSetup.ensureAdb()` 的逻辑是：

```kotlin
if (Settings.Global.getInt(resolver, Settings.Global.ADB_ENABLED, 0) == 1) return  // ← 已经是 1，直接返回
Settings.Global.putInt(resolver, Settings.Global.ADB_ENABLED, 1)
```

而开机时 `adb_enabled` **本来就是 1**（小米没重置它），所以 `ensureAdb` 什么都不做。
日志里开机那次也没有 `turned it back on`，只有手动关掉时才出现。

真正缺的是另一个东西：

```
service.adb.tcp.port   重启后为空 → adbd 只监听 USB，不开 5555
sys.set_adb_disabled   = true     → 小米自己的标志位
```

这两个都是**运行时属性**，重启清空；`persist.adb.tcp.port` 是空且 shell 写不了（`setprop` 返回 0 但值不变，SELinux 静默拒绝）。

所以：

| | 重启后 ADB |
|---|---|
| 电视 A（`.23`） | 当时实测是开的（固件行为可能不同） |
| 电视 B（`.253`） | **必须手动开关一次** |

**变通办法**（电视 B 每次重启后）：

```
设置 → 账号与安全 → ADB 调试 → 关 → 等 3 秒 → 开
```

注意：关掉后 Aerial 会在几秒内自动把它改回 1（`AerialGuard: ADB debugging had been switched off; turned it back on`），
所以实际操作是「关一下就行」，不用再点开。

要真正做到免手动，只能 root 后写 `persist.adb.tcp.port`，不在本方案范围内。

### 卸载

```bash
adb shell pm uninstall app.orchard.tv
adb shell settings put secure enabled_accessibility_services "<去掉 Aerial 那段>"
```

---

## 六、常用命令

```bash
./mitv.sh probe            # 电视在线？ADB 端口开了？
./mitv.sh connect          # 连接 + 型号/版本
./mitv.sh backup           # 备份包列表
./mitv.sh find             # 搜广告/商店相关包
./mitv.sh tune             # 设置层优化
./mitv.sh home             # 把 Aerial 拉回前台
./mitv.sh uninstall <包名>  # 卸载（慢，会掉线，自动重连）
./mitv.sh restore-all      # 查看已卸载清单 + 回滚说明
```

---

## 七、注意事项

1. **ADB 在重启后不保证可用**。开关显示"开"也不代表 `adbd` 在监听 5555。
   稳妥做法：去 设置 → 账号与安全 → ADB 调试 **关一下再开**，然后 `adb connect`。
   原因见第五节「keep_adb 并不能保证重启后 ADB 可用」。
2. **授权会过期**。如果 `adb devices` 显示 `unauthorized`，
   在电视弹窗里勾选"一律允许"。
3. **卸载过程中 adbd 会掉线**，这是正常现象，脚本会自动重连。
4. **恢复出厂设置** = 所有卸载的包回来，同时设置层改动也一并还原。

---

## 八、TVBox（com.github.tvbox.osc.jun）

开源空壳播放器，**本身不含任何内容**，需要自己填「配置地址」（接口）才有片源。

### 版本选择（关键）

| 版本 | minSdk | 能否装 |
|---|---|---|
| FongMi 影视 5.8.1 | 24（Android 7.0） | ❌ |
| TVBox q215613905 java32 | **19** | ✅ |

这台机器是 32 位 `armeabi-v7a`（Amlogic `gxbaby`），只能装 `java32` 变体。

### 安装记录

```bash
# 下载（gh.nxnow.top 镜像，189 KB/s；gh-proxy.com 只有 8-24 KB/s）
# sha256 ba4fbd2e371e1a8e606766cd204c2b4b7581a046b3127dce1a5ce3bf02d5ab83
./mitv.sh install apk/tvbox-java32.apk
```

`adb install` 在本机会挂死，`install` 子命令走的是
`install-create / install-write / install-commit` 会话方式。

### 实测

- 启动正常，`HomeActivity` 在前台，无崩溃
- 首页能显示「豆瓣热播」海报（豆瓣元数据，不需要接口）
- 但**点进去播不了**——播放必须要有接口

### 关于接口

- `java32` 只支持 **Java 爬虫（jar）**；如果某个接口用的是 `.py` 爬虫，
  需要换 `python32` 变体（31.6 MB）
- 配置入口：首页 → 设置 → 配置地址
- 不提供、不调试盗版接口


---

## 九、两台电视对照

| | 电视 A | 电视 B |
|---|---|---|
| IP | `192.168.1.23` | `192.168.1.253` |
| 型号 | MiTV4-ANSM0 (`xmen`) | MiTV4-ANSM0 (`xmen`) |
| 系统 | Android 6.0.1 / API 23 | Android 6.0.1 / API 23 |
| 固件 | `22.2.8.3108` | incremental `3352` |
| ABI | `armeabi-v7a` | `armeabi-v7a` |
| 原包数 | 84（系统 76 + 三方 8） | 85（系统 76 + 三方 9） |
| 现包数 | 79 | 76 |
| 系统包备份 | `backup/system-20261024-132852.txt` | `backup/tv2-system-20261024-151324.txt` |
| Aerial | ✅ | ✅ |
| TVBox | ✅ `java32` | ✅ `java32` |

**系统包完全一致**（都是 76 个，逐一 diff 过），所以第一批卸载清单可以直接复用。

### 电视 B 多卸的 3 个

在第一批 7 个之外，额外卸了：

| 包名 | 是什么 |
|---|---|
| `com.mitv.shoplugin` | 有品商城插件 |
| `com.mitv.care` | 米家关怀 |
| `com.xiaomi.mitv.tvvideocall` | 电视视频通话 |

这三个都是 2018–2020 年通过小米应用商店装的增值应用，能从商店重装。

### 电视 B 保留的第三方应用

`com.changba.sd`（唱吧）、`com.dangbeimarket`（当贝市场）、
`com.gitv.dvb.live`（广电直播）、`com.lutongnet.nldmxXiaomiChildren`（宝宝巴士儿童）、
`com.mitv.codec.update`（编解码更新）

都是用户自己装的，一个没动。

### 指定操作哪一台

所有脚本都认 `MITV_IP`：

```bash
MITV_IP=192.168.1.253 ./mitv.sh probe
MITV_IP=192.168.1.253 ./mitv.sh home
MITV_IP=192.168.1.253 ./batch-uninstall.sh <包名...>
```

`backup/uninstalled.log` 现在每条都带设备 IP，`./mitv.sh restore-all` 会按设备分组显示。
