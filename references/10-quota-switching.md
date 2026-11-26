# 多账号额度轮换（2026-11-26 版）

> 作者：future ｜ 更新：2026-11-26

一个 Claude 订阅有两道额度闸：**5 小时会话额度**和**每周额度**。跑长任务时，撞任意一道都会被硬断。

这一篇讲的是：用两个（或多个）订阅**轮流顶班**，让任务不断档，同时不让平台看出"同一台机器在反复换号"。

---

## 1. 先分清两道闸，别混成一个数

很多人把「5h 用了 60%、周用了 30%」合成一个"利用率 60%"来判断，这样做会踩坑：

- 5h 额度 5 小时就回血，撞了只是**暂停几小时**
- 周额度要等一周才回血，撞了是**停用几天**

两者的严重程度差一个量级，混在一起算，就会出现「5h 还有 80%，周只剩 2%，脚本却认为这个号很健康」。

所以本方案把判断拆成两层：

| 层 | 作用 | 判据 |
|---|---|---|
| **第一层：周额度** | 决定「这个号还能不能用」 | 周剩余 ≤ **13%** → 停用，5h 再空也不用 |
| **第二层：5h 额度** | 决定「周额度都够时，用哪个号」 | 5h 剩余 ≤ 10–20%（每轮随机）→ 优先换到 5h 更宽的那个 |

一句话：**周额度是生死线，5h 只是调度偏好。**

---

## 2. 周额度地板：13%，写死不是偷懒

```
默认地板 13%  →  利用率阈值 0.87
可用 WEEK_FLOOR_PCT=8~13 覆盖
```

### 为什么是 13%，不是"每轮随机 8~13"

一开始的设计是每轮抽一个 8~13 的数当阈值，实测发现**会抖**：

```
第 1 轮：抽到 8  → 周剩 10%，10 > 8，判定"还能用"
第 2 轮：抽到 13 → 周剩 10%，10 < 13，判定"停用"，切走
第 3 轮：抽到 8  → 又判定"能用"，切回来
```

同一台机器、同一个号，在两轮之间反复"死而复生"，日志里全是无意义的切换。

所以改成：**地板固定 13%，落盘到 `guard2.floor`，重启不重抽。** 想放宽就设 `WEEK_FLOOR_PCT=8`，但设置一次就固定，不要每轮变。

### 为什么留 13% 而不是 0%

- 留余量：正在跑的会话可能还有几轮 tool call，13% 够它收尾
- 留缓冲：探测有 10–20 分钟间隔，13% 能覆盖这个窗口内的消耗
- 不留太多：留 30% 会让两个号互相踢（见 §6 最小驻留）

---

## 3. 5h 额度：10–20% 随机触发

```
每轮抽 W = 10~20
5h 触发线 = 1 - W/100   （0.80 ~ 0.90）
检查间隔 = W 分钟
```

作用只有一个：**周额度都够的时候，优先用 5h 更宽的那个号**。

它**不再**参与"能不能用"的判断 —— 一个号周额度只剩 5%，就算 5h 是 0%，也不会被启用。

---

## 4. 决策顺序（脚本每轮实际怎么走）

```
1. 读当前号：http / 5h / 7d / 两个 reset 时间
2. 算：week_left = (1 - u7) * 100
3. 若 http != 200        → 死号，立即切（不看驻留）
4. 若 week_left <= 地板  → 周额度耗尽，立即切（不看驻留）
5. 否则若 5h >= 触发线 且 距上次切换 > 30 分钟
       → 找候选（周额度 > 地板 且 5h < 95%）
       → 有就切；没有就进入等待
6. 否则什么都不做，睡 W 分钟
```

注意第 3、4 步**不受 30 分钟驻留限制** —— 号已经死了，再驻留就是白等。

---

## 5. 等待：比"谁能更早真正恢复可用"

没有可用候选时，不能随便挑一个重置时间等。这里有两个不同的"恢复点"：

| 情况 | 等什么 | 醒来后复核 |
|---|---|---|
| 周额度都耗尽了 | 各号的 **r7**（周重置）+ 30~60 分钟随机 | 该号 `周剩余 > 地板` |
| 周额度够、但 5h 都榨干了 | 各号的 **r5**（5h 重置）+ 10~30 分钟随机 | 该号 `周剩余 > 地板` **且** `5h < 95%` |

**取更早的那个**。举个真实例子：

```
当前 pro 号：周剩 44%，5h 剩 2%
另一个 max 号：周剩 2%（触地板），周重置 11-28 21:00

错误做法：等 max 的周重置（4 天后）
正确做法：等 pro 自己的 5h 重置（4 小时后），因为 pro 周额度还够
```

这就是"比谁能更早真正恢复可用"，而不是"取 min(r5, r7)"——后者几乎总会选中 5h，切过去发现周额度还是死的，30 分钟后又被切回来。

### 等待期间的三条提前结束条件

- 当前号自己恢复了（周剩余 > 地板）→ 取消等待，继续用
- 出现了一个可用候选 → 立即切，不等了
- 等待到期但复核不通过 → 丢掉等待状态，下一轮重新评估（不硬切）

---

## 6. 最小驻留 30 分钟

切过去之后 30 分钟内，**就算又超阈值也不切**。

原因：两个号的额度都在往下掉，没有驻留就会 A→B→A→B 来回踢，每次切换都要重启会话、发「继续」，任务被打断无数次。

例外只有两种：**死号**和**周额度触地板**——这两种等下去没有意义。

---

## 7. 续跑：只发「继续」，串行

切号会重启 tmux 会话。重启后：

- **正在跑的任务**（面板底部有 `esc to interrupt`）→ 发「继续」
- **已经跑完的** → 什么都不发（多发一次会让它把做完的事再做一遍）

多个窗口**不要并发**：

```
窗口 A 发「继续」→ 等 random(5~10 秒) → 窗口 B → ...
```

同时往 5 个窗口灌输入，终端层面就是一串密集按键，容易串窗口。

---

## 8. 重启保留模型和推理强度

重启时无脑用默认参数，会出现「原来 opus + max 的任务，重启后掉回 sonnet」——输出质量突变，你还以为是额度问题。

正确做法：重启前从进程参数里读出来，原样拼回去：

```bash
ps -eo args= -p <claude_pid>
# claude -c --model opus --effort max --permission-mode bypassPermissions
```

脚本只重启**正在跑 claude 的会话**，纯 shell 会话跳过。

---

## 9. 切号的作用范围（重要边界）

`claude-safe` 在**进程启动时**读一次 token。所以：

| 场景 | 切号是否生效 |
|---|---|
| tmux 里的 Claude Code 会话 | ✅ 脚本会重启它，重启即换号 |
| 网页版 / CloudCLI 已跑着的进程 | ❌ 要等它下次重启或新开会话 |
| 你本地电脑上的 Claude Code | ❌ 用的是本机凭据 |

不要以为切了 active 就全局生效。

---

## 10. 时区：跟着服务器走

systemd 单元里**不要写 `Environment=TZ=`**，让它继承系统时区；脚本格式化时间时用服务器本地时区。

理由：

1. 排查对不上：`journalctl`、`ls -l`、nginx 日志都是机器本地时区，只有守护日志是另一个时区，对时间要心算
2. 一台美国 IP 的机器，系统里到处是别的时区，本身就是不该留的痕迹
3. 固定偏移不跟夏令时，半年内会有 1 小时误差

```bash
timedatectl     # 应该是 America/Los_Angeles（美西）
```

---

## 11. 部署

```bash
# 1. 第二个号单独授权（不要让新 token 覆盖 active）
tmux new-session -d -s auth2 'claude setup-token'
tmux capture-pane -p -J -t auth2 | grep -oE 'https://claude.ai/oauth/[^ ]+'
# 浏览器授权 → 把 code 粘回会话
tmux send-keys -t auth2 -l '<code>'; tmux send-keys -t auth2 Enter
# 拿到 token 后单独存文件
printf '%s' '<sk-ant-oat01-...>' > /root/.claude/tokens/pro-YYYYMMDD.env
chmod 600 /root/.claude/tokens/pro-YYYYMMDD.env

# 2. 装脚本
install -m 755 scripts/quota-guard2.sh /usr/local/bin/claude-quota-guard2

# 3. systemd
cat >/etc/systemd/system/claude-quota-guard2.service <<'EOF'
[Unit]
Description=Claude multi-account quota guard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HOME=/root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/claude-quota-guard2
Restart=always
RestartSec=20

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now claude-quota-guard2
```

### 常用命令

```bash
claude-quota-guard2 --status     # 两个号的 5h / 周余量 / 周重置时间 / 地板 / 是否在等待
claude-quota-guard2 --once       # 只跑一轮（调试用）
DRY_RUN=1 claude-quota-guard2    # 干跑：只打日志，不切号
```

`--status` 输出示例：

```
ACCOUNT            HTTP   5H       7D       WEEK_LEFT  RESET_7D
max-20261122       200    0.0      0.98     2%         11-28 21:00
pro-20261124       200    0.01     0.56     44%        11-27 05:00
active: max-20261122   周地板: 13%   等待中: 无
```

### 调地板

```bash
# 方式一：写进单元（持久）
Environment=WEEK_FLOOR_PCT=10
systemctl daemon-reload && systemctl restart claude-quota-guard2

# 方式二：删掉落盘值，回落默认 13
rm -f /root/.claude/failover/guard2.floor && systemctl restart claude-quota-guard2
```

---

## 12. 自检

```bash
bash scripts/quota-guard2-selftest.sh
```

覆盖：地板换算、候选筛选（周额度、5h 上限）、等待目标选择（周重置 vs 5h 重置）、死号判定。不碰真实账号，纯函数级验证。

---

## 13. 踩过的四个坑

| 现象 | 根因 | 修法 |
|---|---|---|
| 所有账号都判成 `http=000` | HTTP/2 状态行尾部带空格，`${first##* }` 取到空串 | 按空格切分后取第 2 段，非数字归 `000` |
| 双号都紧时切过去立刻又超 | 等的是 `min(r5, r7)`，几乎总落在 5h | 按「周耗尽 / 5h 耗尽」分别算恢复点，取能真正恢复的那个 |
| 日志偶发 `write error: Broken pipe` | `printf ... | head` 触发 SIGPIPE | 改用 here-string |
| 手动跑 + systemd 同时跑，切两次 | 没有单实例保护 | `flock -n` 锁文件 |

---

## 14. 风险与边界

- 两个号同一出口 IP 长期同时在线，关联风险高于单号；能分环境就分
- 自动切换只解决"任务中断"，**不解决"账号存活"**
- 额度规则由平台决定，随时会变；脚本要能一键停：`systemctl stop claude-quota-guard2`
- 不要把地板设得过高（比如 30%），否则两个号会互相踢，切换频率上去，行为反而不自然
