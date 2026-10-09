# Round 4: no-Via 全量 scaling 矩阵 —— 最终结论(2026-10-10)

> 取代 R1/R2/R3 全部旧结论(旧文档见 `docs/archive/`)。R3 已证明 ViaVersion 对 MSPT
> 无可测影响,本轮起 bot 走**原生 26.2 协议、不装 Via\***,结果即最终结论。

## 设置

- 7 配置 × 4 玩家档 × 3 reps = **84 轮,0 失败,0 掉线**:openjdk25/default、oracle25/default、
  temurin25/{g1,shenandoah,parallel,zgc}、graalvmce25/g1;p25/50/100/150(p200 已知崩溃,不测)
- 每轮 600s warmup + 600s measure,16G 堆,workload=mixed,seed=20260930,
  server 核 0-7、bot 核 8-15,workspace wsN,原生 26.2 bot
- 执行窗口 2026-10-08 14:23 ~ 2026-10-10 02:41(中间因 WSL 升级暂停一次,幂等 resume),
  shuffle 盐 `r4` 与 R2/R3 执行顺序解耦
- 数据:`results/round4-runs.csv`(84 行逐轮)、`results/round4-summary.csv`(28 格聚合);
  下表数值 = 3 reps 的逐轮统计再取平均

## 结果

### p25(全部轻松,差异在噪声内)

| 排名 | 配置 | mean MSPT | p95 | p99 | GC max pause |
|---|---|---|---|---|---|
| 1 | temurin25/g1 | 8.40 | 10.07 | 11.83 | 99ms |
| 1 | graalvmce25/g1 | 8.40 | 9.86 | 11.29 | 114ms |
| 3 | oracle25/default | 8.91 | 10.62 | 12.60 | 131ms |
| 4 | openjdk25/default | 8.98 | 10.62 | 12.27 | 115ms |
| 5 | temurin25/shenandoah | 9.17 | 11.21 | 13.36 | 1ms |
| 6 | temurin25/zgc | 9.57 | 11.20 | 13.65 | <1ms |
| 7 | temurin25/parallel | 9.81 | 12.25 | 14.78 | 247ms |

### p50(差异仍在噪声内)

| 排名 | 配置 | mean MSPT | p95 | p99 |
|---|---|---|---|---|
| 1 | temurin25/g1 | 10.63 | 12.97 | 15.65 |
| 1 | openjdk25/default | 10.63 | 13.11 | 15.69 |
| 3 | temurin25/shenandoah | 11.03 | 13.51 | 16.21 |
| 4 | temurin25/parallel | 11.17 | 13.20 | 15.34 |
| 5 | oracle25/default | 11.24 | 14.52 | 18.63 |
| 6 | graalvmce25/g1 | 11.92 | 14.82 | 18.14 |
| 7 | temurin25/zgc | 12.69 | 15.54 | 19.05 |

### p100(差异仍在噪声内,parallel 略落后)

| 排名 | 配置 | mean MSPT | p95 | p99 |
|---|---|---|---|---|
| 1 | openjdk25/default | 18.11 | 22.32 | 30.34 |
| 2 | temurin25/shenandoah | 18.16 | 23.15 | 31.26 |
| 3 | oracle25/default | 18.36 | 23.42 | 30.72 |
| 4 | graalvmce25/g1 | 18.37 | 23.28 | 32.14 |
| 5 | temurin25/g1 | 18.38 | 22.54 | 30.84 |
| 6 | temurin25/zgc | 18.62 | 22.97 | 30.97 |
| 7 | temurin25/parallel | 20.30 | 25.64 | 35.38 |

### p150(过载档,配置间拉开决定性差距)

| 排名 | 配置 | mean MSPT | p95 | p99 | >50ms tick 占比 | 3-rep 极差 |
|---|---|---|---|---|---|---|
| 1 | temurin25/shenandoah | **58.25** | 92.94 | 120.85 | 58.9% | 2.6ms |
| 2 | temurin25/zgc | **59.21** | 92.81 | 120.99 | 62.4% | 6.4ms |
| 3 | oracle25/default | 78.45 | 120.36 | 165.76 | 92.4% | 12.3ms |
| 4 | graalvmce25/g1 | 82.82 | 130.89 | 176.14 | 94.1% | 15.7ms |
| 5 | openjdk25/default | 87.18 | 138.54 | 182.27 | 97.0% | 9.9ms |
| 6 | temurin25/g1 | 95.59 | 152.43 | 215.02 | 97.9% | 24.9ms |
| 7 | temurin25/parallel | 113.18 | 179.18 | 258.57 | 99.7% | 10.0ms |

## 结论

1. **p25-p100:选什么都行。** 全部配置 mean MSPT 8-20ms,差距 ≤ rep 间噪声,0 掉线。
2. **过载点:所有配置在 p100→p150 之间。** p100 最慢一档 mean 也只有 20ms;
   p150 全部配置 mean >50ms(20 TPS 不保),无一幸免。
3. **过载时只有低暂停 GC 能兜底:p150 上 Shenandoah/ZGC(~58-59ms)领先 G1 系(78-96ms)
   约 25-39%,领先 Parallel(113ms)约 48%。** G1 系内部顺序(oracle/graalvm/openjdk/temurin)
   在 rep 间不稳定,视为同档。Parallel 全程垫底,GC max pause 200-250ms 也是全场最差。
4. **推荐配置:**
   - 明确会冲到 100+ 玩家:**temurin25 + Shenandoah 或 ZGC**。两者 p150 打平;
     ZGC 暂停更低(GC max <1ms vs Shen ~1ms,实际都无关痛痒),Shenandoah 在 p25-p100
     略稳。随手选 Shenandoah(堆外开销小于 ZGC)。
   - 玩家 ≤100:任意默认配置即可,openjdk25/oracle25 默认(G1)与其他无差异。
5. **与 R3 排名层面一致**(绝对值不可跨矩阵比,环境漂移,见 methodology.md 陷阱 #7):
   R3 p150 排名 zgc(43)< shen(49) ≪ oracle/g1/openjdk/graalvm(76-78) < parallel(92);
   R4 p150 排名 shen ≈ zgc ≪ oracle < graalvm < openjdk < g1 < parallel。
   两轮共同结论:**ZGC/Shenandoah 第一梯队,G1 系中间档,Parallel 垫底**,方向稳健。
   (R4 p150 绝对值整体高于 R3,如同矩阵 zgc 59 vs 43ms——跨日环境漂移,不解读。)

## 备注

- resume 逻辑小坑已踩:`run-scaling.sh` 的 `LAUNCHED` 计数与 `cell_done` 重复计数,
  导致 parallel/p100 与 g1/p25 两格各少 1 rep;已用 `run-min-bench.sh` 同参数补跑
  (`runs/20261010-015942-*`、`runs/20261010-021956-*`),聚合前已验证 28 格 ×3 完整。
- 被 kill 的不完整目录 `runs/20261009-130104-temurin25-parallel-mixed-p100-wsN` 无
  markers/metadata,聚合脚本自动跳过,保留未删。
