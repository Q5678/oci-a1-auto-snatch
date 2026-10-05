# ============================================================
# 配置模板：复制为 config.sh 后填写
#   cp config.example.sh config.sh
# 注意：config.sh 包含你的云资源 ID，已加入 .gitignore，
#       不要提交到公开仓库！
# ============================================================

# ---- OCI 基础配置 ----
COMPARTMENT_ID="ocid1.compartment.oc1..xxxx"   # 你的 compartment OCID

# 可用性域列表（脚本按顺序轮询），用完整名称。
# 查询命令：oci iam availability-domain list --compartment-id <tenancy OCID>
AVAILABILITY_DOMAINS=(
  "ap-singapore-1-AD-1"
  "ap-singapore-1-AD-2"
)

SHAPE="VM.Standard.A1.Flex"                   # 机型
OCPUS=4                                       # OCPU 数（免费额度最多 4）
MEMORY_GBS=24                                 # 内存 GB（免费额度最多 24）

SUBNET_ID="ocid1.subnet.oc1..xxxx"             # 子网 OCID
IMAGE_ID="ocid1.image.oc1..xxxx"               # 系统镜像 OCID
# 查询 ARM 镜像：
# oci compute image list --compartment-id <compartment OCID> \
#   --operating-system "Canonical Ubuntu" --shape VM.Standard.A1.Flex \
#   --sort-by TIMECREATED --sort-order DESC --query 'data[0].id'

SSH_KEY_FILE="$HOME/.ssh/id_rsa.pub"          # SSH 公钥（没有就 ssh-keygen 生成一个）
DISPLAY_NAME="a1-auto"                        # 实例显示名称

# ---- 重试配置 ----
ROUND_INTERVAL=120    # 每一轮（所有 AD 都试完）后等待秒数，建议 60~300
REQUEST_TIMEOUT=120   # 单次创建请求的最长等待秒数
MAX_ROUNDS=0          # 0 = 无限轮询直到成功
LOG_FILE="snatch.log" # 日志文件（相对路径相对于脚本目录）
