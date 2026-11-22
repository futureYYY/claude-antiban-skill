> 作者：future ｜ https://github.com/futureYYY/claude-antiban-skill ｜ MIT

# 阶段 1-2：服务器与出口 IP

> 本文所有 IP、段、端口均为占位符。落地时替换成自己的值，**不要写进任何公开文档**。

## 一、买什么

**结论：要看「产品类型」，别被「IP 不满意可以换」打动。**

同样是买一台美国服务器，商家有两种卖法：

| 卖法 | 听着像 | 实际买到什么 |
|---|---|---|
| 普通 VPS，附带一句「IP 不满意可以给你换」 | 服务很贴心 | **换多少次都还在同一个机房、同一个 ASN**，判定结果一个字都不变 |
| 独立的「静态住宅 IP / 家庭宽带 VDS」产品线 | 价格明显更贵 | IP 来自运营商的家宽段，`asn.type = isp`，可能带 `Connection type = dsl` |

判断是不是住宅，看的是 **IP 的 ASN 归属类型**，不是它被换过几次：

- 机房产品的 IP，换 10 个，`asn.type` 还是 `hosting`
- 住宅产品线的 IP，才可能是 `isp`

打个比方：「换 IP」是**在同一栋写字楼里换房间号**，楼的性质不变；「换产品线」才是**换一栋楼**。

我的实测：同一家换了两次 IP（Cogent → NTT），两次都被判机房 / 商业段；只有换成住宅产品线，才拿到 `dsl` 段。

> **这两种情况要分清**：
> - 买错了产品类型（机房 VPS）→ 让商家换 IP 没用，只能换产品线
> - 买对了产品线，但这个 IP 的欺诈分偏高 → **可以要求换 IP**，同一条产品线里挑一个干净的（话术见第五节）

## 二、三档判据（看 `asn.type`，不看宣传）

| asn.type | company.type | 判定 |
|---|---|---|
| hosting | 任意 | 机房 IP，最差 |
| isp | business | 半住宅，不稳 |
| isp | isp | 住宅（双 ISP），最好 |

**「双 ISP」是一个 IP 的两个属性维度，不是两个 IP。** 商家说双 ISP 时，要它两个字段都返回 `isp`。

判断「机房 IP」的硬判据是 `asn.type = hosting`，不是 `company.type`。

## 三、我的服务器配置（2026-10，¥169/月）

| 项 | 值 |
|---|---|
| 机型 | 【华盛顿州西雅图 Atlas Networks】美国家庭宽带静态住宅 IP VDS · 基础版 |
| 可用区 | US-SEA-BGP-01（经典网络） |
| CPU | 1 核 |
| 内存 | 1 GB（必须加 2 GB swap） |
| 系统盘 | 20 GB |
| **上行带宽** | **100 Mbps** |
| **下行带宽** | **100 Mbps** |
| **月流量** | **3000 GB** |
| 系统 | Ubuntu 22.04 |
| 计费 | 每月 ¥169 |

**流量实测**：2026-10-03 开机，到 11-01 约 4 周用了 **251.85 GB / 3000 GB（≈8%）**。也就是说跑 Claude Code + 日常代理，一个月 250 GB 上下，3000 GB 的额度非常宽裕；真正吃流量的是下模型、传大文件这类操作。

⚠️ **记得记下到期日**：这台是月付，到期当天会直接断网，而且不会有提前通知。续费后 IP 一般保留，但换套餐 / 换产品线会换 IP。

IP 属性：`asn.type=isp` 且 `company.type=isp`、`hosting=false`、Scamalytics 欺诈分 0、Server=No、Connection type=`dsl`、PTR 为空。

⚠️ **1 核 1G 只能跑 Claude Code，不能当编译机**。Spring Boot 起服务 + Maven 编译必然 OOM，前端构建要 12G 堆。编译回本地，服务器只写码。

## 四、验收

```bash
bash scripts/check-ip-quality.sh <VPS_IP>
```

六项看齐才算达标：

| # | 判据 | 来源 |
|---|---|---|
| 1 | `asn.type = isp` | ipinfo |
| 2 | `company.type = isp` | ipinfo |
| 3 | **ASN 编号与第二家库一致** | ipapi.is 交叉核对 ipinfo |
| 4 | Scamalytics 欺诈分 ≤ 25（低风险区间） | Scamalytics |
| 5 | Server / Public Proxy / VPN / Tor 全 No | Scamalytics |
| 6 | `Connection type = dsl` | Scamalytics |

### 关于交叉验证

判"是不是住宅"这件事，各家的口径不一样，所以要分两层看：

- **类型字段（isp / hosting）只有 ipinfo 一家给** —— 这是唯一来源，没有第二家能独立复现。所以第 3 条补的是**另一件事**：核对两家库对「这个 IP 属于哪个 ASN」是否一致。不一致说明有一家库过时、或者 IP 刚变更，这时候别急着付款。
- **"是不是住宅连接"这件事有两家独立判定** —— ipinfo 看 ASN 归属类型，Scamalytics 看滥用记录 + 连接类型（`dsl` 是住宅宽带的强特征）。两者结论一致才可信。
- **PTR 是弱信号** —— 住宅 IP 不一定有反解，整段没有反解是机房的典型特征，但反过来不成立。

所以真正意义上的交叉验证是第 3、5、6 条：**不同数据源、不同维度、指向同一个结论**。

### 关于欺诈分（会浮动，别当成绝对值）

Scamalytics 的分是**段 / 商级**的 —— 官方口径是 "based on the overall risk from \<ISP\>'s IP addresses"，**不是只算你这一个 IP**。所以：

- 买新 IP 时用它筛：≤25 属低风险，可以下手
- **已在用的 IP 分数上浮**（比如从 0 涨到 25），不必急着换 —— 同段换 IP 改不了这个数
- 分涨上去之后，先看 `Server` / `Public Proxy` / `Connection type` 三项是否还干净；这三项才是住宅属性的强证据
- 真正的判据还是「实测能不能用」：能用、不频繁弹验证码，就继续用

PTR 反解为空是住宅常态，不用强求。

### 测试 IP ≠ 实际开出的 IP

客服给的样品可能是完美分数，实际开通后完全不同。我这次的记录（IP 已脱敏）：

| 序号 | asn / company | 欺诈分 | 结果 |
|---|---|---|---|
| 样品 | isp / isp | 0 | 完美，但不是分给我的 |
| 实开 #1 | isp / isp | 38 | 双 ISP 但分偏高 |
| 换 #2 | isp / business | 0 | 分好但非双 ISP |
| 再换 #3 | isp / isp | 0 | 达标，留用 |

**开通后必须逐项复验，别拿样品当成品。**

## 五、跟商家换 IP 的话术

把标准写成他能照着查的动作，别写术语：

> 我要同一个 /23 段内、ipinfo 上 ASN TYPE 和 Company Type 都显示 ISP、scamalytics 上 Server 显示 No 且欺诈分 ≤25 的 IP。

三条纪律：

1. **先写死验收标准再答应换**（不写 → 对方给你同段的另一个 IP）
2. 问清「是否重装系统」（会丢 SSH 公钥和已装服务）
3. 退款选退现金，别选退账户余额

## 六、两把尺子不能横比

| | Scamalytics 欺诈分 | IPPure 风险值 |
|---|---|---|
| 量什么 | 滥用 / 欺诈举报 | 段内人机流量构成 |
| 方向 | 越低越好 | 数值越大越危险 |
| 粒度 | 段 / 商级 | 段 / ASN 级 |

同一个 IP 可以是「欺诈分 0 但 IPPure 22」，不矛盾，量的不是一回事。**换同段 IP 改不了 ASN 级的指标。**

## 七、服务器加固

执行 `bash scripts/harden-server.sh <SSH_PORT> <SS_PORT> <TIMEZONE>`。

1. 仅密钥登录 —— **先证明密钥能登，再关密码**
2. ufw：`deny incoming`，只放行 SSH 端口 + shadowsocks 端口。**先 allow 再 enable**，反了会把自己锁在外面
3. 关 IPv6
4. 时区对齐出口 IP（如 `America/Los_Angeles`）
5. 1G 内存必加 2G swap

### 完成判据

```bash
ss -tlnp     # 只有 sshd + ss-server 在听
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no <alias> echo x
# 期望: Permission denied (publickey) —— 括号里不能再出现 password
```

### 真实 IP 的两个落点（部署 Claude Code 之后才致命）

服务器日志里出现你的家宽 IP，本来只是商家能看到；真正的风险是 **Claude Code 有 root 权限，它执行 `who` / `last` 就能读到并可能写进上下文**。

- `SSH_CONNECTION` / `SSH_CLIENT` 环境变量 → `claude-safe` 里 unset 掉
- 主动执行 `who` / `last` / `cat /var/log/auth.log` → 这条堵不掉，只能靠「日志里本来就没有」来根治

**根治 = 开梯子再 SSH**（链式下服务器看到的来源是它自己）。清日志是边清边漏。
