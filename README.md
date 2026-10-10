# Paper 26.2 JVM/GC Benchmark

在同一台机器上测量 Paper 26.2 服务器在 7 种 JDK/GC 配置、25–150 名模拟玩家负载下的 tick 耗时(MSPT),回答两个问题:**哪个 JDK/GC 最快?过载点在哪?**

## 结论

- **玩家 ≤100:任意默认配置即可。** 7 个配置 mean MSPT 均为 8–20ms,差距在重复间噪声内。
- **过载点在 100→150 人之间。** 150 人时所有配置 mean MSPT 均超 50ms,保不住 20 TPS,无一幸免。
- **过载时只有低暂停 GC 能兜底。** 150 人时 Shenandoah/ZGC(约 58–59ms)领先 G1 系(78–96ms)约 25–39%,领先 Parallel(113ms)约 48%。
- **推荐配置:** 会冲 100+ 玩家用 **Temurin 25 + Shenandoah**(或 ZGC,两者打平;Shenandoah 堆外开销更小);玩家 ≤100 随意。**Parallel 全程最差,不建议使用。**

## 实验结果

150 玩家(过载档,3 次重复平均,MSPT 单位 ms):

| 排名 | 配置 | mean MSPT | >50ms tick 占比 |
|---|---|---|---|
| 1 | temurin25 / Shenandoah | **58.3** | 58.9% |
| 2 | temurin25 / ZGC | **59.2** | 62.4% |
| 3 | oracle25 / 默认(G1) | 78.5 | 92.4% |
| 4 | graalvmce25 / G1 | 82.8 | 94.1% |
| 5 | openjdk25 / 默认(G1) | 87.2 | 97.0% |
| 6 | temurin25 / G1 | 95.6 | 97.9% |
| 7 | temurin25 / Parallel | 113.2 | 99.7% |

25/50/100 玩家三档下,7 个配置 mean MSPT 均在 8–20ms,差异不超过重复间噪声。

完整逐档表格与统计见 [docs/round4-novia.md](docs/round4-novia.md);逐轮原始数据见 [results/round4-runs.csv](results/round4-runs.csv)。

## 实验方法

- **矩阵:** 7 个 JDK/GC 配置(openjdk25/默认、oracle25/默认、temurin25/{G1, Shenandoah, Parallel, ZGC}、graalvmce25/G1)× 4 档玩家数 {25, 50, 100, 150} × 3 次重复 = **84 轮,0 失败 0 掉线**。
- **时长:** 每轮 600s 预热 + 600s 测量;堆固定 16G;世界 seed 固定。
- **负载:** mineflayer 无头 bot 混合负载;bot 走原生 26.2 协议,不装 Via* 插件(已单独验证 Via 对 MSPT 无可测影响)。
- **绑核:** 服务器进程绑核 0–7,bot 绑核 8–15。
- **指标:** 自研 TickLogger 插件逐 tick 记录 MSPT(System.nanoTime)。

### 环境(结果仅在此环境下成立)

- AMD Ryzen 7 5700X(8C/16T),62GB RAM
- **WSL2**(非裸机,governor/perf 不可控)
- Paper **26.2-129**(sha256 锁定,要求 Java 25+),Java 25 运行时

## 复现

前置:sdkman 安装各 JDK(清单见 `config/jdks.yaml`)、node ≥ 18。

```bash
cd bots && npm ci
./scripts/build-golden-world.sh   # 生成并锁定 golden world
./scripts/smoke-paper.sh          # 冒烟测试

# 单轮
./scripts/run-min-bench.sh --runtime temurin25 --gc zgc --workload mixed \
    --players 100 --warmup 600 --measure 600 --heap 16G \
    --workspace workspaces/ws0 --port 25565 --cores 0-7 --botcores 8-15

# 完整矩阵(7 配置 × {25,50,100,150} × 3 reps,约 28h)
./scripts/run-scaling.sh --botversion 26.2 --workspace wsN --port 25567
python3 scripts/aggregate.py 'runs/*'   # 聚合逐轮统计到 CSV
```

方法学细节与陷阱(join storm、预生界约束、时长敏感性等)见 [docs/methodology.md](docs/methodology.md)。

## 仓库结构

```
bots/        mineflayer 无头玩家负载发生器
config/      JDK 清单(jdks.yaml)、paper/server 固定配置
docs/        spec.md、methodology.md、round4-novia.md(完整结果)、archive/(历史轮次)
results/     聚合 CSV(round4-runs.csv 为逐轮数据)
scripts/     harness:run-min-bench.sh(单轮)、run-scaling.sh(矩阵)、aggregate.py(聚合)等
ticklogger/  自研 Paper 插件:逐 tick MSPT 写 CSV
```

更早的实验轮次已归档于 [docs/archive/](docs/archive/)。
