# 测试方案修正（基于当前环境实测）

依据 `prof.md` 全部实验要求**不变**，以下仅为针对本机实测环境的执行层修正。
探测日期：2026-09-30。

---

## 0. 环境实测结论

| 项目 | 实测值 | 对方案的影响 |
|---|---|---|
| OS | WSL2,kernel 6.18.33.2-microsoft-standard-WSL2 | **非裸机**,prof.md「默认裸机」前提不满足 |
| CPU | AMD Ryzen 7 5700X,8C/16T,16 逻辑核 | SMT 开启，需绑定物理核 |
| NUMA | 单节点（node 0: CPU 0-15) | numactl 绑定无意义，仅记录 |
| 内存 | 62 GB（可用 60 GB) | 8G heap 无压力；32G 阶段亦可，但需独占运行 |
| 文件系统 | ext4(/dev/sdd),929G 可用 | **无 btrfs/reflink**,golden world 恢复降级 |
| CPU governor | `/sys/.../cpufreq` 不存在（WSL2) | 不可控，只能记录 |
| perf | perf_event_paranoid=2,`instructions`/`cycles` 计数器**实测有效** | perf stat 可用，无需降级 |
| taskset | 可用 | CPU affinity 可固定 |
| Paper | paper-26.2-129.jar,SHA256 `b1d8f6bf…feb083` | 已 pin，实测**要求 Java ≥ 25**(JDK 21 直接拒绝启动） |

---

## 1. WSL2 替代裸机的修正（偏差记录，不改要求）

1. metadata 中 `os` 字段必须标注 `virtualization: wsl2`；结果**不得外推**到裸机结论。
2. Windows 宿主机负载是不可控变量：每轮 benchmark 前后记录 WSL2 内 load average；正式 run 期间宿主机保持空闲；在 metadata 增加 `host_note` 字段。
3. governor 不可设 `performance` → 按 prof.md「无法修改则记录当前状态」处理，metadata 记 `governor: unavailable (wsl2)`。
4. WSL2 内存动态分配：metadata 记录运行时 `/proc/meminfo` 快照。

## 2. CPU 绑定修正

- server JVM:`taskset -c 0-7`（物理核，Ryzen 5000 每 CCD 内 0-7 为物理核、8-15 为 SMT 兄弟，需以 `lscpu -e` 实测 topology 为准写入 probe 脚本，禁止 hardcode)。
- bot/replay 客户端进程：绑定剩余核（8-15)。
- NUMA：单节点，`numactl --cpunodebind/--membind` 跳过，记录 `numa: single-node`。

## 3. World 恢复机制修正

- btrfs snapshot、reflink 均不可用（ext4)。
- 降级方案：`rsync -a --delete golden/ work/`;golden world 体积预期 < 1GB，恢复耗时秒级，每轮恢复耗时计入 metadata(`world_restore_seconds`)。
- world snapshot checksum:对 golden world 做 `find -type f | sort | xargs sha256sum` 聚合 hash，写入 metadata。

## 4. JDK 矩阵修正（基于 sdkman 实测，2026-09-30)

### 已安装、Java 25、可直接进矩阵

| runtime key | identifier | family/JIT |
|---|---|---|
| temurin25 | 25.0.4-tem | HotSpot/C2(baseline) |
| zulu25 | 25.0.4+1.1-zulu | HotSpot/C2 |
| oracle25 | 25.0.4-oracle | HotSpot/C2 |
| openjdk25（可选） | 25.0.2-open | HotSpot/C2（上游参考实现） |
| graalvmce25 | 25.3.4+1.r25-graalce | Graal JIT(GraalVM CE) |
| graalvmoracle25 | 25.0.4-graal(手动补装) | Graal JIT(Oracle GraalVM,商用功能更全) |

 ### 需补装(sdkman 有货)

| runtime key | identifier | 用途 |
|---|---|---|
| corretto25 | 25.0.4-amzn | 核心 baseline(prof.md 指定） |
| microsoft25 | 25.0.4+1-ms | vendor 扩展 |
| liberica25 | 25.0.4+1.1-librca | vendor 扩展 |
| sapmachine25 | 25.0.4+1-sapmchn | vendor 扩展 |
| semeru25 | 25.0.4-sem | **OpenJ9，必测** |

### 明确 skipped（记录原因，不绕过）

- **Oracle GraalVM 25**:sdkman broker 对 `25.4.4+1-graal` 返回 404 → 已**手动补装**官方 `graalvm-jdk-25.0.4+7.1`(download.oracle.com,SHA256 `76007c30…ea37276` 校验通过，注册为 `25.0.4-graal`,Paper smoke test 通过）。注意：Oracle GraalVM 为 GFTC license,benchmark/评估用途可用，生产使用需确认授权。
- **Azul Prime/Zing**:sdkman 无此发行版；需官网 trial 授权 → `optional/skipped`，后续手工评估，不自动绕过。
- **Java 8/11/17/21 的全部 14 个已装 JDK**:Paper 26.2 实测拒绝启动 → 不进入任何实验，不作为「偷偷降级」的来源。Java 26/27(tem/zulu/oracle/open，已装）仅用于独立的「JDK major version」扩展实验，不与 vendor 比较混排。

## 5. GC matrix 修正

- HotSpot 系（tem/corretto/ms/oracle/zulu/librca/sapmchn):probe `G1 ZGC Parallel Shenandoah Serial`，只有 `-XX:+UseX -version` 实际接受的入矩阵。**注意：Oracle JDK 与部分 vendor build 可能不含 Shenandoah，以 probe 为准。**
- GraalVM CE 25 / Oracle GraalVM 25:probe 同上;GraalVM 对部分 GC(如 ZGC/Parallel)支持可能受限,probe 决定,失败不阻塞。
- Semeru/OpenJ9 25:probe `-Xgcpolicy:gencon/balanced/optavgpause/optthruput`；禁用一切 HotSpot `-XX:+Use*` 参数。已知风险：Paper 官方不正式支持 OpenJ9，若 Paper 26.2 启动失败 → 记录 `failed: paper incompatible with openj9`，不阻塞整体。
- GC log:HotSpot 用 `-Xlog:gc*:file=gc.log:time,uptime,level,tags`(Java 25 语法需在 Phase 4 实测验证）;OpenJ9 用 verbose GC XML，独立 parser，统一落 `gc-events.jsonl`。

## 6. 资源与规模修正

- heap 第一阶段固定 8G(62G 内存下无压力）;第二阶段 4/8/16/32G 可行，但 32G 配置要求机器独占、宿主机空闲。
- 玩家 scaling(10→200+）依赖 bot 工具协议支持，见下。

## 7. Workload 工具链修正（26.2 协议风险）

- MC 26.2 协议极新,Mineflayer/mcbenchmark 等 bot 工具**大概率协议滞后**,Phase 1 必须实测验证，不得假定兼容。
- 修正执行路径（workload 定义不变）:
  1. 优先验证现有 bot 库对 26.2 协议的支持；
  2. 差一点的做最小 adapter（协议版本 bump);
  3. 完全不兼容时，exploration/entity-redstone-heavy 可先用无玩家方案落地（预生成世界 + 矿车/实体农场构造 + `/tick` 辅助观测）,survival-mixed 标记 `blocked: no compatible bot client`，并在结果中明示，**不伪造玩家负载**。

## 8. 统计与噪声修正

- WSL2 噪声高于裸机：保持 ≥5 runs（目标 10)，随机化顺序、seed 20260930 不变；
- 新增：每 config 计算跨 run 变异系数（CV),CV > 10% 的指标在 summary 中标记 `noisy`，而非静默取平均。

## 9. 不变项确认

以下要求原样保留：MSPT 为主指标（TPS 仅辅助）;0–5/5–20/20–50 min 时间窗；同 jar 同 Paper 配置；默认策略 vs tuned 严格分离；raw data 全保留；目录结构与 `./bench` CLI 目标；失败如实记 `unsupported/skipped/failed`。

---

## 10. 修正后的 Phase 1–3 行动清单

- **Phase 1**:✅ 完成（`docs/exploration.md`)。关键结论：mineflayer 协议层停在 26.1，经 **ViaBackwards 5.12.1-SNAPSHOT 桥接 26.2 已实测可用**;smashyalts/mcbenchmark(775，可 retarget）列为 P6 候选；Paper 内置 spark 无 `mspt` 子命令，用 `spark tps` + `spark tickmonitor`。
- **Phase 2**:✅ 10 个 Java 25 runtime 齐备（sdkman ×9 + Oracle GraalVM 手动 ×1);`java -version`/`-XshowSettings:vm` 已采集至 `probe/`;`config/jdks.yaml` 与 `probe/capabilities.json` 已生成（`scripts/probe-jdk.sh` 可重跑）。
- **Phase 3**:✅ 全部 10 runtime 以确定 GC 参数启动 Paper 26.2-129 通过（`scripts/smoke-paper.sh`，日志在 `smoke/`)。**重要发现：Semeru OpenJ9 25 可正常跑 Paper 26.2**(gencon/balanced/optavgpause/optthruput 四策略全过，启动 ~10.3s vs HotSpot ~7s),prof.md 预期的 OpenJ9 不兼容风险未发生。核心 matrix GC 变体（temurin G1/ZGC/Parallel/Shenandoah、graalce ZGC）亦全部启动通过。
- **Phase 5**:✅ 最小 workload 管线跑通（`scripts/run-min-bench.sh`,temurin25+G1+10 bots,5min 测量，见 `runs/20260930-140331-temurin25-g1-p10` 与 exploration.md §5)。
- **并行化修正（2026-09-30，应用户要求）**：矩阵改 2 路并行（lane0: server 0-3 / bots 12-15 / port 25565;lane1: server 4-7 / bots 8-11 / port 25566)，每轮 warmup 600s + measure 900s，总时长 5.7 天 → ~34h。**代价（已记录）**：两 lane 共享 L3/内存带宽，bots 与邻 lane server 共用 SMT 物理核 → 存在共时噪声；缓解：5 reps + seed 乱序 + 每轮 metadata 记录 workspace/cores，分析时按 lane 分层检验。单 server 4 物理核实测不瓶颈（验证轮 mean MSPT 与单实例同量级）。workspace 隔离：`scripts/mk-workspace.sh`（配置拷贝 + paperclip 缓存硬链 + 独立 world/端口）。
