# options-desk · 投资盘面（iOS）

只读盘面：净值 / 累计收益 / 对 QQQ 的超额 / buffer / 票据梯子。
回答「我现在怎么样」，不回答「如果我开这个结构会怎样」——后者是姊妹 app
[`options-calc`](../options-calc)（期权决策台）。

数据来自每日复盘那条链（Robinhood MCP → `quant.db` → `review_run.py`），
**不新建账本**。详见 [CLAUDE.md](./CLAUDE.md)。

```bash
./sim-run.sh              # 模拟器
./install-to-iphone.sh    # 真机（付费 team，证书 1 年期）
```
