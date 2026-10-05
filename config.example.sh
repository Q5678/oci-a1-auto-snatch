# ============================================================
# 配置模板：复制为 config.sh 后填写
#   cp config.example.sh config.sh
# 注意：config.sh 包含你的云资源 ID，已加入 .gitignore，
#       不要提交到公开仓库！
# ============================================================

# ---- OCI 基础配置 ----
# 只需要填 COMPARTMENT_ID 和 SUBNET_ID，
# 区域、可用性域、镜像 OCID 留空，脚本运行时会自动查询。
COMPARTMENT_ID="ocid1.compartment.oc1..xxxx"   # 你的 compartment OCID（根区间可直接用 tenancy OCID）

# 区域：留空则从下面的子网 OCID 自动识别
REGION=""

# 可用性域：留空则脚本自动查询该区域的全部可用性域并轮询
# 如需手动指定，取消下面注释并填写：
# AVAILABILITY_DOMAINS=(
#   "ap-singapore-2-AD-1"
# )
AVAILABILITY_DOMAINS=()

SHAPE="VM.Standard.A1.Flex"                   # 机型
OCPUS=4                                       # OCPU 数（免费额度最多 4）
MEMORY_GBS=24                                 # 内存 GB（免费额度最多 24）

SUBNET_ID="ocid1.subnet.oc1..xxxx"             # 子网 OCID

# 系统镜像：留空则脚本自动使用最新的 Canonical Ubuntu ARM 镜像
IMAGE_ID=""

SSH_KEY_FILE="$HOME/.ssh/id_rsa.pub"          # SSH 公钥（没有就 ssh-keygen 生成一个）
DISPLAY_NAME="a1-auto"                        # 实例显示名称

# ---- 重试配置 ----
ROUND_INTERVAL=120    # 每一轮（所有 AD 都试完）后等待秒数，建议 60~300
REQUEST_TIMEOUT=120   # 单次创建请求的最长等待秒数
MAX_ROUNDS=0          # 0 = 无限轮询直到成功
LOG_FILE="snatch.log" # 日志文件（相对路径相对于脚本目录）
