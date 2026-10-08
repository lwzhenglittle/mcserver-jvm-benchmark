# Round 1: runtime/GC/workload 矩阵结果(2026-09-30 → 10-01)

矩阵:11 组合 × 3 workload(mixed/explore/entity)× 3 reps = **99 轮**,p25,堆 8G(-Xms8G -Xmx8G),
warmup 600s / measure 600s,0 失败,0 掉线。逐轮数据:[../results/round1-runs.csv](../results/round1-runs.csv);
聚合(含 95% CI):[../results/round1-summary.csv](../results/round1-summary.csv)。

## mean MSPT(ms,3 reps 均值)

| 组合 | mixed | explore | entity |
|---|---|---|---|
| temurin25 shenandoah | 7.88 | **5.94** | **5.38** |
| temurin25 parallel | **7.49** | 6.73 | 6.08 |
| temurin25 zgc | 7.70 | 6.38 | 6.03 |
| temurin25 g1 | 7.98 | 6.31 | 6.01 |
| graalvmce25 g1 | 7.83 | 6.10 | 5.68 |
| graalvmce25 zgc | 8.22 | 6.38 | 5.80 |
| corretto25 g1 | 8.77 | 6.57 | 6.07 |
| semeru25 gencon (OpenJ9) | 9.13 | 7.88 | 7.60 |
| semeru25 balanced | 9.91 | 8.25 | 7.77 |
| semeru25 optthruput | 11.06 | 8.54 | 8.13 |
| semeru25 optavgpause | 10.95 | 8.71 | 8.23 |

p25 轻负载下所有组合均稳 20 TPS,差异体现在 MSPT 均值与尾部。

## 结论

1. **综合最佳:temurin25 + Shenandoah** —— 三 workload 均前二;entity(5.38)与 explore(5.94)双第一,
   max 尾部最小(18-30ms)。
2. **OpenJ9(Semeru)全 GC 策略垫底**,mean 比 HotSpot 系差 15-45%,max 尖刺 70-220ms,全部淘汰。
3. **Vendor 无差异**:corretto25+g1 ≈ temurin25+g1(mixed 差 ~10% 在 CI 边缘,explore/entity 重合)——
   vendor 问题已回答,R2 不再重复测 vendor。
4. Parallel 均值好(mixed 7.49 第一)但它是停顿型 GC,轻负载尾巴没暴露 → 带入 R2 高负载检验。
5. 晋级 R2:temurin25 {g1, shenandoah, parallel, zgc} + graalvmce25 g1(Graal JIT 代表)+
   baseline openjdk25/oracle25(零参数)。

## 附带验证发现

- **时长敏感性**:warmup <600s 结果不可复现(JIT 未稳,带载 warmup 是必须);measure 600s 与 900s
  无显著差异 → 定 600/600。
- **并行 lane 偏差**:双 lane(各占 4 物理核)并行跑会互相干扰(~10%),R2 改为单实例独占 16 核顺序跑。
