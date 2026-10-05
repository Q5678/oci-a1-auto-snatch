#!/bin/bash
# ============================================================
# OCI VM.Standard.A1.Flex 自动抢机脚本
#
# 原理：循环尝试创建实例，遇到 "Out of host capacity"
# （容量不足）就换下一个可用性域继续试，直到成功为止。
#
# 使用方法：
#   1. 安装并配置 OCI CLI: oci setup config
#   2. cp config.example.sh config.sh，只填 COMPARTMENT_ID 和 SUBNET_ID；
#      区域、可用性域、镜像 OCID 留空，脚本会自动查询
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
for var in COMPARTMENT_ID SHAPE SUBNET_ID SSH_KEY_FILE; do
  if [[ -z "${!var:-}" ]]; then
    echo "错误: config.sh 中 $var 未填写"
    exit 1
  fi
done
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "错误: SSH 公钥文件不存在: $SSH_KEY_FILE"
  echo "  没有密钥对的话，运行 ssh-keygen -t rsa -b 4096 一路回车生成"
  exit 1
fi

# ---- 自动识别区域（优先用 config.sh 里填的，否则从子网 OCID 解析）----
if [[ -z "${REGION:-}" ]]; then
  REGION="$(echo "$SUBNET_ID" | cut -d. -f4)"
  if [[ -z "$REGION" || "$REGION" == "$SUBNET_ID" ]]; then
    echo "错误: 无法从 SUBNET_ID 解析区域，请在 config.sh 中填写 REGION"
    exit 1
  fi
fi

# ---- 自动查询可用性域（config.sh 里留空时）----
if [[ -z "${AVAILABILITY_DOMAINS[*]:-}" ]]; then
  echo "正在查询 $REGION 的可用性域..."
  AD_NAMES="$(oci iam availability-domain list \
    --compartment-id "$COMPARTMENT_ID" --region "$REGION" 2>/dev/null \
    | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
  AVAILABILITY_DOMAINS=()
  while IFS= read -r ad_name; do
    [[ -n "$ad_name" ]] && AVAILABILITY_DOMAINS+=("$ad_name")
  done <<< "$AD_NAMES"
  if [[ ${#AVAILABILITY_DOMAINS[@]} -eq 0 ]]; then
    echo "错误: 查询可用性域失败，请检查 OCI CLI 配置（oci setup config）"
    exit 1
  fi
fi

# ---- 自动查询最新 Ubuntu ARM 镜像（config.sh 里留空时）----
if [[ -z "${IMAGE_ID:-}" ]]; then
  echo "正在查询最新的 Canonical Ubuntu ARM 镜像..."
  IMAGE_ID="$(oci compute image list \
    --compartment-id "$COMPARTMENT_ID" \
    --operating-system "Canonical Ubuntu" \
    --shape "VM.Standard.A1.Flex" \
    --sort-by TIMECREATED --sort-order DESC \
    --region "$REGION" 2>/dev/null \
    | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
  if [[ -z "$IMAGE_ID" ]]; then
    echo "错误: 查询镜像失败，请检查 OCI CLI 配置（oci setup config）"
    exit 1
  fi
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
log "开始抢机：region=$REGION, shape=$SHAPE, ocpus=$OCPUS, memory=${MEMORY_GBS}GB"
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
      --region "$REGION" \
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
