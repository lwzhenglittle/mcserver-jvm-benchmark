#!/usr/bin/env node
// add-26.2.js — register Minecraft 26.2 (protocol 776) with the local PrismarineJS stack.
//
// minecraft-data (3.117.0) ships data only up to 26.1, but protocolVersions.json already
// knows 26.2 = proto 776. ViaBackwards' Protocol26_2To26_1 proves the wire delta is tiny:
//   1. login clientbound success packet: trailing session UUID appended
//   2. play clientbound packet_teams: field order changed, color became optional varint
//      new order: name, prefix, suffix, nameTagVisibility, collisionRule, color(option varint), flags
//   3. registry: server adds "sulfur_cube_archetype" (client-side parse is generic, tolerated)
// Everything else (packet IDs, chunk format, entity data types) is unchanged from 26.1.
//
// Idempotent. Run once after `npm ci`. Usage: node add-26.2.js
const fs = require('fs')
const path = require('path')

const MD = path.join(__dirname, 'node_modules/minecraft-data/minecraft-data/data')
const SRC = path.join(MD, 'pc/26.1')
const DST = path.join(MD, 'pc/26.2')

// 1. copy 26.1 data as the 26.2 base
if (!fs.existsSync(DST)) fs.cpSync(SRC, DST, { recursive: true })

// 2. version.json
fs.writeFileSync(path.join(DST, 'version.json'), JSON.stringify({
  version: 776, minecraftVersion: '26.2', majorVersion: '26.2', releaseType: 'release'
}, null, 2))

// 3. protocol.json — apply the two wire changes
const protoPath = path.join(DST, 'protocol.json')
const proto = JSON.parse(fs.readFileSync(protoPath, 'utf8'))

// 3a. login success: append session UUID
const success = proto.login.toClient.types.packet_success
if (!success[1].some(f => f.name === 'sessionId')) {
  success[1].push({ name: 'sessionId', type: 'UUID' })
}

// 3b. packet_teams: 26.2 reorders the add/change container
const teams = proto.play.toClient.types.packet_teams
const sw = teams[1].find(f => f.anon) // teams = ['container', [team, mode, switch, players]]
for (const mode of ['add', 'change']) {
  const c = sw.type[1].fields[mode]
  if (!c || c[0] !== 'container') continue
  const fields = c[1]
  const byName = Object.fromEntries(fields.filter(f => f.name).map(f => [f.name, f]))
  if (!byName.prefix || fields[1].name === 'prefix') continue // already 26.2 layout
  const vis = fields.find(f => f.name === 'nameTagVisibility')
  const col = fields.find(f => f.name === 'collisionRule')
  const flags = fields.find(f => f.name === 'flags')
  c[1] = [
    byName.name,          // display name (nbt)
    byName.prefix,
    byName.suffix,
    vis,
    col,
    { name: 'formatting', type: ['option', 'varint'] }, // BOOL_OPTIONAL_VAR_INT
    flags
  ]
}

// 3c. play clientbound login (join game): 26.2 appends one byte (observed 0x00) that
// ViaBackwards does not remap -> consume it as a trailing boolean flag.
const loginPkt = proto.play.toClient.types.packet_login
if (loginPkt && !loginPkt[1].some(f => f.name === '_flag26_2')) {
  loginPkt[1].push({ name: '_flag26_2', type: 'bool' })
}
fs.writeFileSync(protoPath, JSON.stringify(proto))

// 4. data.js — the node loader's generated per-version getter table (dataPaths.json is unused
// at runtime): clone the 26.1 entry, pointing protocol/version at pc/26.2
const dataJsPath = path.join(__dirname, 'node_modules/minecraft-data/data.js')
let dataJs = fs.readFileSync(dataJsPath, 'utf8')
if (!dataJs.includes("'26.2'")) {
  const m = dataJs.match(/^ {4}'26\.1': \{[\s\S]*?\n {4}\}\n(?= {2}\},\n {2}'bedrock')/m)
  if (!m) throw new Error('26.1 entry not found in data.js')
  const clone = m[0]
    .replace("'26.1': {", "'26.2': {")
    .replace(/pc\/26\.1\/protocol\.json/, 'pc/26.2/protocol.json')
    .replace(/pc\/26\.1\/version\.json/, 'pc/26.2/version.json')
  dataJs = dataJs.replace(m[0], m[0].replace(/\}\n$/, '},\n') + clone)
  fs.writeFileSync(dataJsPath, dataJs)
}

// 5. versions.json — advertise 26.2
const vsPath = path.join(MD, 'pc/common/versions.json')
const vs = JSON.parse(fs.readFileSync(vsPath, 'utf8'))
if (!vs.includes('26.2')) {
  vs.push('26.2')
  fs.writeFileSync(vsPath, JSON.stringify(vs, null, 2))
}

// 6+7. mineflayer / minecraft-protocol supported version lists.
// Anchor on `'26.1']` (last array element) — NOT the first bare '26.1'
// (minecraft-protocol/src/version.js has defaultVersion: '26.1' earlier in the file).
function addToList (file, marker, version) {
  const p = path.join(__dirname, 'node_modules', file)
  let s = fs.readFileSync(p, 'utf8')
  if (s.includes(`'${version}'`)) return
  if (!s.includes(marker)) throw new Error(`marker ${marker} not found in ${file}`)
  s = s.replace(marker, marker.slice(0, -1) + `, '${version}']`)
  fs.writeFileSync(p, s)
}
addToList('mineflayer/lib/version.js', "'26.1']", '26.2')
addToList('minecraft-protocol/src/version.js', "'26.1']", '26.2')

// prismarine-chunk: version→implementation dispatch table. Chunk format unchanged
// in 26.2 (ViaBackwards uses ChunkType26_1 on both sides) -> alias the 26.1 impl.
;(function aliasChunkImpl () {
  const p = path.join(__dirname, 'node_modules/prismarine-chunk/src/index.js')
  let s = fs.readFileSync(p, 'utf8')
  if (s.includes('26.2:')) return
  const marker = "26.1: require('./pc/1.18/chunk')"
  if (!s.includes(marker)) throw new Error('26.1 chunk impl marker not found')
  s = s.replace(marker, `${marker},\n    26.2: require('./pc/1.18/chunk')`)
  fs.writeFileSync(p, s)
})()

// prismarine-physics: exact major-version feature list (no range logic)
;(function patchPhysicsFeatures () {
  const p = path.join(__dirname, 'node_modules/prismarine-physics/lib/features.json')
  const feats = JSON.parse(fs.readFileSync(p, 'utf8'))
  let changed = false
  for (const f of feats) {
    if (f.versions.includes('26.1') && !f.versions.includes('26.2')) {
      f.versions.push('26.2'); changed = true
    }
  }
  if (changed) fs.writeFileSync(p, JSON.stringify(feats, null, 2))
})()

console.log('26.2 (protocol 776) registered: minecraft-data pc/26.2 + mineflayer/minecraft-protocol lists')
