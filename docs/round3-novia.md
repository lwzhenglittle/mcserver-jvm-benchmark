# Round 3: no-Via + 原生 26.2 全矩阵复现(Via 开销实验)

**问题**:R1/R2 的 bot 都经 ViaBackwards(26.1 客户端 → 26.2 服务器)。Via 层影响多大?结论在无 Via 下是否成立?

**方法**:完整复现 R2——7 组合 × p{25,50,100,150} × 3 reps = 84 轮,同 seed 同执行顺序,
服务器无 Via 插件,bot 用原生 26.2 协议(`bots/add-26.2.js` 补丁)。**84/84 完成,0 失败,0 掉线。**
数据:[../results/round2-novia-runs.csv](../results/round2-novia-runs.csv);对比脚本:`scripts/compare-novia.py`。

## 核心结果:mean MSPT(noVia vs Via,rep 中位数)

| 组合 | p25 | p50 | p100 | p150 |
|---|---|---|---|---|
| openjdk25 默认 | 7.90 (−1.0%) | 9.69 (+7.6%) | 17.95 (+8.9%) | 76.19 (+3.0%) |
| oracle25 默认 | 8.06 (+16.5%) | 10.29 (+6.9%) | 18.08 (+8.0%) | 80.60 (+2.2%) |
| temurin25 g1 | 8.82 (+16.3%) | 11.02 (+6.5%) | 19.31 (+17.2%) | 77.56 (+12.8%) |
| temurin25 shenandoah | 8.54 (+2.7%) | 10.54 (+5.4%) | 18.18 (+14.9%) | 47.70 (−0.6%) |
| temurin25 parallel | 8.59 (+11.7%) | 10.68 (+15.1%) | 18.56 (+10.5%) | 90.70 (+0.5%) |
| temurin25 zgc | 9.28 (−1.5%) | 11.56 (+6.8%) | 18.84 (+17.4%) | **37.87 (−20.4%)** |
| graalvmce25 g1 | 8.18 (+16.0%) | 10.86 (+26.6%) | 18.44 (+16.1%) | 78.05 (+13.5%) |

## p150 TPS(达成 tick 率)

| 组合 | Via | noVia |
|---|---|---|
| temurin25 **zgc** | 18.8 | **19.9** |
| temurin25 **shenandoah** | 19.2 | 19.0 |
| temurin25 g1 | 14.5 | 12.9 |
| graalvmce25 g1 | 14.5 | 12.8 |
| openjdk25 默认 | 13.5 | 13.1 |
| oracle25 默认 | 12.7 | 12.4 |
| temurin25 parallel | 11.1 | 11.0 |

## 结论

1. **R1/R2 的组合排名与最终推荐对 Via 移除稳健**:p150 过载档前两名仍是 ZGC、Shenandoah,
   顺序不变;Parallel 依旧垫底。过载拐点仍在 100–150 人之间,未位移。
2. **Via 转发开销 ≈ 0,但去掉 Via 反而更慢**:亚过载档(p25–p100)noVia mean 普遍 +3%~+17%,
   与先行对照实验一致(+19%,rep 分布不重叠,同日对照排除了环境漂移)。机制未定位——
   [推断] 服务器对原生 776 客户端存在对(Via 翻译的)775 客户端不启用的逐玩家代码路径。
3. **ZGC 在无 Via 下过载表现更强**:p150 mean 37.9ms(比 Via 下还低 20%),TPS 19.9——
   是唯一 noVia 快于 Via 的组合。ZGC 的亚毫秒暂停在高负载下与网络线程压力的交互更有利。
4. R2 的绝对数值(Via 配置)对 G1 系组合是**乐观上界**,对 ZGC 是**保守下界**;
   相对排名两矩阵一致,选型结论不变:**temurin25 + ZGC,heap 16G,容量 ~150 人**。

## 附:先行对照(2026-10-07,定机理用)

temurin25+g1 p100 单格,3+3+2 reps:Via 10-02 中位 16.48ms / Via 同日 15.87ms / noVia 同日
18.89ms(+19%)。跨日漂移仅 −3.7%,证明差值来自协议路径而非环境。

## 复现

```bash
node bots/add-26.2.js        # 注册原生 26.2 协议(幂等,npm ci 后需重跑)
./scripts/mk-workspace.sh N 25567 && rm workspaces/wsN/plugins/Via*.jar
./scripts/run-scaling.sh --botversion 26.2 --workspace wsN --port 25567   # 84 轮 ~28h
python3 scripts/aggregate.py 'runs/*-wsN' > results/round2-novia-runs.csv
python3 scripts/compare-novia.py
```
