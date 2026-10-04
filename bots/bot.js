#!/usr/bin/env node
// bot.js — mineflayer workload generator (P6).
// Modes:
//   mixed   — random walk + jump + dig + swing (survival-mixed approximation)
//   explore — sprint in a fixed per-bot bearing away from spawn (chunk load/gen)
//   idle    — connect and stand (baseline)
// Deterministic via --seed. Server must run creative + force-gamemode so bots
// never die mid-run (load stays constant).
// Usage: node bot.js --count 10 --host 127.0.0.1 --port 25565 --seed 20260930 \
//          --mode mixed [--version 26.1]
const mineflayer = require('mineflayer')

const args = {}
for (let i = 2; i < process.argv.length - 1; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1]
const COUNT = parseInt(args.count || '10', 10)
const HOST = args.host || '127.0.0.1'
const PORT = parseInt(args.port || '25565', 10)
const VERSION = args.version || '26.1'
const SEED = parseInt(args.seed || '20260930', 10)
const MODE = args.mode || 'mixed'
const OFFSET = parseInt(args.offset || '0', 10)   // shard offset for username + rng
const STAGGER = parseInt(args.stagger || '500', 10)  // ms between joins

function rng (seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function startBot (i) {
  const rand = rng(SEED + (OFFSET + i) * 7919)
  const bot = mineflayer.createBot({
    host: HOST, port: PORT,
    username: `bench_${String(OFFSET + i).padStart(3, '0')}`,
    version: VERSION, auth: 'offline'
  })
  bot.once('spawn', () => {
    console.log(`[bot ${i}] spawned mode=${MODE} at ${bot.entity.position}`)
    if (MODE === 'mixed') actMixed()
    else if (MODE === 'explore') actExplore()
  })
  bot.on('error', e => console.log(`[bot ${i}] error: ${e.message}`))
  bot.on('end', reason => console.log(`[bot ${i}] disconnected: ${reason}`))
  bot.on('death', () => console.log(`[bot ${i}] DIED (load loss!)`))

  // --- mixed: walk bursts + dig + swing, contained within pregen area (r=400) ---
  function actMixed () {
    let yaw = rand() * Math.PI * 2
    const p = bot.entity.position
    // MC yaw: dx=-sin(yaw), dz=cos(yaw); to head to origin yaw=atan2(x, -z)
    if (Math.hypot(p.x, p.z) > 400) yaw = Math.atan2(p.x, -p.z)
    const dur = 1000 + Math.floor(rand() * 4000)
    bot.look(yaw, 0, true)
    bot.setControlState('forward', true)
    if (rand() < 0.4) bot.setControlState('jump', true)
    if (rand() < 0.5) tryDig()
    if (rand() < 0.3) bot.swingArm()
    setTimeout(() => {
      bot.setControlState('forward', false)
      bot.setControlState('jump', false)
      setTimeout(actMixed, 500 + Math.floor(rand() * 1500))
    }, dur)
  }

  function tryDig () {
    // dig the block 2m ahead at foot level, then put something back
    const p = bot.entity.position
    const ahead = p.offset(-Math.sin(bot.entity.yaw) * 2, 0, Math.cos(bot.entity.yaw) * 2).floored()
    const block = bot.blockAt(ahead)
    if (!block || block.name === 'air' || block.name === 'bedrock') return
    bot.dig(block, true).then(() => tryPlace(ahead)).catch(() => {})
  }

  function tryPlace (at) {
    const item = bot.inventory.items()[0]
    if (!item) return
    const ref = bot.blockAt(at.offset(0, -1, 0))
    if (!ref || ref.name === 'air') return
    bot.equip(item, 'hand').then(() => bot.placeBlock(ref, { x: 0, y: 1, z: 0 })).catch(() => {})
  }

  // --- explore: sprint a fixed bearing, forever ---
  function actExplore () {
    const bearing = (i / COUNT) * Math.PI * 2
    bot.look(bearing, 0, true)
    bot.setControlState('forward', true)
    bot.setControlState('sprint', true)
    setInterval(() => {
      bot.look(bearing, 0, true) // re-assert (knockback, water)
      bot.setControlState('forward', true)
      bot.setControlState('sprint', true)
      bot.setControlState('jump', rand() < 0.3)
    }, 1000)
  }
}

for (let i = 0; i < COUNT; i++) {
  setTimeout(() => startBot(i), i * STAGGER)
}
process.on('SIGTERM', () => process.exit(0))
process.on('SIGINT', () => process.exit(0))
