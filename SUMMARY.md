# 工作流程速览（一页纸）

> 详细步骤见 [`GUIDE.md`](GUIDE.md)；原理与实测记录见 [`README.md`](README.md)。
> 本文件是给"明天就上手"用的。

设备：小米电视4A 55"（`MiTV4-ANSM0` / `xmen` / Android 6.0.1 / `armeabi-v7a`）
已完成：2 台（`192.168.1.23`、`192.168.1.253`）

---

## 六阶段流程

| 阶段 | 动作 | 可逆 | 耗时 |
|---|---|---|---|
| 0 | 连接 + 体检 | — | 2 min |
| 1 | 备份 + **差集核对** | — | 1 min |
| 2 | 设置层优化 | ✅ | 1 min |
| 3 | 卸载广告包 | ❌ | 15–22 min |
| 4 | 装 Aerial 桌面 | ✅ | 8 min |
| 5 | 装 TVBox（可选） | ✅ | 5 min |
| 6 | 验收 + 重启验证 | — | 3 min |

**顺序不能换**：先可逆（2），再不可逆（3），最后装应用（4/5）。
装完应用再卸包会打断桌面进程，验证起来更乱。

**一台电视 35 分钟**，其中 15 分钟在等卸载。

---

## 最容易被跳过、但最不能跳的一步

阶段 1 的差集核对：

```bash
diff <(sed 's/^package://' backup/system-20261024-132852.txt | sort) \
     <(ls -t backup/*system-*.txt | head -1 | xargs sed 's/^package://' | sort)
```

第二台能一次过，就是因为这一步确认了 **76 个系统包完全一致**。
直接照抄清单的话，遇到包集不同的固件就会漏判——该卸的没卸、不该动的动了。

---

## 今天踩到的 4 个真问题

### ① `GET_USAGE_STATS` 漏授权（最坑）

现象：进程正常、守护显示已绑定、但按 Home 30 秒不回来，
`AerialDiag` 日志显示 `state CREATED, shown false`。

原因：Home Guard 靠 UsageStats 判断前台应用，没这权限就永远认为"没变化"。

```bash
appops set app.orchard.tv GET_USAGE_STATS allow
appops set app.orchard.tv android:get_usage_stats allow
```

### ② `keep_adb` 不是万能药

我一开始归因错了。读源码才发现 `GuardSetup.ensureAdb()` 开头就是：

```kotlin
if (Settings.Global.getInt(resolver, ADB_ENABLED, 0) == 1) return
```

而开机时它本来就是 1，所以什么也没做。真正缺的是 `service.adb.tcp.port`
（运行时属性，重启清空）。**没有 root 无解。**

变通：重启后把 ADB 开关**关一下**即可，Aerial 会自动把它改回 1。

### ③ `standard` 版 Aerial 装上后 HOME 声明被 MIUI 剥掉

`dumpsys` 里 0 条 `android.intent.category.HOME`。必须用 **guard 版**，
走无障碍服务 `HomeGuardService` 抢占。

### ④ GitHub 全局限速 1.6 KB/s

实测镜像速度：

| 镜像 | 速度 |
|---|---|
| `gh.nxnow.top` | **189 KB/s** ✅ 首选 |
| `gh-proxy.com` | 8–24 KB/s（不稳定） |
| `ghproxy.net` / `ghfast.top` / `gh.llkk.cc` | 死链 |

下载用 `curl -fL -C - --retry 10 --retry-all-errors`，断了能续。

---

## 两张速查表（详见 GUIDE）

**故障速查表**（12 条）：`unauthorized`、`Connection refused`、`adb install` 卡死、
`SecurityException uid=2000`、`HOME_STATE` 权限、`OLDER_SDK`…

**已知做不到的事**（6 条）：

- 开机广告（`/system/media/bootanimation_rec.zip`，无 root 改不了）
- Home 键闪 4–5 秒小米桌面
- 待机唤醒 30–60 秒才回 Aerial
- ADB 重启后不保证可用
- `adb root` 不可用
- 卸载不可逆，只能恢复出厂

---

## 下次新增一台电视

```bash
cd ~/Desktop/mitv-debloat
export MITV_IP=<新电视IP>

./mitv.sh probe && ./mitv.sh connect
./mitv.sh backup
# 差集核对（别跳）
./mitv.sh tune
./batch-uninstall.sh <已验证的包名>
./mitv.sh install apk/aerial-guard.apk
# 按 GUIDE 7.4 配 6 步（别忘了 GET_USAGE_STATS）
# 按 GUIDE 第 9 节验收
```

型号不同的话：**流程能用，包名必须重新核对。**

---

## 目录

```
SUMMARY.md               一页纸速览（本文件）
GUIDE.md                 照着做的完整流程（422 行）
README.md                原理说明 + 实测记录
mitv.sh                  主脚本
batch-uninstall.sh       逐包卸载
packages.candidates.txt  4 档包名清单
apk/                     离线 APK（Aerial guard/standard、TVBox java32）
backup/                  包清单 + uninstalled.log（带设备 IP）
```

---

*2026-10-24*
