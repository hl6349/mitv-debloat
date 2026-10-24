# APK 说明

本目录**不包含** APK 文件（体积大、且都是第三方开源项目，直接从官方 release 下载更可靠）。

按需下载到本目录，文件名要与脚本里的路径一致。

---

## Aerial TV（桌面）

仓库：https://github.com/pengchujin/aerial-tv

**必须用 guard 版**——`standard` 版的 HOME 声明会被 MIUI 剥掉，详见 `GUIDE.md` 7.1。

```bash
URL="https://github.com/pengchujin/aerial-tv/releases/download/v1.46/aerial-guard.apk"
curl -fL -C - --retry 10 --retry-all-errors -o aerial-guard.apk \
  "https://gh.nxnow.top/$URL"

shasum -a 256 aerial-guard.apk
# 与 release 页面的 sha256 对照
```

安装：

```bash
./mitv.sh install apk/aerial-guard.apk
```

---

## TVBox（可选，空壳播放器）

仓库：https://github.com/j4Uq/TVBoxOSC

**FongMi 5.8.1 要 minSdk 24（Android 7.0），这台电视是 API 23，装不上。**
必须用 q215613905 分支的 `java32` 变体（minSdk 19）。

```bash
URL="https://github.com/j4Uq/TVBoxOSC/releases/download/20260914-1520/TVBox_q215613905_20260914-1520-java32.apk"
curl -fL -C - --retry 10 --retry-all-errors -o tvbox-java32.apk \
  "https://gh.nxnow.top/$URL"

shasum -a 256 tvbox-java32.apk
# 期望 ba4fbd2e371e1a8e606766cd204c2b4b7581a046b3127dce1a5ce3bf02d5ab83
```

---

## 下载慢怎么办

GitHub 直连会被限速到 1.6 KB/s。实测镜像：

| 镜像 | 速度 |
|---|---|
| `gh.nxnow.top` | **189 KB/s** ✅ 首选 |
| `gh-proxy.com` | 8–24 KB/s（不稳定） |
| `ghproxy.net` / `ghfast.top` / `gh.llkk.cc` | 死链 |

`curl -C -` 支持断点续传，镜像中途失效可以直接换一个继续。
