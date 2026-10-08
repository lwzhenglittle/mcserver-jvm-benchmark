# Round 3: ViaVersion 开销实验 —— 结论修正(2026-10-08 勘误)

> ⚠️ **勘误**:本文档早先版本(基于跨日矩阵对比)声称"去掉 Via 慢 ~19%"。
> 经 10-08 交错对照实验证明该结论是**时间聚块伪影**,特此撤回。正确结论见下。

## 最终结论

**ViaVersion/ViaBackwards 转发对 Paper 26.2 服务器性能无可测影响(±1ms 内)。**
原生 26.2 与经 Via 的 26.1 客户端,MSPT 无差异。

## 证据链

### 1. 交错 A/B(正确方法,10-08 同日同环境背靠背)

| 对 | 顺序 | Via mean | noVia mean | Δ |
|---|---|---|---|---|
| 1 | A→B | 18.58 | 18.55 | −0.03ms |
| 2 | B→A | 17.27 | 18.09 | +0.82ms |
| 3 | A→B(300s warmup + JFR) | 21.19 | 20.23 | −0.96ms |

三对全部在噪声内(±1ms)。temurin25+g1, p100, mixed, 16G, 600s warmup/600s measure。

### 2. JFR 火焰图 A/B(10-08,p100,150s profile)

- Server 线程 CPU 样本数相等(1403 vs 1361/180s)
- park 总时长相等(158.7s vs 159.1s)
- 零锁竞争、零主线程 socket/文件 IO
- 热点帧分布无结构性差异

### 3. 唯一真实差异:网络流量

Paper 内置 JFR `minecraft.NetworkSummary`:原生 26.2 连接 180s 内多收 **+18% 字节**
(47.7MB vs 40.5MB/100 连接;包数 +5%)。[推断] 26.2 新增内容(注册表条目、新实体/粒子数据)
不经 ViaBackwards 裁剪故略大。该差异不产生可测 MSPT 影响。

## 原结论为什么是错的(方法论教训)

10-07 的 "Via 15.87 vs noVia 18.89" 看似严谨(同日、rep 分布不重叠),但:
- noVia 3 reps 全部跑在 **00:05–01:06**,Via 对照跑在 **01:07–01:48**
- WSL2 共享 Windows 宿主,环境负载有小时级漂移;10-08 同配置 Via 复测得 18.58(与 10-07 的 15.87 差 17%)
- **分块顺序 A/B 会被环境趋势污染;rep 间一致只证明块内环境稳定,不证明对照有效**
- 正确做法:A/B 交错(A/B/A/B)或同块随机化

同样地,先前"R2(10-01)vs R3(10-07)全矩阵逐格差值表"因跨日执行**全部作废**;
两个矩阵各自内部(同块、seeded shuffle)的排名结论不受影响。

## 不再需要的"机制解释"

早前推测"原生 776 客户端触发额外服务器路径"——交错实验证伪,无需进一步定位。

## 可复现

```bash
node bots/add-26.2.js   # 原生 26.2 bot 支持(依然有效且有用:可脱离 Via 插件跑)
# 交错对:
./scripts/run-min-bench.sh --runtime temurin25 --gc g1 --players 100 --warmup 600 --measure 600 \
    --heap 16G --workspace workspaces/ws0 --port 25565 --cores 0-7 --botcores 8-15
./scripts/run-min-bench.sh --runtime temurin25 --gc g1 --players 100 --warmup 600 --measure 600 \
    --heap 16G --botversion 26.2 --workspace workspaces/wsN --port 25567 --cores 0-7 --botcores 8-15
```

运行目录:`runs/20261008-1*-(ws0|wsN)`(交错对 + JFR 对)、`runs/20261007-0*-wsN`(被证伪的批次)。
