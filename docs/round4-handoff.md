# Round 4 交接文档(2026-10-09 ~09:20 暂停,待 WSL 内核升级)

> 给下一个 agent session:读完本文档即可继续,无需翻历史会话。

## 任务目标

在 **no-Via 环境**(原生 26.2 bot,不装 ViaVersion/ViaBackwards)下重做完整 benchmark 矩阵,
产出全新结论替换旧数据。旧结果文档已归档 `docs/archive/round{1,2,3}*.md`(不再展示),
`runs/` 下全部原始数据保留未删。R3 已证明 Via 对 MSPT 无可测影响(见 archive/round3-novia.md
的勘误),故 no-Via 结果即最终结论。

## 矩阵设计

- 7 配置 × 4 玩家档 × 3 reps = **84 轮**:openjdk25/default、oracle25/default、
  temurin25/{g1,shenandoah,parallel,zgc}、graalvmce25/g1;档位 25/50/100/150(p200 已知崩溃,不测)
- 每轮:600s warmup + 600s measure,16G 堆,workload=mixed,seed=20260930,
  server 核 0-7、bot 核 8-15,workspace `workspaces/wsN`,端口 25567
- shuffle 盐 `r4`(与 R2/R3 的执行顺序解耦,防周期性强日漂移与配置相关)

## 当前状态

- **67/84 完成,0 失败**;剩 **17 轮**(约 5.5-6h)。暂停时有一个进行中的 run 被 kill,
  其数据不完整,resume 会自动重跑该格,无需手工清理。
- 矩阵日志:`runs/scaling-novia.log`(R3 与 R4 共用;R4 有效块 = **最后一个及以后出现的
  `# scaling start 2026-10-08T14:23:44` 头之后**;更早有一小段我误传参数造成的 4 条 FAILED 垃圾记录,忽略)。
  resume 会再追加一个新的 `# scaling start ... resume_after=...` 头。

## 恢复运行(WSL 升级完后)

```bash
cd /home/lwzheng/mctest
setsid nohup ./scripts/run-scaling.sh --botversion 26.2 --workspace wsN --port 25567 \
    --resume-after 20261008-142344 > runs/scaling-r4.out 2>&1 < /dev/null &
```

- `--resume-after 20261008-142344`:跳过该时间戳之后已完成(markers.log 含
  `measurement window end`)的格子;已用 `--dry-run` 验证:67 SKIP + 17 to-run。
- 注意 `--workspace wsN`(**相对名**,脚本自己拼 `$ROOT/workspaces/`;传 `workspaces/wsN` 会
  双重拼接导致 rsync 到 `/world` 失败——踩过)。
- 查进度:`tail -n +$(awk '/^# scaling start/{n=NR} END{print n}' runs/scaling-novia.log) runs/scaling-novia.log | grep -c " DONE"`
- 期间不要跑其他重负载;不要中断,WSL 若再重启就再用同一条 resume 命令(幂等)。

## 跑完后的收尾(下一个 session 的工作)

1. 聚合:只统计满足以下全部条件的 run 目录——
   - 目录名 `runs/2026*-<runtime>-<gc>-mixed-p<N>-wsN`,时间戳 **≥ 20261008-142344**
   - `markers.log` 含 `measurement window end`(完整的)
   - ⚠️ 不要纳入:10-08 的 6 个 ad-hoc A/B 目录(102957/103931/104942/111003/113115/115133,
     其中 wsN 的三个时间戳 < 142344 已被过滤,ws0 的被 -wsN 过滤,双重保险);
     R3 全部目录(时间戳 ≤ 20261008-055722)同理被过滤
   - 每轮取 measurement window 内的 MSPT(mean/p95/p99)、掉线数(bots/kicks)、GC 暂停(gc.log)
2. 写 `docs/round4-novia.md`:排名表、过载点(p150 谁撑不住)、推荐配置、与 R3 的**排名层面**
   对照(绝对值不可跨矩阵比——环境漂移,见 methodology.md 陷阱 #7)
3. 更新 README.md TL;DR(去掉"进行中"标注)
4. commit + push

## 已观察到的部分数据结论(67/84,供参考,以最终文档为准)

- p25/p50/p100:全部配置差异在噪声内(~8-19ms)
- p150:**ZGC / Shenandoah(~58-59ms)≪ G1 系(80-87ms)< Parallel(~115ms)**,ZGC/Shen 领先 ~32%
- 与 R3 排名完全一致,结论方向稳健

## 环境备忘

- 22 个 JDK 装在 sdkman(`~/.sdkman/candidates/java/`);矩阵只用上述 7 个
- 原生 26.2 bot:`bots/bot.js` 加 `--version 26.2` 即可(由 --botversion 26.2 传入)
- WSL2 / Ryzen 7 5700X / 62GB RAM;宿主负载小时级漂移,A/B 必须交错(methodology.md §7)
