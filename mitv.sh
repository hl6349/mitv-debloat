#!/usr/bin/env bash
# 小米电视去广告 / 精简预装 —— 可逆 ADB 脚本
# 用法见末尾 usage()

set -o pipefail

ADB="${ADB:-adb}"
IP="${MITV_IP:-192.168.1.23}"
PORT="${MITV_PORT:-5555}"
TARGET="$IP:$PORT"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HERE/backup"
NOW="$(date +%Y%m%d-%H%M%S)"
DISABLED_LOG="$BACKUP_DIR/disabled.log"

c_red()  { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }

need_adb() {
  command -v "$ADB" >/dev/null 2>&1 || {
    c_red "找不到 adb。请先安装：brew install android-platform-tools"
    exit 1
  }
}

# 必须保留的包，永远不允许禁用
GUARD=" com.android.systemui com.android.settings com.android.packageinstaller \
com.android.providers.settings com.android.providers.media com.android.providers.downloads \
com.android.bluetooth com.android.inputmethod.latin "

guard_check() {
  local pkg="$1"
  case "$GUARD" in
    *" $pkg "*) c_red "拒绝：$pkg 属于系统关键组件，禁用会开不了机/白屏"; return 1 ;;
  esac
  case "$pkg" in
    com.mitv.tvhome|*tvhome*|*launcher*|*Launcher*)
      c_red "拒绝：$pkg 是桌面启动器，禁用会白屏"; return 1 ;;
  esac
  return 0
}

conn() {
  need_adb
  "$ADB" connect "$TARGET" >/dev/null 2>&1 || true
  local state
  state="$("$ADB" -s "$TARGET" get-state 2>/dev/null | tr -d '\r' || true)"
  if [ "$state" != "device" ]; then
    c_red "❌ 连不上 $TARGET（state=${state:-none}）"
    echo "   排查顺序："
    echo "   1. 电视是否开机（待机状态 ping 不通）"
    echo "   2. 设置 → 账号与安全 → ADB 调试 是否已打开"
    echo "   3. 电脑是否和电视同一网段（本机: $(ipconfig getifaddr en1 2>/dev/null || echo 未知)）"
    echo "   4. 电视屏幕上是否弹出了「允许调试」授权框"
    echo "   5. 路由器是否开了 AP 隔离 / 访客网络"
    exit 1
  fi
  c_grn "✅ 已连接 $TARGET"
}

case "${1:-}" in
  probe)
    # 不需要 adb 也能跑：判断电视是否在线、ADB 端口是否打开
    if nc -z -G 2 "$IP" 6095 2>/dev/null; then
      c_grn "✅ $IP 在线（6095 小米电视服务端口已响应）"
    else
      c_red "❌ $IP 的 6095 端口无响应：电视可能关机/待机，或 IP 变了"
    fi
    if nc -z -G 2 "$IP" "$PORT" 2>/dev/null; then
      c_grn "✅ ADB 端口 $PORT 已打开，可以 connect"
    else
      c_red "❌ ADB 端口 $PORT 未打开 → 电视上还没真正启用「ADB 调试」"
      echo "   设置 → 账号与安全 → ADB 调试 → 打开（同意条款）"
      echo "   若已打开仍不通：彻底关机再开机（遥控器长按电源→关机），不要只待机"
    fi
    ;;

  tune)
    # 设置层优化：不需要组件管理权限，这台机器上唯一真正生效的一类改动
    conn
    "$ADB" -s "$TARGET" shell 'settings put global 3rd_app_show_loading_page com.none.placeholder' >/dev/null 2>&1
    "$ADB" -s "$TARGET" shell 'settings put secure upload_log_pref 0' >/dev/null 2>&1
    for p in com.miui.systemAdSolution com.xiaomi.mitv.tvpush.tvpushservice \
             com.mitv.cloudcontrol com.xm.webcontent com.duokan.videodaily com.miui.tv.analytics; do
      "$ADB" -s "$TARGET" shell "appops set $p SYSTEM_ALERT_WINDOW deny" >/dev/null 2>&1
    done
    c_grn "✅ 设置层优化已应用（开屏广告 / 日志上报 / 悬浮窗广告）"
    ;;

  uninstall)
    shift
    [ $# -gt 0 ] || { c_red "用法: $0 uninstall <包名> [包名...]"; exit 1; }
    exec "$HERE/batch-uninstall.sh" "$@"
    ;;

  home)
    # 把 Aerial 拉回前台（Home Guard 失灵时用）
    conn
    "$ADB" -s "$TARGET" shell am force-stop app.orchard.tv >/dev/null 2>&1
    sleep 2
    "$ADB" -s "$TARGET" shell am start -W -n app.orchard.tv/.MainActivity 2>&1 | tr -d '\r' | head -3
    c_grn "✅ 已把 Aerial 拉回前台"
    ;;

  install)
    # 本机的 adb install 会挂死，改用 install-create/write/commit 会话方式
    shift
    apk="$1"
    [ -n "$apk" ] || { c_red "用法: $0 install <apk 路径>"; exit 1; }
    [ -f "$apk" ] || { c_red "找不到文件: $apk"; exit 1; }
    conn

    before="$("$ADB" -s "$TARGET" shell pm list packages -3 2>/dev/null | tr -d '\r' | sort)"

    size="$(stat -f%z "$apk" 2>/dev/null || stat -c%s "$apk")"
    remote="/sdcard/$(basename "$apk")"
    c_ylw "→ 推送 $(basename "$apk")（$((size / 1024)) KB）"
    "$ADB" -s "$TARGET" push "$apk" "$remote" >/dev/null 2>&1 || { c_red "推送失败"; exit 1; }

    out="$("$ADB" -s "$TARGET" shell "pm install-create -r -S $size" 2>&1 | tr -d '\r')"
    sid="$(echo "$out" | grep -o '\[[0-9]*\]' | tr -d '[]')"
    [ -n "$sid" ] || { c_red "创建安装会话失败: $out"; exit 1; }

    "$ADB" -s "$TARGET" shell "pm install-write -S $size $sid base '$remote'" >/dev/null 2>&1 \
      || { c_red "写入失败"; exit 1; }

    c_ylw "→ 提交安装（可能要 1-2 分钟）"
    perl -e 'alarm 240; exec @ARGV' "$ADB" -s "$TARGET" shell "pm install-commit $sid" 2>&1 | tr -d '\r'
    "$ADB" -s "$TARGET" shell "rm -f '$remote'" >/dev/null 2>&1

    sleep 2
    after="$("$ADB" -s "$TARGET" shell pm list packages -3 2>/dev/null | tr -d '\r' | sort)"
    new="$(comm -13 <(echo "$before") <(echo "$after") | sed 's/^package://')"
    if [ -n "$new" ]; then
      c_grn "✅ 新装: $(echo "$new" | tr '\n' ' ')"
    else
      c_ylw "⚠️  包列表没变化（可能是覆盖安装，或安装未真正生效）"
      echo "   查一下: $0 list <关键字>"
    fi
    ;;

  connect)
    conn
    "$ADB" -s "$TARGET" shell getprop ro.build.version.release | tr -d '\r' | sed 's/^/   Android 版本: /'
    "$ADB" -s "$TARGET" shell getprop ro.product.model | tr -d '\r' | sed 's/^/   型号: /'
    ;;

  backup)
    conn
    mkdir -p "$BACKUP_DIR"
    "$ADB" -s "$TARGET" shell pm list packages -s | tr -d '\r' | sort > "$BACKUP_DIR/system-$NOW.txt"
    "$ADB" -s "$TARGET" shell pm list packages -3 | tr -d '\r' | sort > "$BACKUP_DIR/third-$NOW.txt"
    c_grn "✅ 备份完成：$BACKUP_DIR/system-$NOW.txt ($(wc -l < "$BACKUP_DIR/system-$NOW.txt" | tr -d ' ') 个)"
    ;;

  list)
    conn
    "$ADB" -s "$TARGET" shell pm list packages | tr -d '\r' | sed 's/^package://' | sort | grep -i -- "${2:-.}"
    ;;

  find)
    conn
    "$ADB" -s "$TARGET" shell pm list packages | tr -d '\r' | sed 's/^package://' \
      | grep -iE 'ad|adver|recommend|shop|store|game|mall|push|promot' | sort
    ;;

  disable|enable)
    action="${1}"; shift
    [ $# -gt 0 ] || { c_red "用法: $0 $action <包名> [包名...]"; exit 1; }
    conn
    mkdir -p "$BACKUP_DIR"
    rc=0
    for pkg in "$@"; do
      pkg="${pkg%%#*}"; pkg="$(echo "$pkg" | xargs)"
      [ -n "$pkg" ] || continue
      guard_check "$pkg" || { rc=1; continue; }

      if ! "$ADB" -s "$TARGET" shell pm list packages | tr -d '\r' | grep -qx "package:$pkg"; then
        c_ylw "跳过：$pkg 不存在于该机型"
        continue
      fi

      if [ "$action" = "disable" ]; then
        if "$ADB" -s "$TARGET" shell pm disable-user --user 0 "$pkg" 2>&1 | tr -d '\r' | grep -qi "disabled-user"; then
          c_grn "✔ 已禁用 $pkg"; echo "$pkg" >> "$DISABLED_LOG"
        elif "$ADB" -s "$TARGET" shell pm hide "$pkg" 2>&1 | tr -d '\r' | grep -qi "hidden"; then
          c_grn "✔ 已隐藏 $pkg (pm hide)"; echo "hide:$pkg" >> "$DISABLED_LOG"
        else
          c_red "✘ 失败 $pkg"; rc=1
        fi
      else
        "$ADB" -s "$TARGET" shell pm enable "$pkg" >/dev/null 2>&1
        "$ADB" -s "$TARGET" shell pm unhide "$pkg" >/dev/null 2>&1
        c_grn "✔ 已恢复 $pkg"
      fi
    done
    exit $rc
    ;;

  disable-file)
    f="${2:-$HERE/packages.candidates.txt}"
    [ -f "$f" ] || { c_red "找不到文件 $f"; exit 1; }
    pkgs=()
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs)"
      [ -n "$line" ] && pkgs+=("$line")
    done < <(grep -vE '^[[:space:]]*(#|$)' "$f")
    if [ ${#pkgs[@]} -eq 0 ]; then
      c_ylw "文件里没有启用的包（全部被 # 注释了）。先编辑 $f 再跑。"
      exit 0
    fi
    echo "将禁用以下 ${#pkgs[@]} 个包："
    printf '  - %s\n' "${pkgs[@]}"
    printf '确认执行？[y/N] '
    read -r ans
    [ "$ans" = "y" ] || { echo "已取消"; exit 0; }
    exec "$0" disable "${pkgs[@]}"
    ;;

  restore-all)
    c_ylw "本机固件 22.2.8.3108 的实际情况："
    echo "  · pm disable-user / pm hide 被系统拒绝，从未生效"
    echo "  · pm uninstall --user 0 能卸载，但 pm install 系列全部挂死"
    echo "  · 所以没有逐包撤销的手段"
    echo
    if [ -f "$HERE/backup/uninstalled.log" ]; then
      echo "已卸载的包（恢复出厂后会由 /system 重新装回）："
      awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
          is_dev = ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/)
          dev = is_dev ? $1 : "(未记设备)"
          pkg = is_dev ? $2 : $1
          if (dev != last) { printf "\n  [%s]\n", dev; last = dev }
          printf "    - %s\n", pkg
        }' "$HERE/backup/uninstalled.log"
      echo
    fi
    c_grn "回滚方式：电视 → 设置 → 恢复出厂设置"
    ;;

  reboot)
    conn
    "$ADB" -s "$TARGET" reboot
    ;;

  *)
    cat <<'EOF'
小米电视精简工具（可逆）

  ./mitv.sh home                 把 Aerial 桌面拉回前台（守护失灵时用）
  ./mitv.sh install <apk>        装 APK（session 方式，绕过 adb install 挂死）
  ./mitv.sh tune                 设置层优化（开屏广告/日志上报/悬浮窗）
  ./mitv.sh uninstall <包名...>  尝试卸载（本机固件多半无效）
  ./mitv.sh probe                体检：电视是否在线、ADB 端口是否打开
  ./mitv.sh connect              连接并查看型号/系统版本
  ./mitv.sh backup               备份当前全部包名到 backup/
  ./mitv.sh find                 列出疑似广告/商店/推广相关包
  ./mitv.sh list [关键字]        搜索包名
  ./mitv.sh disable <包名...>    禁用（可逆）
  ./mitv.sh enable  <包名...>    恢复
  ./mitv.sh disable-file [文件]  按 packages.candidates.txt 批量禁用（会二次确认）
  ./mitv.sh restore-all          按 disabled.log 全部恢复
  ./mitv.sh reboot               重启电视

环境变量：MITV_IP=192.168.1.23  MITV_PORT=5555  ADB=adb
EOF
    ;;
esac
