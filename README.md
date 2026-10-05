# OCI A1 Flex 自动抢机脚本

解决 Oracle Cloud `VM.Standard.A1.Flex` 机型常见的
`Out of host capacity`（可用性域容量不足）问题：
脚本会自动轮询你配置的多个可用性域，不停重试直到抢到实例为止。

## 准备工作

1. 安装 OCI CLI：https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm
2. 配置 OCI CLI（需要 user OCID、tenancy OCID、region，并上传 API 公钥）：
   ```bash
   oci setup config
   ```
   验证：`oci iam region list` 能返回结果即配置成功。

## 使用方法

```bash
# 1. 复制配置模板并填写
cp config.example.sh config.sh
# 用编辑器打开 config.sh，填上你的 compartment OCID、可用性域、
# 子网 OCID、镜像 OCID 等（里面有查询命令注释）

# 2. 加执行权限并运行
chmod +x snatch.sh
./snatch.sh

# 3. 挂后台长期运行（推荐）
nohup ./snatch.sh > snatch.out 2>&1 &
tail -f snatch.log   # 查看抢机进度
```

抢到后脚本会自动退出，并在日志里打印实例 OCID。

## 常用查询命令

```bash
# 可用性域完整名称
oci iam availability-domain list --compartment-id <tenancy OCID>

# 最新的 Ubuntu ARM 镜像 OCID
oci compute image list --compartment-id <compartment OCID> \
  --operating-system "Canonical Ubuntu" --shape VM.Standard.A1.Flex \
  --sort-by TIMECREATED --sort-order DESC --query 'data[0].id'

# 生成 SSH 密钥对（如果没有）
ssh-keygen -t rsa -b 4096
```

## 提高成功率的小技巧

- 多配几个可用性域，脚本会按顺序轮询
- 新加坡有两个区域：`ap-singapore-1`（Singapore）和
  `ap-singapore-2`（Singapore West），记得先在控制台订阅区域
- 晚间、凌晨等低峰时段更容易放出容量

## 安全提醒

`config.sh` 里有你的云资源 ID，已通过 `.gitignore` 排除，
不要把它提交到公开仓库。
