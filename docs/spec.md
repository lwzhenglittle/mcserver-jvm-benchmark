你现在位于一个本地代码工作区。请设计并实现一套可复现的 Minecraft Java Edition Paper Server JVM/GC benchmark 框架。

## 总目标

我要测试 Paper 26.2 在不同 Java 25+ JVM/JDK、JIT 和 GC 实现下的性能。

目标不是简单比较“TPS”，而是建立一套可复现、自动化、统计上有意义的 benchmark，用于回答：

1. 不同 JVM/JIT 对 Paper 26.2 steady-state tick 性能有什么影响？
2. 不同 GC 对 MSPT tail latency 有什么影响？
3. HotSpot、Graal JIT、OpenJ9 之间有什么差异？
4. 不同 JDK vendor 的 HotSpot build 是否存在可测量性能差异？
5. 不同 JVM 的 CPU 效率、内存占用、GC 行为和 warmup 行为有什么区别？
6. workload 增长时，各 JVM 的 overload point 有什么区别？

不要只写设计文档。请实际探索环境、寻找合适的现有 benchmark/replay 工具，并逐步构建可以真正运行的 benchmark harness。

---

# 一、基本约束

目标服务端：

- Minecraft / Paper：Paper 26.2
- Paper 26.2 要求 Java >= 25
- 主实验必须固定 Java major version = 25
- 不要把 Java 25、26、27 的结果直接用于比较不同 JDK vendor
- Java 26/27 可以作为独立的“JDK major version”扩展实验

测试环境默认优先考虑：

- Linux
- x86-64
- 裸机运行
- 不优先使用 Docker 隔离 JVM，因为容器本身可能带来额外变量
- 如果使用 container，只用于 JDK 获取或辅助组件，并说明理由

所有实验必须记录：

- OS
- kernel
- CPU model
- CPU topology
- SMT 状态
- memory
- NUMA topology
- filesystem
- Paper build
- Minecraft version
- JDK vendor
- java -version
- java -XshowSettings:vm
- JVM flags
- GC
- heap size
- benchmark git commit
- workload/trace ID

每一轮测试都必须能根据 metadata 完整重现。

---

# 二、首先探索并验证候选 JDK

不要假定下面的信息永远正确。

首先联网检查这些项目当前最新的 Java 25 stable build、官方来源、下载方式、license 和平台支持。

至少研究：

## HotSpot/C2 系

1. Eclipse Temurin 25
2. Amazon Corretto 25
3. Microsoft Build of OpenJDK 25
4. Oracle JDK 25
5. Azul Zulu 25
6. BellSoft Liberica JDK 25
7. SAP SapMachine 25

这些都属于 HotSpot 系。

第一阶段不必全部进入完整 benchmark。

建议：

核心 baseline：

- Temurin 25
- Corretto 25

vendor comparison 扩展：

- Microsoft OpenJDK
- Oracle JDK
- Zulu
- Liberica
- SapMachine

如果这些发行版最终只是非常接近的 HotSpot build，也必须记录这一事实，不要人为制造差异。

---

# 三、必须重点测试的不同 JVM/JIT

## A. HotSpot C2

以 Temurin 25 作为标准 HotSpot baseline。

至少测试：

- G1GC
- ZGC
- ParallelGC

尝试检测：

- ShenandoahGC
- SerialGC

但不要假定每个发行版/平台都支持某个 collector。

对每个 JVM 自动 probe，例如尝试：

java -XX:+UseG1GC -version
java -XX:+UseZGC -version
java -XX:+UseParallelGC -version
java -XX:+UseShenandoahGC -version
java -XX:+UseSerialGC -version

只有 JVM 实际接受的 collector 才加入 matrix。

不要因为某个 JVM 不支持一个 GC 就让整个实验失败。

---

## B. GraalVM

研究并安装：

- GraalVM Community Edition，Java 25 系列
- 如果方便，也研究 Oracle GraalVM

重点是普通 JVM/JIT mode：

java -jar paper.jar

不是 Native Image。

目标是比较：

HotSpot C2
vs
Graal JIT

不要错误地把 GraalVM 当成“Native Image benchmark”。

检测 GraalVM 当前实际可用的 GC，并仅测试实际支持的 collector。

记录：

- GraalVM version
- underlying OpenJDK version
- Graal compiler version
- JVMCI/Graal 相关信息

如果有办法可靠记录 Graal compilation activity，则加入 warmup 分析。

---

## C. Eclipse OpenJ9

必须加入。

优先使用：

IBM Semeru Runtime Open Edition Java 25

验证：

java -version

确实显示：

- OpenJDK 25
- Eclipse OpenJ9

研究 OpenJ9 Java 25 当前支持的 GC policies。

至少尝试：

-Xgcpolicy:gencon
-Xgcpolicy:balanced
-Xgcpolicy:optavgpause
-Xgcpolicy:optthruput

不要把 HotSpot flags 强行传给 OpenJ9。

OpenJ9 是独立 JVM，启动参数、GC log、JIT logging 和内存管理方式需要单独适配。

---

# 四、可选但很有价值：Azul Prime / Zing

检查是否可以合法获取 evaluation/trial build。

如果可以：

加入 Azul Prime Java 25。

研究：

- Falcon JIT
- C4 Garbage Collector
- ReadyNow

第一阶段 benchmark 应优先测默认：

Falcon + C4

不要把 ReadyNow 等 warmup acceleration 和普通 cold-start baseline 混在一起。

可以后续增加：

Prime 默认模式
vs
Prime + ReadyNow

如果无法自动合法获取，不要绕过授权。

将其标记为 optional/skipped。

---

# 五、实验矩阵设计

第一版控制规模。

建议核心矩阵：

Temurin 25:
- G1
- ZGC
- Parallel
- Shenandoah（如果支持）

GraalVM CE 25:
- 默认 GC
- G1（如果支持）
- ZGC（如果支持）

IBM Semeru/OpenJ9 25:
- gencon
- balanced
- optavgpause
- optthruput

Corretto 25:
- G1

可选：
Azul Prime:
- C4

Heap 第一阶段固定：

-Xms8G
-Xmx8G

并保证所有 JVM 尽量获得等价 heap constraint。

第二阶段增加：

4G
8G
16G
32G

不要一开始运行完整笛卡尔积。

---

# 六、Paper Server

下载并 pin 一个明确的 Paper 26.2 build。

不要使用“latest”作为长期 benchmark identifier。

保存：

paper-build-XXX.jar

并在 metadata 中记录：

- Paper build number
- SHA256
- 下载 URL
- 下载日期

所有 JVM 必须运行完全相同的 Paper jar。

服务器配置也必须固定。

至少固定：

server.properties
paper-global.yml
paper-world-defaults.yml
spigot.yml
bukkit.yml

不要给不同 JVM 使用不同 Paper 优化参数。

---

# 七、Workload

这是整个实验最重要的部分。

禁止使用：

“启动服务器，没有玩家，然后看 TPS”

这没有意义。

TPS 20 只能说明 MSPT < 50ms。

主要指标必须是 MSPT。

---

# 八、调查现有 Minecraft benchmark / replay 工具

联网研究当前可用项目，特别寻找：

- headless Minecraft client
- fake player
- bot load generator
- player trace replay
- deterministic Minecraft server benchmark
- mcbenchmark
- mc-server-benchmark
- 类似项目

重点评估它们是否支持：

- Minecraft/Paper 26.2
- 当前协议版本
- headless 多玩家
- deterministic replay
- movement
- chunk loading
- digging
- block placement
- inventory
- entity interaction
- combat
- redstone/entity-heavy workload

不要因为之前有人推荐某个项目就假设它一定兼容 26.2。

必须实际检查 repository、最近 commit、issues、protocol support 和运行方式。

如果现成工具差一点即可支持 26.2，可以在本仓库中做最小修改或 adapter。

优先复用，不要无意义重写整个 Minecraft protocol client。

---

# 九、Canonical workloads

最终至少准备 3 类 workload。

## workload 1: survival-mixed

模拟正常 SMP：

- 玩家移动
- 挖掘
- 方块放置
- inventory interaction
- entity interaction
- 已生成 chunk 中活动

目标：

代表普通长期生存服。

---

## workload 2: exploration

重点制造：

- 玩家高速分散
- chunk loading
- chunk generation 或 chunk load

如果使用 chunk generation，必须严格区分：

existing-chunk benchmark

和：

chunk-generation benchmark

不要混合。

---

## workload 3: entity-redstone-heavy

构造稳定可重复的：

- mobs
- hoppers
- redstone
- block entities
- farms
- entity ticking

目标：

提高 tick CPU 和 allocation pressure。

---

# 十、玩家数量 scaling

至少支持：

10
25
50
100
200

如果机器性能允许继续：

300
400
...

目标不是一定跑到 400。

目标是找到：

p95 MSPT 接近或超过 50 ms

的 overload region。

最后希望能绘制：

MSPT vs player count

并确定每个 JVM 的 saturation/overload behavior。

---

# 十一、世界状态必须可恢复

创建：

golden-world

每轮 benchmark 开始前恢复完全相同的 world。

优先考虑：

btrfs snapshot

或：

cp --reflink=always

如果 filesystem 不支持 reflink，再 fallback 到 rsync/cp。

不要在连续 benchmark 中复用被上一轮修改过的世界。

world snapshot checksum / ID 必须写入 metadata。

---

# 十二、Warmup

Minecraft Server 是长期 JIT workload。

必须同时研究：

cold behavior

和：

steady state behavior。

建议每轮：

0–5 min:
cold/startup

5–20 min:
warmup

20–50 min:
measurement

参数要可配置。

正式 steady-state summary 默认使用 measurement window。

但 cold/warmup 数据不能丢弃。

记录：

- server startup time
- warmup MSPT
- CPU
- GC
- JIT activity
- steady-state MSPT

---

# 十三、核心性能指标

不要把 TPS 作为主指标。

记录每 tick timing，并计算：

mean MSPT
median MSPT
p90
p95
p99
p99.9
max

另外记录：

TPS

但 TPS 只是辅助指标。

如果可能，记录 tick timestamp，从而可以将：

GC pause

与：

MSPT spike

按照时间关联。

---

# 十四、GC 数据

HotSpot：

使用 unified GC logging，例如：

-Xlog:gc*:file=gc.log:time,uptime,level,tags

根据 Java 25 实际语法验证。

解析：

GC count
pause duration
p50 pause
p95 pause
p99 pause
max pause
GC CPU time
GC wall time
heap before/after
old generation occupancy
allocation pressure
promotion behavior
Full GC

OpenJ9：

使用 OpenJ9 推荐的 verbose GC / logging 机制。

不要试图用 HotSpot parser 解析 OpenJ9 log。

建立统一中间格式：

gc-events.jsonl

例如：

timestamp
runtime
gc_type
pause_ms
heap_before
heap_after
cause

无法映射的字段允许为空。

---

# 十五、系统级数据

Linux 至少采集：

pidstat
/proc
perf stat

研究是否还能安全使用：

perf record
JFR
async-profiler

但 profiler-heavy run 和正常 benchmark run 要分开。

正常 run 至少记录：

process CPU %
RSS
VSZ
minor faults
major faults
context switches
threads

perf stat：

cycles
instructions
IPC
cache references
cache misses
branches
branch misses

如果权限允许。

---

# 十六、内存指标

记录：

Xmx
committed heap
used heap
RSS
native memory

HotSpot 可以考虑：

Native Memory Tracking

但如果 NMT 对性能有 measurable overhead，则单独作为 profiling run。

OpenJ9 使用对应机制。

目标是比较：

performance

和：

memory efficiency

而不仅仅是 tick latency。

---

# 十七、CPU 环境控制

benchmark 启动前记录：

lscpu
numactl --hardware
cpupower frequency-info

尽量固定：

CPU affinity

例如：

taskset

如果是 NUMA 系统，研究：

numactl --cpunodebind
numactl --membind

不要在不同 run 随机跨 NUMA node。

CPU frequency governor 尽量设为：

performance

如果无法修改，至少记录当前状态。

避免其他高负载进程。

记录机器 load。

---

# 十八、实验重复

每个 configuration：

至少 5 runs。

最好支持：

10 runs。

不要固定顺序：

G1 ×5
然后 ZGC ×5

而应随机化 configuration order。

支持 deterministic random seed。

例如：

benchmark seed = 20260930

保存实际执行顺序。

---

# 十九、统计

不要只输出单次最快结果。

每个 config 聚合：

median
mean
standard deviation
min/max
95% confidence interval

p95/p99 MSPT 也要跨 run 汇总。

保留所有 raw data。

严禁只保留最终平均值。

---

# 二十、目录设计

建议类似：

benchmark/
  config/
    jdks.yaml
    workloads.yaml
    benchmark.yaml

  jdks/
    temurin-25/
    corretto-25/
    graalvm-25/
    semeru-25/

  server/
    paper-26.2-build-xxx.jar
    config/

  worlds/
    golden/
    work/

  traces/
    survival-mixed/
    exploration/
    entity-redstone/

  runs/
    <run-id>/
      metadata.json
      server.log
      gc.log
      mspt.csv
      pidstat.csv
      perf.txt
      client.log

  scripts/

  analysis/

  results/

不要提交巨大的 JDK binary/world 文件到 git。

使用：

.gitignore

以及 download/bootstrap scripts。

---

# 二十一、JDK manifest

建立统一的：

config/jdks.yaml

类似：

jdks:

  temurin25:
    family: hotspot
    jit: c2
    vendor: eclipse-adoptium
    java_major: 25
    home: ...

  graalvm25:
    family: hotspot
    jit: graal
    vendor: graalvm-community
    java_major: 25
    home: ...

  semeru25:
    family: openj9
    jit: openj9
    vendor: ibm
    java_major: 25
    home: ...

每个 runtime 初始化时自动采集：

java -version
java -XshowSettings:vm -version

保存完整输出。

不要完全相信配置文件中的手写 vendor/version。

---

# 二十二、GC capability detection

实现 runtime probe。

HotSpot-like JVM：

自动尝试 GC flags。

OpenJ9：

自动尝试不同：

-Xgcpolicy

输出 capability manifest。

例如：

{
  "runtime": "temurin25",
  "gcs": [
    "g1",
    "zgc",
    "parallel",
    "shenandoah"
  ]
}

不要 hardcode “所有 HotSpot 一定支持 Shenandoah”。

---

# 二十三、参数公平性

第一阶段比较默认策略。

共同参数尽量只有：

-Xms8G
-Xmx8G

加：

GC selector

和必要 logging。

不要把：

Aikar flags G1

与：

default ZGC

进行比较。

这会混入大量 tuning variable。

实验分为：

## Default-policy benchmark

尽量只指定 heap + GC。

## Tuned benchmark

以后再对每个 GC 使用合理 tuning。

两套结果严格分开。

---

# 二十四、Paper-specific profiler

研究 Paper 26.2 当前推荐 profiler。

如果内置 spark 可用，可以作为辅助数据源。

但不要让 heavy profiling 一直开着影响正式 benchmark。

如果 spark 能提供可靠 tick timing/export API，可以用于 MSPT 数据。

否则自己寻找更低 overhead 的采集方式。

---

# 二十五、结果输出

最终自动生成：

results/summary.csv
results/summary.json

至少包括：

runtime
vendor
java_version
vm
jit
gc
heap
workload
players

mean_mspt
p50_mspt
p95_mspt
p99_mspt
p999_mspt
max_mspt

cpu_percent
cpu_seconds
rss_mean
rss_max

gc_count
gc_pause_total
gc_pause_p95
gc_pause_p99
gc_pause_max

startup_seconds
warmup_behavior

---

# 二十六、图表

生成：

1. mean MSPT vs players
2. p95 MSPT vs players
3. p99 MSPT vs players
4. CPU usage vs players
5. RSS vs players
6. GC pause CDF
7. MSPT time series
8. GC pause 与 MSPT spike 对齐图
9. startup/warmup MSPT time series

不要画误导性的 truncated-axis bar chart。

---

# 二十七、第一阶段任务顺序

不要一次性做完整项目。

按照以下顺序推进：

## Phase 1：环境探索

检查：

OS
hardware
filesystem
installed Java
available disk
perf permissions

研究 Paper 26.2。

研究可用 benchmark/replay 工具。

输出：

docs/exploration.md

---

## Phase 2：JDK bootstrap

至少自动安装或发现：

Temurin 25
Corretto 25
GraalVM CE 25
IBM Semeru/OpenJ9 25

验证每一个：

java -version

构建：

jdks.yaml

---

## Phase 3：Paper smoke test

让同一个 Paper 26.2 jar 分别在：

Temurin
Corretto
GraalVM
Semeru

上成功启动。

处理 JVM-specific incompatible flags。

---

## Phase 4：GC capability probe

生成实际 matrix。

---

## Phase 5：最小 workload

先实现一个短 benchmark：

1 runtime
1 GC
少量 bot
5–10 min

确保可以稳定：

启动
load world
施加负载
采数据
停止
归档结果

---

## Phase 6：完整 workload

加入：

survival-mixed
exploration
entity-redstone-heavy

---

## Phase 7：完整 JVM matrix

运行核心组合。

---

# 二十八、非常重要的原则

不要为了完成任务而伪造数据。

如果某个 JDK：

下载失败
不兼容
Paper crash
benchmark client 不支持 26.2
某 GC 不存在

就记录：

unsupported
skipped
failed

以及具体原因。

不要偷偷换成 Java 21。

Paper 26.2 的测试必须 Java >= 25。

---

# 二十九、网络资料

在做实现前优先查询官方资料。

Paper：
PaperMC 官方文档和下载源。

JDK：
各 vendor 官方网站或官方 GitHub。

OpenJ9：
Eclipse OpenJ9 官方文档。

Semeru：
IBM 官方或 ibmruntimes 官方 GitHub。

不要从随机 JDK 下载站获取二进制。

下载后保存 SHA256。

---

# 三十、最终目标

最终仓库应该让我可以执行类似：

./bench bootstrap

./bench probe

./bench run 
  --runtime temurin25 
  --gc g1 
  --heap 8G 
  --workload survival-mixed 
  --players 100

或者：

./bench matrix core

然后自动完成：

恢复 world
启动 Paper
等待 ready
warmup
启动 bots/replay
采集系统指标
采集 MSPT
采集 GC
停止 server
归档结果

最后：

./bench analyze

生成汇总数据和图表。

优先保证：

可重复性
实验公平
raw data 完整
自动化

其次才是界面美观。

现在开始。

第一步先不要大规模写代码。

先探索当前 repository、机器环境、Paper 26.2、可用 JDK 25 runtime，以及当前可用于 Minecraft 26.2 的 benchmark/replay 工具。

将调查结果写入 docs/exploration.md，然后根据实际发现制定实现路线，并开始完成 Phase 1–3。
