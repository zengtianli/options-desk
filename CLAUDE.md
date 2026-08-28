# CLAUDE.md · options-desk（投资盘面）

> iOS 只读盘面。父级形态规则 `~/Apps/ios/CLAUDE.md`，建 app 的通用坑单 `/appios`，
> 全局偏好 `~/.claude/CLAUDE.md`。姊妹 app：`~/Apps/ios/options-calc`（期权决策台）。

**2026-08-28 立。当前只有脚手架，没有 UI —— 按对齐的顺序，先修数据口径再建界面。**

## 这个 app 回答什么

「我现在怎么样」：净值 · 累计收益 · **对 QQQ 的超额** · buffer · 六批票据梯子。

它**不**回答「如果我开这个结构会怎样」——那是 `options-calc`。两个刻意分开：
那个是纯函数计算器（零网络、零凭证、离线、3 个 Swift 文件，舰队里最稳的一个），
这个天天变、要联网要凭证要缓存要陈旧提示。合并会把最稳的变成最复杂的。

## 数据从哪来（**不造第二个账本**）

```
Robinhood MCP (get_*)
    → ~/investment/data/quant.db        rh_history / rh_group_pnl / rh_*_positions
    → review_run.py --facts             引擎值
    → 每日复盘正文 + 配图（blog-options）
```

**这条链是活的**（2026-08-28 查证：`rh_portfolios.asof` = 2026-08-27 16:00 EDT）。
本 app 是它的**消费端**。要新建的只有「把 quant.db 暴露成只读 API」，
而那个服务**也已经存在**：`~/Dev/stations/web-stack/services/stockoptions/api.py`，
`/api/equity-curve` `/api/summary` `/api/portfolio` 形状正好，只是数据源指着一堆
2026-06 就停更的 JSON。**重新指向 quant.db，禁新建第二个 API**（铁律 #5）。

## 三个目录各管一段（这不是一个目录的活）

| 目录 | 职责 |
|---|---|
| `~/investment/options/robinhood/` | 口径：回填 `qqq_close`、对账 `net_deposit`、把同步挂进 `review_run.py` |
| `~/Dev/stations/web-stack/services/stockoptions/` | 只读 API：数据源换成 quant.db，接 authgate |
| 本目录 | 客户端 |

## ⚠ 前身死过一次，死因写在这里

`cc-options` 曾经就是这个东西。2026-08-28 查证它的状态：

```
data/portfolio.json    停在 2026-06-01     LaunchAgent(17:00 同步)     没了
daily_nlv.csv          停在 2026-05-21     VPS 的 cc-options.service   没了
cc-options.tianli.cyou  DNS 不指向 VPS,也不在 menus 子域注册表里
```

**三个月里没有任何东西报过警。** 死因：同步挂在一个「Mac 得在 17:00 醒着」的
LaunchAgent 上，那个前提一破，整条链无声停摆。

由此两条硬约束，删一条这个 app 迟早重蹈覆辙：

1. **同步挂在用户每天真的会做的那件事上** —— `review_run.py`（写复盘必跑）顺带推
   quant.db。**不要再挂 LaunchAgent**：习惯不会静默死，cron 会。
2. **数据陈旧必须在界面上刺眼**，而不是安静地显示一个旧数字。
   同源教训：2026-08-28 blog-reader 的 blog-options 站因为撞访问闸静默贡献 0 篇，
   错误条上只有一句「解析失败」——既不像错误也指不出方向。

## 首屏放什么（**不是年化**）

2026-08-28 用真 TWR（逐日链接、当日入金在期初剔除）算主账户 `5UK56277`：

```
TWR 累计    +24.46%      53 个交易日 / 78 自然日,净入金 $115,570
年化        +183.1%      ← 把 53 天放大 4.8 倍
年化波动     41.1%
年化收益的标准误  ≈ 90pp
```

**误差带是估计值的一半** —— 「年化 183%」和「年化 93%」统计上分不开。
把它做成首屏大字 = 每天剧烈跳动且没有信息量。

所以：**首屏 = 累计收益 + 对 QQQ 的超额 + 样本天数**（这三个稳、可解释）；
年化放二级页，**旁边必须同时印标准误和样本长度**。等序列过了一年再让它当主角。

## 开工前必须先修的三个口径坑（全在服务端，不在 app 里）

| 坑 | 实测（2026-08-28） | 后果 |
|---|---|---|
| `qqq_close` 缺一半 | 53 天里只有 **36 天**有值，首个有值日 2026-07-10 | **超额收益算不出来** —— 首屏最重要那栏是空的。（博客那张 race 图锚在 07-09，就是这个原因） |
| 序列太短 | `rh_history` 只从 **2026-06-09** 起 | 年化 = 噪音 × 4.8 |
| `net_deposit` 稀疏 | 只有 2 行非零（07-10、07-13，合计 $115,570） | TWR 全靠它；漏一笔入金，年化就假 |

## 已对齐的决策（2026-08-28，用户拍板）

- **新建本 app**，不并进 `options-calc`。
- **先修口径再建界面** —— 现在建，超额那栏一开始就是空的；而且 app 建完再改口径，两边都要动。
- **两个账户合并成一个总账**（`5UK56277` + `700013444`）。「我的钱表现如何」本来就该是合并口径；
  分账户看是运维视角不是投资视角。

## 凭证

复用 blog-reader 那套（2026-08-28 验过，零手工）：`Gate.swift` + `seed-gate.sh`，
密码存 **macOS 钥匙串**（`security -s tlz-gate`），装机时用 `-gatepw` 启动参数喂一次，
app 验过写进 iOS 钥匙串。

> **密码禁进 `~/.personal_env`** —— 2026-08-28 实测 `XCBuildData` 会把构建时的完整环境
> **连值一起**记进中间产物（当时那里躺着 68 个真实凭证的明文）。
> 现在 HQ 的构建脚本已用 `scrub_env.sh` 摘掉，机器门 `secret_leak_audit.py`。

## 构建与装机

```bash
./sim-run.sh              # 模拟器（shim → 总部 SSOT）
./install-to-iphone.sh    # 真机（shim → 总部 SSOT）
```

付费 team `B9LJH93LA4`，证书 2027-08-28 到期。装机脚本尾部打印的到期日是从包里那张
`embedded.mobileprovision` 实读的，不是写死文案。

**先跑一屏再铺开**（`/appios` 硬约束，有 hook 实拦）：登录 + 一个主界面先装进模拟器看过，
才允许写第 3 个界面。导航范式错了是 N 处返工，不是 1 处。
