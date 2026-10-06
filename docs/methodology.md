# 测试方法学

本文档固化两轮实验的方法,使结果可复现、可审计。实验需求原文见 [spec.md](spec.md)。

## 1. 环境

| 项 | 值 |
|---|---|
| CPU | AMD Ryzen 7 5700X,8C/16T,SMT 开启,单 NUMA 节点 |
| RAM | 62 GB |
| OS | WSL2(Linux 6.18.33.2-microsoft-standard-WSL2),ext4 on vhdx |
| 服务器核 | taskset 0-7(8 逻辑核 = 4 物理核) |
| bot 核 | taskset 8-15 |

限制(如实声明):WSL2 下 CPU governor、perf、NUMA 绑定不可控;非裸机,绝对数值不可外推到其他硬件,
相对排名在同环境内可复现。

## 2. 被测对象

- Paper **26.2-129**(`paper-26.2-129.jar`,sha256 锁定,要求 Java ≥ 25)
- 所有 JVM 跑**完全相同的 jar 与完全相同的配置**;每轮恢复同一 golden world
- 固定配置:`config/server/`(server.properties、bukkit.yml、spigot.yml)、`config/paper-global.yml`、
  `config/paper-world-defaults.yml`——不给任何 JVM 单独调 Paper 参数

## 3. 运行时矩阵

`config/jdks.yaml` 为唯一事实来源。Java 25 版本:

| runtime | 发行版 | 备注 |
|---|---|---|
| temurin25 | Adoptium Temurin 25.0.4 | 主力,GC: g1/shenandoah/parallel/zgc |
| corretto25 | Amazon Corretto 25.0.4 | R1 验证:与 temurin 无差异后淘汰 |
| microsoft25 | Microsoft OpenJDK 25.0.4 | 同上 |
| zulu25 / liberica25 / sapmachine25 | Azul / BellSoft / SAP | R1 淘汰 |
| oracle25 | Oracle JDK 25.0.4 | R2 baseline(零参数) |
| openjdk25 | java.net 上游 25.0.2 | R2 baseline(零参数) |
| graalvmce25 | GraalVM CE 25.3.4 | Graal JIT + G1 |
| semeru25 | IBM Semeru(OpenJ9)25.0.4 | GC: gencon/balanced/optthruput/optavgpause,R1 全败淘汰 |
| graalvmoracle25 | — | 上游 broker 404,未测 |

`default` 伪 GC(R2 baseline 专用):不传任何 GC flag,JVM 自选(Java 25 默认 G1,自动堆 ~15.6G)。

## 4. Golden world 与负载

- **golden world**:固定 seed,Chunky 预生成 r=512 区块,另建 entity-redstone 压力区(实体+红石);
  每轮运行前整目录恢复并校验 sha256,保证每轮世界逐字节一致
- **bot 负载**:mineflayer 无头客户端,确定性随机(seed=20260930)。协议两种支持:
  - 26.1 协议 + 服务器装 ViaVersion/ViaBackwards(**两轮矩阵的实际配置**)
  - **原生 26.2 协议(776)**:`node bots/add-26.2.js` 后 `--version 26.2`,服务器无需 Via 插件。
    原理:ViaBackwards `Protocol26_2To26_1` 证明包 ID 完全不变,线格式仅 3 处差异(login success 追加
    session UUID、packet_teams 字段重排且 color 变 optional varint、join game 追加 1 字节标志位);
    补丁将 minecraft-data 26.1 数据复制为 26.2 并修正这 3 处。已实测:无 Via 服务器 3 bot
    spawn/行走/挖掘 60s 无任何报错。26.2 新内容语义对负载生成无影响。
  三种 workload:
  - `mixed`:随机行走冲刺 + 40% 跳跃 + 50% 挖掘 + 30% 挥手,离原点 >400 格自动折返(约束在预生界内)
  - `explore`:持续向外探索(chunk 生成/加载压力)
  - `entity`:entity-redstone 区附近活动(实体/红石压力)
- **bot 工程参数**(血泪教训,见 §7):
  - 分片:每 node 进程 ≤50 bot(`SHARDS=(PLAYERS+49)/50`),避免单进程事件循环成为瓶颈
  - 进场限速:p>100 时全局 ~1 bot/s(每片 stagger = SHARDS×1000ms),否则进场风暴触发 keepalive 连锁踢出
  - p200 实测:进场风暴 + 服务器过载 → tick 长达 26.8s,200 bot 全被 keepalive 踢出,**不可测量**

## 5. 指标采集

| 来源 | 内容 |
|---|---|
| `mspt.csv`(TickLogger 插件) | **逐 tick** MSPT(System.nanoTime),主指标 |
| `gc.log` | `-Xlog:gc`(OpenJ9 用 verbosegc),暂停次数/时长 |
| `proc.txt` | 每秒采样 server 进程 CPU%、RSS、majflt |
| `server.log` | spark tps / tickmonitor、Tick # 超时记录 |
| `bots.*.log` | spawn/掉线/keepAliveError 计数(掉线=该轮作废) |
| `metadata.json` | 全部运行参数 + 环境指纹 + jar/world 哈希 |

主指标为测量窗内 MSPT 分布:**mean / p50 / p95 / p99 / max / >50ms 占比 / 达成 TPS**(ticks÷600s)。

## 6. 单轮流程(`run-min-bench.sh`)

1. 恢复 golden world,校验 sha256
2. 冷启动 server(taskset 0-7,`-Xms$HEAP -Xmx$HEAP $GCFLAG`),等待 ready
3. 冷启动边界标记 → bot 进场(分片、限速)
4. **warmup 600s(带载 warmup——JIT 必须在真实负载下预热,不接受空跑预热)**
5. 测量窗 600s,spark tickmonitor 伴随
6. 优雅停服(stop 指令),归档运行目录 `runs/<ts>-<runtime>-<gc>-<workload>-p<N>-<ws>`

时长敏感性(R1 验证过):warmup <600s 结果不可复现(JIT 未稳);measure 600s 与 900s 无显著差异。

## 7. 已知陷阱(踩过的坑,勿复踩)

1. **bot 进场风暴**:200 bot 25s 内涌入 → 登录/区块发送风暴 → 服务器 stall → keepalive 连锁踢出。
   解决:分片 + 限速进场。
2. **bot 跑出预生界**:引入 chunk 生成变量(比 chunk 加载重得多),且各档不可比。
   解决:mixed 模式 r>400 自动折返。
3. **单 node 进程 >50 bot**:事件循环饱和,bot 侧成为瓶颈(假过载)。
4. **heap 必须 -Xms=-Xmx 且全组合一致**;baseline 例外(测的就是默认行为,metadata 标记 `default`)。
5. 过载测量有效性以 **bot 存活率** 为准:p150 全部存活可测;p200 全灭,剔除该档。
6. sdkman 的 `sdk install` 交互提示不吃 `SDKMAN_AUTO_ANSWER`,需 `yes n |` 供 stdin(安装 22 个 JDK 时的坑)。

## 8. 统计

每格 3 reps,seeded shuffle 打乱执行顺序(消时间漂移);报告 rep 中位数 + rep 间 spread;
rep spread >30% 的格(如 shenandoah p150 双峰)单独标注,不把中位数当稳定值。

## 9. 两轮矩阵速查

- **R1**(99 轮,8G,p25):11 runtime/GC × 3 workload → 晋级 temurin25{g1,shenandoah,parallel,zgc}
  + graalvmce25 g1;baseline openjdk25/oracle25 直接进 R2。结论与逐格数据:[round1-results.md](round1-results.md)
- **R2**(84 轮,16G):7 组合 × p{25,50,100,150} → 过载点 100-150 之间;ZGC/Shenandoah 过载占优。
  结论:[round2-results.md](round2-results.md)
