# options-desk 数据口径修复 · handoff

> 建于 2026-08-29（口径走 `systime.py`＝上海；harness 注入的 `currentDate` 早一天，别照抄）。
> 目标：**先修口径再建界面**。界面在口径修完之前不动 —— 现在建，首屏最重要那栏是空的。

## 三个目录各管一段

| 目录 | 本轮状态 |
|---|---|
| `~/investment/options/robinhood/` | qqq_close 回填 ✅ · net_deposit 对账 / 新鲜度守卫 → 见下 |
| `~/Dev/stations/web-stack/services/stockoptions/` | API 数据源换 quant.db → 见下 |
| `~/Apps/ios/options-desk/`（本目录） | 客户端，口径修完再动 |

---

## ✅ 已完成：坑 #1 `qqq_close` 缺一半

**这是首屏「对 QQQ 超额」那栏算不出来的唯一原因，本轮已解除。**

- 空洞：`5UK56277` 77 行里 22 行为空，且是干净的前缀空洞（全部 ≤ 2026-07-10，首个有值日 2026-07-09）。
- **原计划的补法是错的**：库里唯一带日频 QQQ 收盘的表 `klines` 停在 **2026-06-05**，
  正好在空洞开始前 4 天断掉，一天都补不上。`rig_equity_QQQ` 是月频回测曲线、
  `asset_universe_*` 是汇总统计，都不是日频价。
- 实际补法：Robinhood MCP `get_equity_historicals(QQQ, interval=day, bounds=regular, adjustment_type=split)`
  → 落盘 `~/investment/data/qqq/qqq_daily_close_2026-06-05_2026-07-14.csv`（含 `source` 列，口径可追溯）
  → `~/investment/options/robinhood/backfill_qqq_close.py --csv <上面那个> --apply`。
- 脚本**幂等、默认 dry-run、只填 NULL 不覆盖已有值、改库前自动备份**，价格源为空即非零退出。
- 2026-07-03 是美股休市（7/4 观察日），价格源里标为 `carry_forward_market_holiday_jul4_observed`
  ＝沿用 07-02 收盘，当日 QQQ 日收益为 0。这是**我们定的口径，不是原始数据**。
- 反向验证三道：重跑报「无空洞」/ 库里直查 `holes=0` / 首尾抽值比对 → 07-09、07-13、07-14
  与既有值逐分对上（07-10 差 3 分：historicals 的 close 不是官方结算价，量级 0.004%，不影响）。

结果：`5UK56277` 空洞 **22 → 0（77/77）**。
备份在 `~/investment/data/quant.db.bak-20260828-101319`（⚠ 这是即时撤销的网不是备份，真备份看 git/VPS）。

> `700013444` 仍是 77 行全空 —— **这不是缺口**。qqq_close 是市场基准数、不是账户属性，
> 挂在主账户行上一份就够；合并总账时取该日任一非空值即可。别去"补齐"它，那是把同一个数存两遍。

## ⚠️ 首屏数字重算（回填后第一次能算超额，但**是暂定值**）

口径：两账户合并总账 · 逐日链接 TWR · 当日现金流计入期初基数。

```
区间      2026-06-09 → 2026-08-27    49 个链接日 / 50 个快照日
净入金    $115,570      期初 NLV $1,009,444 → 期末 $1,365,066
TWR 累计  +23.35%
QQQ 同窗  +1.88%   (707.83 → 721.11)
★ 超额    +21.48pp    ← 回填前这一栏根本算不出来
年化      +194.3%  ± 85pp   一倍标准误区间 [110%, 279%]
年化波动  37.4%
```

**敏感性（最敏感的两个输入各动一次）**：

| 变体 | 累计 | 超额 | 年化 |
|---|---|---|---|
| 合并总账 · 现金流期初（已拍板口径） | +23.35% | +21.48pp | +194% |
| 只主账户（排除 $0.06 死账户） | +24.59% | +22.71pp | +210% |
| 合并总账 · 现金流期末 | +23.23% | +21.36pp | +193% |

现金流期初/期末口径只差 0.12pp，无所谓；合并与否差 1.2pp（累计）/ 15pp（年化）——
**年化对输入的敏感度是累计的十倍以上**，又一条「年化不配上首屏」的证据。

**风险调整后超额没被吃掉**（这条要先自我证伪再信）：

```
beta(对 QQQ) 0.83    相关 0.57    组合/QQQ 波动比 1.46x
波动配平超额 +20.61pp     Jensen 式超额 +21.80pp
组合 Sharpe 3.07  vs  QQQ 0.50
```

但 **Sharpe 3.07 ± 2.29**（一倍标准误 [0.78, 5.36]，两倍就跨过 0）。49 天的 Sharpe 不是能力的证据。
且相关只有 0.57 —— beta 回归解释不了多少，残差风险占大头，说明「对 QQQ 超额」这个框架本身
在这个样本长度上就很弱。再加一条：这 49 天 QQQ 只走了 +1.88% 且中途下探到 693，
**正是卖方结构最舒服的震荡市** —— 这个 +21pp 是 regime-conditional，不是可外推的 edge。

→ 对首屏设计的结论**不变且更硬**：累计收益 + 超额 + 样本天数上首屏；
年化 / Sharpe 一律进二级页且必须与标准误、样本长度同框。

### ⛔ 但这批数字全部是暂定值 —— 现金流数据不完整

本轮新建的对账守卫 `reconcile_net_deposit.py`（现金恒等式反算）实跑 5UK56277 六月区间，
**它自己的结论行**就是：

```
→ net_deposit 在这些日子是错的（漏记资金流），基于它算出的 TWR / 累计收益 / 超额收益不可用。
```

50 个交易日里 **17 天 `net_deposit` 是 NULL**（全部 ≤2026-07-09）。情景对照：

| 情景 | 累计 | 超额 | n |
|---|---|---|---|
| 未知现金流全当 0（上面那组数的口径） | +23.35% | +21.48pp | 49 |
| 06-18 那笔 $35,939 按**提现**计 | +27.66% | +25.78pp | 49 |
| 起点挪到 06-23（两笔悬案都在起点之前） | +10.51% | +9.46pp | 42 |

**能确定的方向**：已定性的两笔（06-11 的 $50,000、06-22 的 $21,373.90）都有镜像反号证据 =
**账户间内部划转**，在合并总账里一出一进相互抵消，**对上表不产生影响**。
唯一悬着的 06-18 若定性为提现，累计收益**更高不更低** —— 所以 +23.35% 是那项不确定性的保守端。
第三行的 +10.51% **不是「更正确的数」**，只是丢掉了前两周（那两周真赚了 11.6pp）；
别因为它规避了假设就直接采用。

**唯一能了断的证据**（自动化拿不到，本会话可见的 `mcp__robinhood-trading__*` 里没有任何
transfers/deposits/statements 接口）：2026-06 月结单 PDF 的 Transfers / Cash Movement 段，
或 App → Account → Transfers → Transfer history 筛 06-18~06-19。**这条要人工取一次。**

## 🔧 进行中（并行车道，本轮工作流 `wf_c390f3ad-dbe`）

1. **坑 #3 `net_deposit` 对账** —— 见下「新发现」。
2. **新鲜度守卫挂进 `review_run.py`** —— 前身 cc-options 就是死在 LaunchAgent 上，
   禁再挂 cron；挂在「用户每天真的会做的那件事」上。
3. **stockoptions API 数据源换 quant.db** —— 禁新建第二个 API；响应必带 `asof` + `staleness_days`。

## ⚠ 新发现：第二个账户是空的，且有一笔一万块没有记录

「两账户合并成总账」这个决定本身没错（口径上就该合），但它带来的不是「更全的账」：

**⚠ 先前写在这里的「从 $10,000 单调掉到 $0.06」是错的** —— 那是抽样（每 8 行取一条）看出来的，
跳过了中间那笔 5 万。全量看是这样：

```
700013444    06-09  10,000.00
             06-11  60,003.76   ← 一笔 $50,000 进来(此前无人记录)
             06-16  60,595.26
             06-18  21,373.96   ← 划出 $35,939.30
             06-22       0.06   ← 划出 $21,373.90,此后 60 行恒定
```

现金对账闭合：`10,000 + 50,000 − 2,686(交易亏损) − 57,313.20(两笔划出) = 0.80`，
实际期末 0.06，差 0.74 是手续费级。所以**那一万块既没亏掉也没消失，是被划走的**。
交易只亏 $2,686（`SELECT SUM(net_cash) FROM rh_orders WHERE account='700013444'` = −2686.0，
与 `options/_archive/agentic_longvol_postmortem.json` 的 `realized_total: -2686` 逐字一致）。

合并 TWR 时如果不把这笔当 CONTRIBUTION/WITHDRAWAL 处理，链接收益率里会挂一个假的
接近 -100% 的单日。权重极小（$10k vs $1.36M，实测对累计的影响 1.2pp）但性质是**脏数据不是噪音**。
**三笔里两笔已定性**（06-11 的 $50,000 从 5UK 划来、06-22 的 $21,373.90 划回 5UK —— 都有 5UK 侧
镜像反号未解释项佐证，差额分别 $25.60 / $1.58）。**只剩 06-18 那笔 $35,939.30 定不了**：
5UK 同窗未解释项是 +620,801.63，主体是约 700 股 QQQ 被叫走的指派现金，而
`rh_settlements` 六月零行、`rh_equity_orders` 早于 06-17 不完整，3.6 万从 62 万里剥不出来。

## 坑 #2 序列太短：无解，只能等

`rh_history` 从 2026-06-09 起，49 个链接日。这不是能修的东西 ——
唯一的处理是**不要在首屏放需要长样本才有意义的数**（年化、Sharpe、最大回撤）。已按此设计。

## ✅ 已了断：`rh_orders` 到底完不完整

工作流两个 agent 都把这条列成 blocker（「恰好 1000 行，疑似 API 分页截断，所有对账都建在
『订单表完整』这个未验证假设上」）。本会话有 MCP，**直接验掉了**：

```
窗口 2026-07-01 ~ 2026-08-27（库覆盖到的范围）
  MCP 权威侧  335 单     ← get_option_orders 分页拉全，2 页，next 已耗尽
  库里        323 单
  库缺         12 单     ← 全部 state=cancelled，processed_premium 全 0
  库多          0 单
  12 单净现金影响  $0.00
```

**结论**：① 不是分页截断 —— 截断会砍掉最老的一批，而缺的 12 单散在 07-29/08-03/08-04/08-05
中间；「恰好 1000 行」是巧合。② 对账守卫**不是**建在流沙上，它报的 ±$7 万~±$320 万残差
与漏单无关，那些是 settlement 记账时点差 + 真实的 `net_deposit` 缺记。
③ 缺失有部分规律：07-29/08-03 的缺单对应**次日没跑 dump**（07-30、08-04 都在那 7 个缺失快照日里），
但 08-05 前后两天都有快照却仍缺 4 单 —— **还有第二个机制没查清**，不过既然全是 cancelled 零现金，
不影响任何口径结论。

## 待办

**本轮已完成（全部 commit + push）**

- [x] qqq_close 回填 22 行 → 主账户 0/77 空洞；回填器 + 价格源带 provenance 进仓
- [x] net_deposit fail-closed 对账守卫 `reconcile_net_deposit.py`（12 条反向验证，**一个字没写库**）
- [x] 数据新鲜度守卫挂进 `review_run.py`（不挂 cron；陈旧 → 醒目告警 + 非零退出码；反向验证四红一绿）
- [x] 哑弹 `com.tianli.investment-eod-review.plist` 退役到 Trash（实测未加载、它指的 `eod_cron.sh` 不存在）
- [x] stockoptions API 三端点换源 quant.db + 合并总账 + `staleness` 信封
- [x] 新增 `/api/desk-summary`（首屏三个数，**复用 `_twr_curve` 不写第三份实现**）
- [x] iOS 首屏 + Live 数据源接通，**端到端跑通**：`quant.db → api.py → 模拟器`
- [x] `rh_orders` 分页截断悬案 → **证伪**（缺的 12 单全是 cancelled、零现金）
- [x] `~/Apps/ios` 两个 app 补登记 harness.yaml

**真正剩下的**

- [ ] **[P0] ⏳[external]** 06-18 那笔 $35,939.30 定性 —— **只能人工取一次**：
      2026-06 月结单 PDF 的 Transfers / Cash Movement 段，或 App → Account → Transfers →
      Transfer history 筛 06-18~06-19。本会话可见的 `mcp__robinhood-trading__*` 里
      **没有任何 transfers/deposits/statements 接口**，自动化拿不到。
      拿到后往 `reconcile_net_deposit.py` 的 `CONFIRMED_CORRECTIONS` 加一行即可幂等写库。
- [ ] **[P0]** 把 `reconcile_net_deposit.py` 也挂进 `review_run.py`（新鲜度守卫已挂，对账守卫还没）
- [ ] `rh_settlements` 补 `settlement_date` 列（现按 expiry 记账，产生成对反号假红）；
      并回补 2026-07-10 之前的六月行 + `rh_equity_orders` 06-17 之前的行
- [ ] `rh_history` 去重 + 补 7 个缺失交易日（06-10/06-17/06-29/07-06/07-08/07-30/08-04）
- [ ] `review_audit.missing_for()` 的 ① 判据从「dump 文件存在」升成「文件存在**且**库已落进去」
      （agent 已查清调用点，刻意没动：会连锁到 `review_auto.py` 的收敛循环）
- [ ] API 上线 —— **不是「跑一下 deploy.sh」**：VPS 上零部署面，是 `/ship new` 四件全新
      （subdomains.yaml + CF DNS/Origin Rule + authgate + nginx vhost + systemd unit）
- [ ] Gate 凭证移植（真机装机才需要；模拟器阶段用 `-apiBase` 启动参数即可）
- [ ] `/api/scenarios` `/api/roll-signals` 仍 503（pre-existing）；`/api/twr` 等仍读停更的旧 JSON

## 本轮已落盘的文件

```
~/investment/options/robinhood/backfill_qqq_close.py          新建,幂等回填器
~/investment/data/qqq/qqq_daily_close_2026-06-05_2026-07-14.csv  新建,价格源(带 source 列)
~/investment/data/quant.db                                     22 行 qqq_close 写入
~/Apps/ios/options-desk/handoffs/data-truth-fix.md             本文件
```

远端：`~/Apps/ios/options-desk` 已建私库 `github.com/zengtianli/options-desk` 并 push。

---

## 2026-08-29 第二轮 · 归日口径 + 上线（本轮把待办清零）

### 一、发现：`rh_history` 的日期标签有 28% 是错的

`asof` 不是收盘时刻，是「我那天什么时候跑的 dump」。全库 **156 行里 44 行**
`substr(asof,1,10)` ≠ `quantlab.tcal.session_of(asof)`：

```
2026-08-05T00:15:54-07:00   → ET 03:15，还没开盘 → 属于 session 2026-08-04
2026-07-10T22:28:54-07:00   → ET 次日 01:28，已收盘 → 仍属于 session 2026-07-10
```

**两条我先前写下的「事实」因此被推翻**：

| 先前写的 | 实测 |
|---|---|
| 「缺 7 个交易日，⛔ 无解只能等」 | 真缺 **3 天**（06-17 / 06-26 / 07-07）。另 4 天（06-10 / 06-29 / 07-06 / 07-08 / 07-30 / 08-04 中的）有快照，只是被记到了次日名下 |
| 「`qqq_close` 已修好（0/77 空洞）」 | 空洞是填上了，但**填进去的口径本身就错**：那一列记的是**拉数那一刻的报价**，不是收盘价。标签 `2026-07-31` 的三条快照分别是 683.55（= 07-30 收盘）/ 661.73（= 07-29 收盘）/ 683.29（某个盘中价），没有一个是 07-31 收盘 |

### 二、修法（三个脚本，都幂等 + 备份 + 反向验证）

| 脚本 | 做什么 | 结果 |
|---|---|---|
| `derive_session.py` | 物化 `rh_history.session` 列，判据 = `tcal.session_of`（**不另建第二套时区规则**） | 156 行全写，54 个 session |
| `backfill_qqq_close.py --repair` | 按 session 从权威日线**整列重写** `qqq_close` | 校正 **25 行**，反向验证 0 行不符 |
| `derive_settlement_date.py` | `rh_settlements` 补 `settlement_date`（T+1，日历同一份 SSOT） | 63 行全填，对账假红 **33 → 20** |

消费端同步改读 `session`：`api.py` 的 `_DAILY_SQL` / `/api/meta`、`reconcile_net_deposit.py` 的日粒度。
`fetch_data.py` 两个 writer 也改了，新 dump 自带这两列。

### 三、首屏数字重算（全部来自 `/api/desk-summary` 实跑响应）

| | 第一轮报的 | 修完口径 |
|---|---|---|
| 样本 | 50 天 / 49 链接 | **54 天 / 53 链接** |
| TWR 累计 | +23.35% | **+22.45%** |
| QQQ 同窗 | +1.88% | **+1.22%** |
| 超额 | +21.48pp | **+21.23pp** |
| 年化 | +194.3% ± 85pp | +161.9% ± 76pp → [85%, 238%] |
| beta / 相关 | 0.83 / 0.57 | 0.85 / 0.59 |
| Sharpe | 3.07 ± 2.29 | 2.92 ± 2.20（2SE 跨 0） |
| **波动配平后超额** | +20.6pp | **+14.30pp** ← 我上一轮报高了 6.3pp |

结论方向不变（超额扛得住风险调整、但是 regime-conditional 不可外推）。

### 四、上线

```
https://desk.tianli.cyou            authgate 闸内 · noindex · 不进导航
tlz-optionsdesk.service             uvicorn api:app @ 127.0.0.1:8642 · User=www-data
/var/lib/tlz-optionsdesk/quant.db   库副本，由 review_run.py 顺带推（push_quant_db.py）
```

`/ship new` 的 `station_ship.py` **只做静态站**，所以拆开走：`ssot/dns/origin/access` 交给它，
nginx vhost + systemd unit 按 VPS 上现成的 `edu-points` 范式手落（仍走 `nginx_ship`、仍登记 vhost 归属）。

**端到端实跑验过（不是复述部署脚本的退出码）**：

- 边缘未登录 → `302 → /_gate/login`（带 cf-ray + noindex），`/` 与 `/api/` 两条都验
- 边缘带凭证 → `HTTP 200` + 正确 JSON（sessions 54 / +22.45% / +21.23pp）
- 模拟器带钥匙串凭证实跑 → 渲染出真数（`shots/sim-214310.png`）
- 模拟器无凭证 → `.gate` 错误条，点名 URL + 原因 + 下一步动作（`shots/sim-214209.png`）
- `authgate/verify.sh` **33 通过 / 0 失败**

### 五、顺手修的两个别处的真 bug

1. **`cf_api.py origin-rules add`** 用 `expr.rfind('"')` 定位插入点，而那条规则尾部是
   `... or starts_with(http.host, "app")` → 新 host 被插进了 `starts_with` 的参数里。
   是 CF 报 400 才拦住的，**错误信息完全不提插错了位置**。改成定位 `http.host in {…}` 集合本身。
2. **`authgate/verify.sh` 有两条长期恒红的过期期望**（fit `/coach/schedule` 2026-08-17
   已摘掉 authgate-protect 且路径 404；sig `/` 已改成分层准入，`/` 本就是公开的抠图工作台）。
   5 条红全由这两条产生 —— **一张常年红的表，人会整张不看**。已按线上 vhost 实证订正，
   并把伪造 cookie 那节的探测目标换到真的由本闸保护的路径。

### 六、这轮之后还剩什么（都不是「没做完」，是真的做不了）

| 悬着的 | 为什么 |
|---|---|
| 06-18 那笔 $35,939.30 的定性 | MCP 没有 transfers/deposits/statements 接口（ToolSearch 查实）。需要用户拉 2026-06 月结单的 Transfers 段，或 App → Account → Transfers 看 06-18~06-19。拿到证据后往 `reconcile_net_deposit.CONFIRMED_CORRECTIONS` 加一条再 `--apply` |
| 真缺的 3 个 session（06-17 / 06-26 / 07-07） | 没有历史 portfolio 接口可补 |
| `net_deposit` 的 0 与 NULL 被合并 | `fetch_data.append_history` 里 `dep = ... or 0.0`，dump 没带这个字段时写 0 而不是 NULL —— 即「当天没有外部流水」被断言成事实。**本轮未改行为**（改了会让更多天变成「未知」，且多数天确实没流水），先记在这里 |
| 装真机 | 需要用户把 iPhone 连上：`./install-to-iphone.sh && bash seed-gate.sh` |
