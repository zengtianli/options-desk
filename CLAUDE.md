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

> **2026-08-29 ssh 实测补充:比原来记的更彻底** —— VPS 上 `/var/www/web-stack` 整个目录不存在、
> 无任何 `tlz-*` systemd unit、无 nginx vhost、8621 无监听、`/var/www/cc-options/data` 缺失;
> configs repo 有一条 commit「退役 mindmap/n8n/stockoptions(2026-06-03 用户钦定砍单)」。
> 所以那个 API **不是「改数据源」就能用**,是「改源 + `/ship new` 四件全新
> (subdomains.yaml + CF DNS/Origin Rule + authgate + nginx vhost + systemd unit)」两件事。
> 顺带查实:`com.tianli.investment-eod-review.plist` 是**哑弹不是定时炸弹**
> (未加载、`~/Library/LaunchAgents/` 无副本、它指的 `eod_cron.sh` 根本不存在),已退役到 Trash。

**三个月里没有任何东西报过警。** 死因：同步挂在一个「Mac 得在 17:00 醒着」的
LaunchAgent 上，那个前提一破，整条链无声停摆。

由此两条硬约束，删一条这个 app 迟早重蹈覆辙：

1. **同步挂在用户每天真的会做的那件事上** —— `review_run.py`（写复盘必跑）顺带推
   quant.db。**不要再挂 LaunchAgent**：习惯不会静默死，cron 会。
2. **数据陈旧必须在界面上刺眼**，而不是安静地显示一个旧数字。
   同源教训：2026-08-28 blog-reader 的 blog-options 站因为撞访问闸静默贡献 0 篇，
   错误条上只有一句「解析失败」——既不像错误也指不出方向。

## 首屏放什么（**不是年化**）

2026-08-29 回填完 `qqq_close` 之后重算，**已拍板口径**（两账户合并总账 · 逐日链接 TWR ·
当日现金流计入期初基数）：

```
区间      2026-06-09 → 2026-08-28   54 个 session / 53 个链接,已记录净入金 $115,570
TWR 累计  +22.45%   ← ⚠ 暂定值,见下
QQQ 同窗  +1.22%
★ 超额    +21.23pp        ← 回填之前这一栏根本算不出来
年化      +161.9% ± 76pp  一倍标准误区间 [85%, 238%]
年化波动  35.0%(QQQ 24.2%,比 1.45x)
```

> **2026-08-29 二次订正,别抄上一版的数。** 上面这批比我先前报的低,不是算错了,
> 是**归日口径修好了**:快照不是收盘时刻拉的,`asof` 是「我什么时候跑的 dump」。
> 全库 156 行里 **44 行**(28%)`substr(asof,1,10)` ≠ 真 session。改按
> `quantlab.tcal.session_of` 归日之后 —— 样本 50 → **54 天**、
> TWR 23.35% → 22.45%、QQQ 1.88% → 1.22%、超额 21.48 → **21.23pp**。
> 数字全部来自 `/api/desk-summary` 实跑响应,不是手算。

⚠ **这个 +22.45% 是暂定值,不是结论。** 54 个 session 里 **18 天的 `net_deposit` 是 NULL**
(全部 ≤2026-07-09),那段资金流动一条没记。TWR 的分母是「期初市值 + 当日现金流」,
缺一笔那天的收益率就是错的,**而且错得毫无痕迹** —— 一笔没记的入金会被当成投资赚来的钱。
情景对照(合并总账):

| 情景 | 累计 | 超额 | n |
|---|---|---|---|
| 06-18 按**内部划转**计（首屏口径 = 保守端） | +23.36% | **+21.49pp** | 52 链接 |
| 06-18 按**外部提现**计 | +27.22% | **+25.34pp** | 52 链接 |

**这两行现在由服务端算，不是手写的** —— `/api/desk-summary` 的 `flow_scenarios` /
`excess_range`，app 首屏直接印区间。理由见下。

**2026-08-29 证据升级(MCP 权威侧,不是从库里推)**:06-18 那笔 **确定是现金离开
`700013444`,不是亏掉的** —— `get_realized_pnl` 显示该账户整个六月只有 06-18 有成交、
realized 仅 **−$2,686**(11 笔);`get_pnl_trade_history(span=all)` 全历史就那 11 笔期权平仓、
**无任何 transfer 行**。当天 NLV 60,004 → 21,374(约 −38,630),交易只解释 2,686,
剩 ≈35,944 是现金走掉的。该账户整本账因此闭合到 **$0.80**
(入 10,000 期初 + 50,000 自 5UK;出 35,939.30 + 21,373.90;交易亏 2,686)。

**仍未定的只有「去哪了」**,而它只有两种可能、**两端都算得出来** —— 所以现在给区间,
不再挂一个开放式「暂定值」。**区间可以拿来决策,开放式的不确定不行。**
另两笔(06-11 的 $50,000、06-22 的 $21,373.90)有镜像证据 = 账户间内部划转,
在合并总账里一出一进相互抵消,**对区间没有贡献**。

MCP 确无 transfers/deposits/statements 接口(逐个加载 `get_accounts` / `get_portfolio` /
`get_realized_pnl` / `get_pnl_trade_history` 四个真 schema 确认)。月结单到手后,
删掉 `api.py` 里 `desk_summary` 的那段 `OPEN_FLOWS`、并往
`reconcile_net_deposit.CONFIRMED_CORRECTIONS` 加**两条**(两个账户各一条)即可。

**误差带是估计值的一半** —— 「年化 194%」和「年化 110%」统计上分不开。
把它做成首屏大字 = 每天剧烈跳动且没有信息量。年化对输入还特别敏感：换个合并口径，
累计只动 1.2pp 而年化动 15pp。

超额**扛得住风险调整**（beta 0.85 / 波动比 1.45x / 波动配平后仍 **+14.30pp**），但别当能力证据：
Sharpe 2.92 **± 2.20**（两倍标准误跨过 0，区间 [−1.48, 7.32]），相关只有 0.59，
且这 53 个链接日里 QQQ 净走 +1.22%、中途下探 −6.5% 又冲高 +5.1% —— 正是卖方结构最舒服的震荡市。
**这是 regime-conditional 的结果，不是可外推的 edge。**

> 「波动配平后 +20.6pp」是上一版的数,**报高了 6.3pp** —— 那时基准序列整体错位一天。
> 现值 +14.30pp,仍然为正,结论方向不变。

所以：**首屏 = 累计收益 + 对 QQQ 的超额 + 样本天数**（这三个稳、可解释）；
年化 / Sharpe 放二级页，**旁边必须同时印标准误和样本长度**。等序列过了一年再让它当主角。

## 开工前必须先修的三个口径坑（全在服务端，不在 app 里）

进度与证据全文见 `handoffs/data-truth-fix.md`。

| 坑 | 实测（2026-08-29 重核） | 状态 |
|---|---|---|
| `qqq_close` 缺一半 | 主账户 77 行里 22 行空，且是干净前缀空洞（全部 ≤07-10） | ✅ **已修，0/77 空洞**。注意：库里唯一日频 QQQ 表 `klines` 停在 06-05，补不上 —— 价格取自 RH MCP `get_equity_historicals`，回填器 `~/investment/options/robinhood/backfill_qqq_close.py` |
| 序列太短 | `rh_history` 从 **2026-06-09** 起，53 个链接日（54 个 session） | ⛔ **无解，只能等**。处理方式＝不在首屏放需要长样本的数（年化/Sharpe/回撤） |
| **归日口径错 28%** | 快照不是收盘时刻拉的：`2026-08-05T00:15 PT` = ET 凌晨 3:15，属于 **08-04**。全库 156 行里 **44 行** `substr(asof,1,10)` ≠ 真 session | ✅ **已修**。`session` 列物化进库（`derive_session.py`，判据走 `quantlab.tcal.session_of`，不另建第二套时区规则）；`api.py` 的 `_DAILY_SQL` 与对账守卫全部改读它。回归 3 条 + 反向验证 |
| `qqq_close` **不是收盘价** | 它记的是**拉数那一刻的报价**。标签 `2026-07-31` 的三条快照分别是 683.55（07-30 收盘）/ 661.73（07-29 收盘）/ 683.29（某个盘中价）—— 没有一个是 07-31 收盘 | ✅ **已修**。`backfill_qqq_close.py --repair` 按 session 从权威日线整列重写，**校正 25 行**，反向验证 0 行不符。`interpolated: true` 的 gap-fill 假 bar 挡在 CSV 外 |
| `rh_settlements` 缺 `settlement_date` | 指派现金按 expiry 记账而 RH 按 T+1 结算日入账 → 成对反号假红（08-21 −328 万紧跟 08-24 +321 万） | ✅ **已修**。`derive_settlement_date.py` 按 T+1 派生（日历同一份 SSOT），63 行全填、幂等、反向验证绿；对账假红 **33 → 20** |
| `net_deposit` 稀疏 | **比原以为的严重得多**：主账户前 22 行**全是 NULL**（2026-07-09 之前的资金流动一条没记），那两笔 29,570/86,000 不是「全部入金」只是「开始记账之后的入金」 | 🔧 已建 fail-closed 对账守卫 `reconcile_net_deposit.py`（现金恒等式反算，残差 >$50 判红），**一个字没往库里写** —— 06-18 那笔 $35,939 的定性缺证据，不猜 |

> `700013444` 的 `qqq_close` 全空**不是缺口** —— 它是市场基准数不是账户属性，挂主账户一份就够。

### 再修完口径之前,别信这几个数

本轮实测挖出的、会影响首屏的其他洞（全部有命令输出支撑）：

| 洞 | 实测 | 影响 |
|---|---|---|
| 第二账户轨迹**不是**单调归零 | `700013444` 是 10,000(06-09) → **60,004(06-11)** → 21,374(06-18) → 0.06(06-22 起 60 行恒定)。中间有一笔 5 万入金 | 之前「从 $10,000 掉到 $0.06」的说法是抽样看出来的，**错的**。全 77 行才看得见那笔 5 万 |
| ~~交易日数缺 7 天~~ | ✅ **2026-08-29 证伪**：那 7 天里有 **4 天其实有快照**，只是被记到了次日名下（凌晨拉的 dump）。按 session 归日，每户 **54 个 session**，真缺的只有 **3 天**：06-17 / 06-26 / 07-07 | 分母从 50 变 54。「缺 7 天、无解只能等」是错的 —— 一半是归日 bug，不是数据缺失 |
| 同日多快照 | 13 个日子有多条（07-31 一天 9 条；06-25 的 16:00 与 16:14 两条 nlv 只差 26.60 而 cash 差 497,300） | 日粒度取「同 **session** 内最晚一条」。⚠ 裸 `substr(asof,1,10)` 不只是挑错行，是**归错天** |
| `net_deposit` 的 0 与 NULL | `fetch_data.append_history` 里 `dep = _f(marks.get("net_deposit")) or 0.0` —— dump 没带这个字段时**写 0 而不是 NULL**，即「当天没有外部流水」被断言成事实而不是未知 | 07-09 之后的 0 全是这么来的。多数天确实没流水，所以这个假设通常对；但它一旦错，错法和缺 NULL 一样无痕。**未改行为，先记在这里** |
| ~~`rh_orders` 疑似分页截断~~ | ✅ **已证伪**（2026-08-29 拿 MCP `get_option_orders` 分页拉全 07-01~08-27 与库逐单对 ID）：权威侧 335 单 / 库 323 单 / 库多 0；缺的 **12 单全部是 `cancelled` 且 premium 全为 0，净现金影响 $0.00** | 「恰好 1000 行」是巧合不是截断（截断会砍最老的，而缺的散在中间）。**对账守卫不是建在流沙上**，它报的那些 ±$7 万~±$320 万残差与漏单无关 |
| `rh_settlements` 六月零行 | 最早 expiry = 2026-07-10；且缺 `settlement_date` 列（按 expiry 记账产生成对反号假红） | 06-18 那 +620,801 的指派现金无从对账，悬案因此定不了 |

## 已对齐的决策（2026-08-28，用户拍板）

- **新建本 app**，不并进 `options-calc`。
- **先修口径再建界面** —— 现在建，超额那栏一开始就是空的；而且 app 建完再改口径，两边都要动。
- **两个账户合并成一个总账**（`5UK56277` + `700013444`）。「我的钱表现如何」本来就该是合并口径；
  分账户看是运维视角不是投资视角。

## 线上（2026-08-29 上线）

```
https://desk.tianli.cyou          authgate 闸内 · noindex · 不进任何导航
  /                               一页说明（/var/www/desk）
  /api/desk-summary               首屏三个数（app 只吃这一个端点）
```

VPS 侧三件：`tlz-optionsdesk.service`（`uvicorn api:app` @ `127.0.0.1:8642`，User=www-data）·
vhost SSOT `~/Dev/tools/configs/nginx/vps/desk.tianli.cyou`（改完走 `nginx_ship`，**禁在 VPS 上直接改**）·
库副本 `/var/lib/tlz-optionsdesk/quant.db`。

**数据怎么上去的**：`review_run.py`（写复盘必跑）跑完顺带调 `push_quant_db.py` 推库
—— **不挂 LaunchAgent**，那正是前身的死因。推失败不拦复盘，只告警；
另一道是 app 首屏那条陈旧度条，几小时内自己变色。两道指向同一件事。

`/ship new` 的 `station_ship.py` **只做静态站**（rsync 一个含 index.html 的目录 + 静态 vhost），
所以这次是拆开走的：`ssot/dns/origin/access` 交给它，nginx vhost 与 systemd unit 按 VPS 上
现成的 `edu-points` 范式手落（仍走 `nginx_ship` 下发、仍登记 vhost 归属）。

> 路上修了总部一个真 bug：`cf_api.py origin-rules add` 用 `expr.rfind('"')` 定位插入点，
> 而那条规则的表达式尾部是 `... or starts_with(http.host, "app")` ——
> 新 host 被插进了 `starts_with` 的参数里，`starts_with(http.host, "app" "desk.tianli.cyou")`。
> 是 CF 报 400 才拦住的，**它的错误信息完全不提插错了位置**。已改成定位 `http.host in {…}` 集合本身。

## 凭证

复用 blog-reader 那套（2026-08-28 验过，零手工）：`Gate.swift` + `seed-gate.sh`，
密码存 **macOS 钥匙串**（`security -s tlz-gate`），装机时用 `-gatepw` 启动参数喂一次，
app 验过写进 iOS 钥匙串。

`Gate.swift` 从 blog-reader **移植不重写**（契约 6），只改 Keychain 的 service 标识。
撞闸的判据是**最终 URL 落在 `/_gate/` 下**，不是状态码 —— URLSession 会跟着 302，
到手的是登录页的 **200 HTML**，状态码分辨不出来；嗅 HTML 内容则是给页面文案建第二份判据，改个字就瞎。
`DeskError` 为此单列 `.gate` 一档：混进 `.decoding` 会显示成「数据对不上契约」，把人引向服务端去查。

## 选源（启动参数）

| 参数 | 源 |
|---|---|
| （默认） | `https://desk.tianli.cyou` —— 装到手机上点开就是真数 |
| `-apiBase <URL>` | 指别处，如本机调试 `-apiBase http://127.0.0.1:8799` |
| `-sample` | 本地样本，不联网（截图/离线调试用） |

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
