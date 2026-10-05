#!/bin/bash
# ============================================================
# OCI VM.Standard.A1.Flex 自动抢机脚本
#
# 原理：循环尝试创建实例，遇到 "Out of host capacity"
# （容量不足）就换下一个可用性域继续试，直到成功为止。
#
# 使用方法：
#   1. 安装并配置 OCI CLI: oci setup config
#   2. cp config.example.sh config.sh，并填好里面的配置
#   3. chmod +x snatch.sh && ./snatch.sh
#   4. 挂后台: nohup ./snatch.sh > snatch.out 2>&1 &
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.sh"

if [[ ! -f "$CONFIG" ]]; then
  echo "错误: 找不到 config.sh，请先复制模板并填写配置："
  echo "  cp config.example.sh config.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG"

# ---- 校验必填配置 ----
for var in COMPARTMENT_ID SHAPE SUBNET_ID IMAGE_ID SSH_KEY_FILE; do
  if [[ -z "${!var:-}" ]]; then
    echo "错误: config.sh 中 $var 未填写"
    exit 1
  fi
done
if [[ ${#AVAILABILITY_DOMAINS[@]} -eq 0 ]]; then
  echo "错误: config.sh 中 AVAILABILITY_DOMAINS 为空，至少填一个可用性域"
  exit 1
fi
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "错误: SSH 公钥文件不存在: $SSH_KEY_FILE"
  exit 1
fi

ROUND_INTERVAL="${ROUND_INTERVAL:-120}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-120}"
MAX_ROUNDS="${MAX_ROUNDS:-0}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/snatch.log}"
OCPUS="${OCPUS:-4}"
MEMORY_GBS="${MEMORY_GBS:-24}"
DISPLAY_NAME="${DISPLAY_NAME:-a1-auto}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

trap 'log "收到中断信号，退出。"; exit 130' INT TERM

log "==================================================="
log "开始抢机：shape=$SHAPE, ocpus=$OCPUS, memory=${MEMORY_GBS}GB"
log "可用性域：${AVAILABILITY_DOMAINS[*]}"
log "==================================================="

round=0
while true; do
  round=$((round + 1))
  log "----- 第 $round 轮 -----"

  for ad in "${AVAILABILITY_DOMAINS[@]}"; do
    log "尝试在 $ad 创建实例..."

    OUTPUT=$(oci compute instance launch \
      --compartment-id "$COMPARTMENT_ID" \
      --availability-domain "$ad" \
      --shape "$SHAPE" \
      --subnet-id "$SUBNET_ID" \
      --image-id "$IMAGE_ID" \
      --ssh-authorized-keys-file "$SSH_KEY_FILE" \
      --display-name "$DISPLAY_NAME" \
      --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GBS}" \
      --wait-for-state RUNNING \
      --wait-interval-seconds 10 \
      --max-wait-seconds "$REQUEST_TIMEOUT" \
      2>&1)
    EXIT_CODE=$?

    if [[ $EXIT_CODE -eq 0 ]]; then
      INSTANCE_ID=$(echo "$OUTPUT" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
      log "=============================================="
      log "抢机成功！实例已在 $ad 创建并运行中。"
      log "实例 OCID: ${INSTANCE_ID:-未知，请查看日志}"
      log "=============================================="
      exit 0
    fi

    if echo "$OUTPUT" | grep -qi "Out of host capacity"; then
      log "$ad 容量不足，换下一个。"
    else
      log "$ad 创建失败（非容量问题），错误摘要："
      echo "$OUTPUT" | grep -iE "error|ServiceError|message" | head -3 | while read -r line; do log "  $line"; done
    fi
  done

  if [[ "$MAX_ROUNDS" -ne 0 && "$round" -ge "$MAX_ROUNDS" ]]; then
    log "已达到最大轮数 ($MAX_ROUNDS)，退出。"
    exit 1
  fi

  log "本轮所有可用性域均无容量，${ROUND_INTERVAL} 秒后开始下一轮..."
  sleep "$ROUND_INTERVAL"
done
