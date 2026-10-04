# Phase 1 探索报告（2026-09-30)

## 1. 环境（详见 plan-revision.md §0)

WSL2 / Ryzen 7 5700X 8C16T / 62G / ext4 / 单 NUMA。perf、taskset 可用；governor 不可控；btrfs/reflink 不可用（world 恢复用 rsync)。

## 2. Paper 26.2

- 目标 jar:`paper-26.2-129.jar`,SHA256 `b1d8f6bf…feb083`,MC 26.2(**协议 776**,2026-06-16 发布，"Chaos Cubed")。
- 实测要求 **Java ≥ 25**(JDK 21 启动直接拒绝）。
- 内置 spark v1.10.180（捆绑 profiler)。可用命令实测：`spark tps`(TPS + tick durations min/med/95%ile/max)、`spark tickmonitor --threshold-tick <ms> --without-gc`(逐 tick 超阈值事件）、`spark gcmonitor`。**没有 `spark mspt` 子命令**（已实测，打帮助）。

## 3. Bot / replay 工具调研结论

| 工具 | 现状 | 26.2 可用性 |
|---|---|---|
| **mineflayer**(PrismarineJS) | 活跃；npm 最新 + node-minecraft-protocol 1.68.0 | 直支持到 **26.1**(775);minecraft-data 数据已到 26.3，但协议层停在 26.1 |
| **smashyalts/mcbenchmark**(Go) | 1.1.0-beta,3 stars，最后提交 2026-07-26；架构 = Paper 抓包插件 → trace 编译 → headless 回放，与 prof.md 需求高度吻合 | 目标 **26.1.2**(775)；可通过 docs/PROTOCOL.md 重新生成 packet ID 适配 776 |
| **ViaBackwards** | 5.12.1-SNAPSHOT 支持到 **26.2** | 可作协议桥：775 客户端 → 776 服务端 ✅ **已实测可用** |
| Modrinth "MCBenchmark" 插件 | 服务端负载生成插件 | 未深入；备选 |

**采用路径**:mineflayer(26.1 协议）+ ViaVersion/ViaBackwards(5.12.1-SNAPSHOT，已 pin SHA256 于 `plugins.sha256`)。已对全部 10 个 runtime 生效且配置一致。后续（P6）若需要玩家行为 trace 回放，再评估 mcbenchmark 的 775→776 retarget（工作量：重新生成 packet ID)。

**风险记录**:Via 翻译层引入少量额外 CPU/数据包处理开销——对所有 JVM 一视同仁，不影响组间公平性；绝对 MSPT 数值不可与无 Via 的裸服直接比较。

## 4. JDK 侧

10 个 Java 25 runtime 齐备（见 `config/jdks.yaml`、`probe/capabilities.json`)。GC probe 实测：Oracle JDK / Oracle GraalVM 无 Shenandoah；其余 HotSpot 系 5 GC 全；OpenJ9 四策略全。

## 5. 已完成管线（P5 验证产物）

- `scripts/probe-jdk.sh` — JDK/GC 探测
- `scripts/smoke-paper.sh` — 启动冒烟
- `scripts/proc-collect.sh` — /proc 采样（CPU%/RSS/VSZ/线程/缺页/上下文切换，comm-safe 解析）
- `scripts/run-min-bench.sh` — 完整一轮：rsync 恢复 golden world → taskset 0-7 启服 → warmup → bots（绑 8-15)→ spark tps/tickmonitor + /proc + GC log → stop → 归档 `runs/<id>/metadata.json`
- `bots/bot.js` — mineflayer 随机游走负载（mulberry32 确定性种子）
- `worlds/golden/world` — golden snapshot(6.7MB,checksum 入 metadata)

**P5 首跑结果**(`runs/20260930-140331-temurin25-g1-p10`):temurin25 + G1 + 10 bots，启动 9s,warmup 3min，测量 5min;10 bots 全程在线无掉线；tickmonitor 捕获 max tick 115ms;spark 报 1min 窗口 tick durations 6.0/7.2/9.0/16.6 ms(min/med/95/max);proc 采样 96 点；GC log 完整。管线判定：**可用**。

## 6. 已知缺口（进 P6 前）

1. MSPT 目前来自 spark 聚合输出（1min 窗口粒度）,**非逐 tick 序列**;prof.md 要求 tick 级时序 → P6 需 spark tickmonitor 全量阈值或 Paper API 插件直采。
2. bot 当前为默认 survival,5 分钟内未死亡；长跑/高负载需 creative 或抗性，避免中途减员破坏负载恒定（P6 处理）。
3. OpenJ9 GC log 机制（verbosegc XML）未接入 run-min-bench.sh（代码内 TODO)。
4. survival-mixed / exploration / entity-redstone-heavy 三类 canonical workload 未实现（P6);golden world 目前是默认生成世界，未含红石/农场构造。

## 7. P6 已完成（2026-09-30)

- **逐 tick MSPT**：自研 `ticklogger/` Paper 插件（`ServerTickEndEvent`，队列+异步写盘，主线程仅 `queue.offer`);`-Dticklogger.out=<run>/mspt.csv` 注入，每 run 产出 tick,epoch_ms,duration_ms,time_remaining_ns 全序列（含 cold/warmup/measurement，不丢弃）。
- **bot 存活**:`gamemode=creative` + `force-gamemode=true`（固定配置，已入 git);bot.js 三模式：`mixed`（游走+挖+放+挥击）、`explore`（定向往外疾跑）、其他值=idle(entity workload 用）。
- **OpenJ9 GC log**:`-Xverbosegclog`(XML）已接入 runner，与 HotSpot unified log 分格式落盘（解析器后续统一进 gc-events.jsonl)。
- **golden world v2**(checksum `a6241fa0…0beab9a`,58MB):chunky 预生成半径 512(4225 chunks)+ 实体红石区（50 对观察者钟、4 条中继器环、20 活塞、150 只 PersistentRequired 羊围栏）,forceload 240-320；构造脚本带 4 项 execute-if-block 自检，失败即中止。`scripts/build-golden-world.sh` 可重建。
- **explore 拆分**:`explore`（跑出预生界=chunk generation）与 `explore-existing`(runner 每 60s `spreadplayers` 圈回预生区）严格分离。
- 验证 run:`runs/20260930-143729-temurin25-g1-p10`(mixed)、`-144144`(explore)、`-144557`(entity)、`-145051-semeru25-gencon-p10`,4/4 成功，mspt.csv/gc.log/proc.txt/metadata 齐。

## 8. 进 P7 前的遗留

1. mcbenchmark trace 回放（775→776 retarget）仍未接；当前负载为 mineflayer 程序化行为，非真实玩家 trace。
2. gc-events.jsonl 统一中间格式解析器未写。
3. 统计聚合/图表（`./bench analyze`）未实现。
4. 每 config ≥5 runs + 随机化顺序（seed 20260930）未自动化。

## 9. 时长敏感性验证（2026-09-30，决定矩阵参数）

同配置双轮对照（temurin25-g1-mixed-p25):A warmup300/measure900,B warmup600/measure900。

| 窗口 | mean | p95 | p99 | max |
|---|---|---|---|---|
| A warmup 最后 5min | 8.94 | 12.72 | **35.49** | 240.5 |
| B warmup 最后 5min(5-10min 段） | 7.75 | 9.50 | 11.41 | 29.5 |
| A 测量 0-5 / 5-10 / 10-15min | 8.01/8.39/9.30 | 9.20/9.63/10.72 | 10.64/10.82/12.00 | 53.0/41.3/44.3 |
| B 测量 0-5 / 5-10 / 10-15min | 8.08/8.56/7.89 | 10.13/11.01/8.95 | 12.10/12.82/10.03 | 33.8/36.3/33.5 |

结论：
1. **warmup ≥ 600s 必须**:5min 时 JIT 仍活跃（p99 35ms),10min 收敛。
2. **measure 600s 可行**:5min 切片与 15min 全窗 mean 偏差 ≤6.5%,p95 ≤10%，与轮间噪声同量级；p999 稳定；max 随窗口大小漂移，仅作参考指标。
3. 用户决策：reps 5→3（偏差已记 plan-revision)，矩阵 99 轮 ≈ 16.5h。
