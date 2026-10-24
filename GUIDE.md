# 小米电视纯净版改造 · 固定操作指南

> 一页纸速览见 [`SUMMARY.md`](SUMMARY.md)；原理与实测记录见 [`README.md`](README.md)。

> 已验证设备：**MiTV4-ANSM0 ×2**（`192.168.1.23`、`192.168.1.253`）
> 目标：换掉广告桌面、清掉广告组件、精简预装。**不刷机、不 root。**

---

## 0. 适用范围

| 项 | 值 |
|---|---|
| 型号 | `MiTV4-ANSM0`（代号 `xmen`） |
| 系统 | Android 6.0.1 / API 23 |
| ABI | `armeabi-v7a`（32 位） |
| 平台 | Amlogic `gxbaby` |
| 已验证固件 | `22.2.8.3108`、incremental `3352` |
| 原包数 | 84–85（系统 76 + 三方 8–9） |

**换成别的型号能用吗？** 流程能用，包名必须重新核对。不要照抄清单直接卸。

---

## 1. 前置条件

```bash
# 电脑
brew install android-platform-tools

# 电视
设置 → 账号与安全 → ADB 调试 → 打开（同意条款）
```

电视和电脑必须在同一网段。首次连接时电视会弹「是否允许 USB 调试」，
**勾选「一律允许使用这台计算机进行调试」**再点确定。

---

## 2. 全流程一览

| 阶段 | 动作 | 可逆 | 耗时 |
|---|---|---|---|
| 0 | 连接 + 体检 | — | 2 min |
| 1 | 备份包清单 | — | 1 min |
| 2 | 设置层优化 | ✅ 可逆 | 1 min |
| 3 | 卸载广告包 | ❌ 不可逆 | 15–22 min |
| 4 | 装 Aerial 桌面 | ✅ 可卸载 | 8 min |
| 5 | 装 TVBox（可选） | ✅ 可卸载 | 5 min |
| 6 | 验收 | — | 3 min |

**顺序不能换**：先做可逆的（2），再做不可逆的（3），最后装应用（4/5）。
装完应用再卸包会打断桌面进程，验证起来更麻烦。

---

## 3. 阶段 0 · 连接与体检

```bash
cd ~/Desktop/mitv-debloat
export MITV_IP=192.168.1.253        # 换成目标电视

./mitv.sh probe                     # 6095/5555 端口通不通
./mitv.sh connect                   # 连接 + 型号/版本
```

体检要拿到四样东西：

```bash
adb -s $MITV_IP:5555 shell getprop ro.product.model
adb -s $MITV_IP:5555 shell getprop ro.build.version.sdk
adb -s $MITV_IP:5555 shell getprop ro.product.cpu.abi
adb -s $MITV_IP:5555 shell pm list packages | wc -l
```

**如果 `unauthorized`**：去电视上点允许。
**如果 `Connection refused`**：去电视把 ADB 开关**关一下再开**（见第 11 节）。

---

## 4. 阶段 1 · 备份（不可跳过）

```bash
./mitv.sh backup
```

产出 `backup/system-<时间戳>.txt` 和 `third-<时间戳>.txt`。

**再做一步差集**——这是判断能不能复用清单的关键：

```bash
# 拿一台已验证的电视做基准
diff <(sed 's/^package://' backup/system-20261024-132852.txt | sort) \
     <(sed 's/^package://' backup/tv2-system-20261024-151324.txt | sort)
```

两台 MiTV4 的系统包 **76 个完全一致**，所以清单可以照搬。
如果差集里出现新的广告类包，单独评估，别硬套。

---

## 5. 阶段 2 · 设置层优化（可逆，先做）

```bash
./mitv.sh tune
```

做三件事：

| 设置 | 值 | 作用 |
|---|---|---|
| `global 3rd_app_show_loading_page` | `com.none.placeholder` | 清空第三方 App 的 15 秒开屏广告 |
| `secure upload_log_pref` | `0` | 关日志上报 |
| 6 个广告包的 `SYSTEM_ALERT_WINDOW` | `deny` | 掐掉悬浮窗广告 |

这一步纯设置层，随时能改回去，**先做**。

---

## 6. 阶段 3 · 卸载广告包（不可逆）

### 6.1 已验证安全清单（10 个）

前 7 个两台都跑过，后 3 个在第二台跑过：

```bash
./batch-uninstall.sh \
  com.miui.systemAdSolution \
  com.miui.tv.analytics \
  com.mitv.cloudcontrol \
  com.xm.webcontent \
  com.duokan.videodaily \
  com.xiaomi.mitv.tvpush.tvpushservice \
  com.xiaomi.mitv.shop \
  com.mitv.shoplugin \
  com.mitv.care \
  com.xiaomi.mitv.tvvideocall
```

| 包名 | 作用 |
|---|---|
| `com.miui.systemAdSolution` | 小米广告 SDK（核心） |
| `com.miui.tv.analytics` | 观看行为分析 |
| `com.mitv.cloudcontrol` | 云端配置下发（推广位来源） |
| `com.xm.webcontent` | H5 推广页 |
| `com.duokan.videodaily` | 多看视频日报（推荐位） |
| `com.xiaomi.mitv.tvpush.tvpushservice` | 推送服务 |
| `com.xiaomi.mitv.shop` | 小米商城 |
| `com.mitv.shoplugin` | 有品商城插件 |
| `com.mitv.care` | 米家关怀 |
| `com.xiaomi.mitv.tvvideocall` | 电视视频通话 |

### 6.2 执行细节

- 每个包约 **2 分钟**，10 个约 22 分钟
- 卸载过程中 **adbd 会掉线**，脚本会自动重连
- 必须阻塞式等待，**不能**丢到设备端后台（子进程会被回收）
- 跑完检查 `backup/uninstalled.log`，每条带设备 IP

### 6.3 未验证的候选

`packages.candidates.txt` 里第 2、3 档还有约 25 个（游戏中心、支付、天气、
日历、相册、屏保、K 歌、米家…）。**收益递减**：桌面已经换成 Aerial 之后，
这些应用在首页根本看不到。建议先用几天再决定。

⚠️ `com.mitv.screensaver`（屏保）卸了会变成待机直接黑屏，慎动。

---

## 7. 阶段 4 · 装 Aerial 桌面

仓库：https://github.com/pengchujin/aerial-tv （MIT，无广告）

### 7.1 为什么必须用 guard 版

小米用签名级权限锁死了 HOME：

```
am start -a MAIN -c HOME
→ SecurityException: requires com.mitv.tvhome.permission.HOME_STATE
```

`standard` 包装上后，`android.intent.category.HOME` 声明会被 MIUI **剥掉**
（`dumpsys` 里 0 条），所以必须用 **guard 版**——它不声明 HOME，
改用无障碍服务 `HomeGuardService` 抢占。

### 7.2 下载

GitHub 直连会被限速到 1.6 KB/s。可用镜像（实测速度）：

| 镜像 | 速度 |
|---|---|
| `gh.nxnow.top` | **189 KB/s** ✅ 首选 |
| `gh-proxy.com` | 8–24 KB/s（不稳定） |
| `ghproxy.net` / `ghfast.top` / `gh.llkk.cc` | 死链 |

```bash
URL="https://github.com/pengchujin/aerial-tv/releases/download/v1.46/aerial-guard.apk"
curl -fL -C - --retry 10 --retry-all-errors -o apk/aerial-guard.apk \
  "https://gh.nxnow.top/$URL"
shasum -a 256 apk/aerial-guard.apk
```

APK 已在本地（`apk/aerial-guard.apk`，2.8 MB），一般不用重下。

### 7.3 安装

```bash
./mitv.sh install apk/aerial-guard.apk
```

**不要用 `adb install`**——这台机器上会挂死。`install` 子命令走的是
`install-create / install-write / install-commit` 会话方式。

### 7.4 配置（6 步，缺一不可）

```bash
A() { adb -s $MITV_IP:5555 shell "$@"; }
PKG=app.orchard.tv

# 1. 权限
A "pm grant $PKG android.permission.ACCESS_FINE_LOCATION"
A "pm grant $PKG android.permission.WRITE_SECURE_SETTINGS"
A "appops set $PKG SYSTEM_ALERT_WINDOW allow"
A "appops set $PKG WRITE_SETTINGS allow"

# 2. ★ 关键：守护靠 UsageStats 判断前台应用
A "appops set $PKG GET_USAGE_STATS allow"
A "appops set $PKG android:get_usage_stats allow"

# 3. 无障碍（追加，不覆盖小米自己的服务）
CUR=$(A 'settings get secure enabled_accessibility_services')
A "settings put secure enabled_accessibility_services '$CUR:$PKG/$PKG.guard.HomeGuardService'"
A 'settings put secure accessibility_enabled 1'

# 4. 通知监听（待机被杀后快速恢复）
A "settings put secure enabled_notification_listeners '$PKG/$PKG.guard.RevivalListener'"

# 5. 自动恢复 ADB
A "am broadcast -a $PKG.CONFIG -n $PKG/.guard.ConfigReceiver --ez keep_adb true"

# 6. 启动
A "am start -W -n $PKG/.MainActivity"
```

> **第 2 步最容易漏。** 漏了的现象：进程正常、守护显示已绑定、
> 但按 Home 30 秒都不回来，`AerialDiag` 日志显示 `state CREATED, shown false`。
> 补上授权 + 重启应用即恢复。

### 7.5 验证

```bash
A 'dumpsys accessibility | grep -c "Aerial 桌面守护"'   # 应为 1
A 'input keyevent 3'                                    # 模拟按 Home
sleep 5
A 'dumpsys activity activities | grep -m1 mFocusedActivity'   # 应为 app.orchard.tv
```

正常表现：**先闪 4–5 秒小米桌面，然后 Aerial 接管**。

---

## 8. 阶段 5 · 装 TVBox（可选）

开源空壳播放器，**本身不含任何内容**，需要自己填接口才有片源。

### 8.1 版本选择（关键）

| 版本 | minSdk | 能否装 |
|---|---|---|
| FongMi 影视 5.8.1（最主流分支） | 24 = Android 7.0 | ❌ |
| TVBox q215613905 `java32` | **19** | ✅ |

这台是 32 位 `armeabi-v7a`，只能装 `java32` 变体（19.8 MB）。

```bash
URL="https://github.com/j4Uq/TVBoxOSC/releases/download/20260914-1520/TVBox_q215613905_20260914-1520-java32.apk"
curl -fL -C - --retry 10 --retry-all-errors -o apk/tvbox-java32.apk \
  "https://gh.nxnow.top/$URL"
# sha256 应为 ba4fbd2e371e1a8e606766cd204c2b4b7581a046b3127dce1a5ce3bf02d5ab83

./mitv.sh install apk/tvbox-java32.apk
```

### 8.2 限制

- `java32` 只支持 **Java 爬虫（jar）**。接口若用 `.py` 爬虫需换 `python32`（31.6 MB）
- 首页的「豆瓣热播」是豆瓣元数据，**不需要接口**，但点进去播不了
- 配置入口：首页 → 设置 → 配置地址
- 不提供、不调试盗版接口

---

## 9. 阶段 6 · 验收清单

逐项打勾：

```bash
A() { adb -s $MITV_IP:5555 shell "$@"; }

# 1. 包数下降（85 → 75 左右，装了两个应用后 77）
A 'pm list packages | wc -l'

# 2. Aerial 在前台
A 'dumpsys activity activities | grep -m1 mFocusedActivity'

# 3. 守护已绑定
A 'dumpsys accessibility | grep -c "Aerial 桌面守护"'

# 4. 内存
A 'grep MemAvailable /proc/meminfo'

# 5. 无崩溃
A 'logcat -d -b crash | tail -20'

# 6. 设置层生效
A 'settings get global 3rd_app_show_loading_page'   # com.none.placeholder
A 'settings get secure upload_log_pref'             # 0

# 7. Home 键接管
A 'input keyevent 3'
```

**合格线**：Aerial 在前台、守护=1、崩溃记录为空、Home 键 5 秒内接管。

最后**重启一次**，确认开机直接进 Aerial。

---

## 10. 回滚

```bash
./mitv.sh restore-all      # 查看两台设备各自卸了什么
```

**没有逐包恢复的手段。** 这台机器上：

- `pm install-existing` 不存在
- `pm install -r`（/data/app、/sdcard 两种路径）、`pm install --user 0`、
  会话式 `install-create/write/commit` 对已卸载的系统包全部无效或挂死

**唯一回滚方式：设置 → 恢复出厂设置。** 所有包从 `/system` 重新装回，
设置层改动也一并还原（Aerial/TVBox 这类三方应用会保留）。

---

## 11. 故障速查表

| 现象 | 原因 | 解法 |
|---|---|---|
| `unauthorized` | 没授权这台电脑 | 电视弹窗勾「一律允许」 |
| `Connection refused` / 5555 不通 | `service.adb.tcp.port` 重启清空 | 电视 ADB 开关**关一下**（Aerial 会自动改回 1） |
| `adb install` 卡住不动 | 固件 `pm install` 挂死 | 用 `./mitv.sh install` |
| `pm disable-user` 报 SecurityException | uid=2000 改不了 uid=1000 的包 | 改用 `pm uninstall --user 0` |
| `pm hide` 报缺 MANAGE_USERS | shell 无此权限 | 同上 |
| `pm uninstall` 要 2 分钟且掉线 | 固件行为 | 阻塞等待 + 自动重连（脚本已处理） |
| 装完 Aerial 按 Home 不回来 | 漏了 `GET_USAGE_STATS` | 补授权 + 重启应用 |
| `am start -c HOME` 报 HOME_STATE | 小米签名级权限锁死 | 必须用 guard 版 |
| Aerial 首页正常但 `standard` 版没 HOME | MIUI 剥掉 HOME 声明 | 换 guard 版 |
| GitHub 下载 1.6 KB/s | 限速 | 用 `gh.nxnow.top` 镜像 |
| FongMi 装不上（OLDER_SDK） | minSdk 24 | 换 TVBox `java32` |
| `setprop persist.adb.tcp.port` 无效 | SELinux 静默拒绝 | 无解（需 root） |

---

## 12. 已知做不到的事

1. **开机广告去不掉**。它是本地文件 `/system/media/bootanimation_rec.zip`（729 KB），
   无 root 无法修改，DNS 拦截也无效。
2. **按 Home 会闪 4–5 秒小米桌面**。小米桌面禁不掉（禁了白屏），
   这是 Android 6 + MIUI 的固有延迟。
3. **待机唤醒后可能 30–60 秒才回 Aerial**。小米会强杀后台，靠同步适配器兜底。
   等太久就 `./mitv.sh home` 强制拉回。
4. **ADB 重启后不保证可用**。开关显示"开"不等于 `adbd` 在监听 5555，
   需要关一下开关。详见 README 第五节。
5. **`adb root` 不可用**：`adbd cannot run as root in production builds`。
6. **卸载不可逆**，只能恢复出厂。

---

## 13. 新增一台电视的最短路径

```bash
cd ~/Desktop/mitv-debloat
export MITV_IP=<新电视IP>

./mitv.sh probe && ./mitv.sh connect
./mitv.sh backup

# 差集核对（关键，别跳）
diff <(sed 's/^package://' backup/system-20261024-132852.txt | sort) \
     <(ls -t backup/*system-*.txt | head -1 | xargs sed 's/^package://' | sort)

./mitv.sh tune

./batch-uninstall.sh \
  com.miui.systemAdSolution com.miui.tv.analytics com.mitv.cloudcontrol \
  com.xm.webcontent com.duokan.videodaily com.xiaomi.mitv.tvpush.tvpushservice \
  com.xiaomi.mitv.shop

./mitv.sh install apk/aerial-guard.apk
# → 按 7.4 配 6 步（别忘了 GET_USAGE_STATS）
# → 按第 9 节验收
```

预计 **35 分钟**一台（其中 15 分钟在等卸载）。

---

## 14. 目录说明

```
mitv.sh                    主脚本：probe/connect/backup/tune/install/home/list/uninstall/restore-all
batch-uninstall.sh         逐包卸载（阻塞等待 + 掉线重连 + 三态判断）
packages.candidates.txt    4 档分级的真实包名清单
GUIDE.md                   本文件
README.md                  完整实测记录与原理说明
apk/                       Aerial guard/standard、TVBox java32
backup/                    包清单备份 + uninstalled.log（带设备 IP）
```

---

*最后更新：2026-10-24，验证设备 2 台*
