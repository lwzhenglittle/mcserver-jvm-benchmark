# Paper 26.2 JVM/GC Benchmark (Minecraft 1.21.x 世代)

可复现的 Minecraft Paper Server JVM/GC benchmark 框架与两轮实验数据。
目标问题:**同一台机器上,Paper 26.2 用哪个 JDK / GC 最快?过载点在哪?**

## TL;DR

- **推荐:`temurin25 -XX:+UseZGC -Xms16G -Xmx16G`**(或 Shenandoah)
- 8 核(Ryzen 7 5700X,WSL2)容量上限 **~150 并发玩家**(mixed 负载);200 人服务器崩溃性过载
- ≤100 人时 JDK/GC 选择几乎无差异(<2ms,噪声级);>100 人时 ZGC/Shenandoah 比 G1 好 ~35%,Parallel 最差
- baseline(openjdk25/oracle25 零参数)≈ temurin25+G1+16G——**厂商无魔法,差距全在 GC**

详细数据:[docs/round2-results.md](docs/round2-results.md)、[docs/round1-results.md](docs/round1-results.md)、[docs/round3-novia.md](docs/round3-novia.md)(Via 开销实验:原生 26.2 bot 反而慢 ~19%)

## 实验总览

| | Round 1 | Round 2 |
|---|---|---|
| 问题 | 11 runtime × GC × 3 workload,谁最快 | 晋级组合 × 玩家数 scaling,过载点 |
| 组合 | 33(11 runtime/GC × 3 workload) | 7(2 baseline + 5 晋级) |
| 轮数 | 99(33 × 3 reps) | 84(7 × 4 档 × 3 reps) |
| 玩家 | 25 | 25 / 50 / 100 / 150 |
| 堆 | 8G | 16G |
| warmup/measure | 600s / 600s | 600s / 600s |
| 结果 | 0 失败,0 掉线 | 0 失败,0 掉线 |

## 仓库结构

```
bots/            mineflayer 无头玩家负载发生器(bot.js)
config/          固定配置:jdks.yaml(运行时清单)、paper-*.yml、server/(server.properties 等)
docs/            spec.md(实验需求)、methodology.md(方法学)、round1/round2-results.md、exploration.md
results/         round1-runs.csv(99)、round2-runs.csv(84)、round1-summary.csv
scripts/         全部 harness:run-min-bench.sh(单轮)、run-matrix.sh(R1)、run-scaling.sh(R2)、
                 aggregate.py(聚合)、build-golden-world.sh、mk-workspace.sh、proc-collect.sh、smoke-paper.sh
ticklogger/      自研 Paper 插件:逐 tick MSPT 写 CSV(System.nanoTime,零分配热路径)
plugins.sha256   插件版本锁定
```

## 复现(概要)

```bash
# 前置:sdkman 安装 JDK(见 config/jdks.yaml),node >= 18,pip/none
cd bots && npm ci
./scripts/build-golden-world.sh          # 生成并锁定 golden world(pregen 512 + entity-redstone 区)
./scripts/smoke-paper.sh                  # 冒烟
# 单轮
./scripts/run-min-bench.sh --runtime temurin25 --gc zgc --workload mixed \
    --players 100 --warmup 600 --measure 600 --heap 16G \
    --workspace workspaces/ws0 --port 25565 --cores 0-7 --botcores 8-15
# 矩阵
./scripts/run-scaling.sh                 # R2:84 轮 ~28h
python3 scripts/aggregate.py 'runs/*'    # 聚合每轮统计到 CSV
```

方法与陷阱(join storm、预生界约束、时长敏感性等)见 [docs/methodology.md](docs/methodology.md)。

## 环境(结果仅在此环境下成立)

- AMD Ryzen 7 5700X(8C/16T,SMT 开),62GB RAM,单 NUMA
- **WSL2**(kernel 6.18.33.2-microsoft-standard),ext4 on vhdx——非裸机,governor/perf 不可控
- Paper **26.2-129**(sha256 锁定,要求 Java 25+),Java 25 运行时矩阵
- 插件:TickLogger(自研)、Chunky(pregen)、spark、ViaVersion/ViaBackwards(bot 用 26.1 协议)
