#!/usr/bin/env bash
# 逐包卸载（MiTV4-ANSM0 / 22.2.8.3108）
#
# 实测要点：
#   1. pm uninstall --user 0 会阻塞约 2 分钟，结束时 adbd 会掉线
#   2. 所以必须「阻塞等待 + 结束后重连验证」，不能丢到设备端后台
#   3. 不能用「命令失败」判断包是否还在，必须区分「设备离线」和「包不存在」
#
# 警告：本机 pm install 系列全部挂死，卸载后无法单独恢复，只能恢复出厂设置。

set -o pipefail

ADB="${ADB:-adb}"
IP="${MITV_IP:-192.168.1.23}"
PORT="${MITV_PORT:-5555}"
TARGET="$IP:$PORT"
WAIT="${MITV_WAIT:-240}"      # 单次卸载最长等待秒数
RETRY="${MITV_RETRY:-2}"      # 每个包最多尝试次数

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/backup/uninstalled.log"
mkdir -p "$HERE/backup"

c_grn() { printf '\033[32m%s\033[0m\n' "$*"; }
c_red() { printf '\033[31m%s\033[0m\n' "$*"; }
c_ylw() { printf '\033[33m%s\033[0m\n' "$*"; }

reconnect() {
  "$ADB" connect "$TARGET" >/dev/null 2>&1
  sleep 2
}

# 输出 installed / uninstalled / unknown
pkg_state() {
  local pkg="$1" out
  reconnect
  out="$("$ADB" -s "$TARGET" shell pm list packages 2>/dev/null | tr -d '\r')"
  if [ -z "$out" ]; then
    echo unknown
  elif echo "$out" | grep -qx "package:$pkg"; then
    echo installed
  else
    echo uninstalled
  fi
}

uninstall_one() {
  local pkg="$1" attempt state

  for attempt in $(seq 1 "$RETRY"); do
    state="$(pkg_state "$pkg")"
    case "$state" in
      uninstalled)
        c_ylw "跳过（已卸载）: $pkg"; return 0 ;;
      unknown)
        c_red "设备无响应，无法判断 $pkg"; sleep 5; continue ;;
    esac

    echo "  第 $attempt 次尝试（预计约 2 分钟，期间 adbd 会掉线）..."
    "$ADB" -s "$TARGET" shell am force-stop "$pkg" >/dev/null 2>&1

    # 阻塞式调用。正常情况约 128 秒返回；超时则强杀客户端，下一轮再验
    perl -e 'alarm shift; exec @ARGV' "$WAIT" \
      "$ADB" -s "$TARGET" shell "pm uninstall --user 0 $pkg" >/dev/null 2>&1

    sleep 3
    state="$(pkg_state "$pkg")"
    if [ "$state" = "uninstalled" ]; then
      c_grn "✅ 已卸载 $pkg"
      echo "$TARGET $pkg" >> "$LOG"
      return 0
    fi
    c_ylw "  仍在（状态: $state），重试"
  done

  c_red "✘ 失败 $pkg（$RETRY 次尝试后仍在）"
  return 1
}

[ $# -gt 0 ] || { echo "用法: $0 <包名> [包名...]"; exit 1; }

reconnect
if ! "$ADB" -s "$TARGET" shell echo ok 2>/dev/null | grep -q ok; then
  c_red "连不上 $TARGET，先跑 ./mitv.sh probe"
  exit 1
fi

fail=0
for pkg in "$@"; do
  echo "──────── $pkg ────────"
  uninstall_one "$pkg" || fail=$((fail+1))
done

echo
c_grn "完成：成功 $(( $# - fail ))/$#，失败 $fail"
[ "$fail" -eq 0 ]
