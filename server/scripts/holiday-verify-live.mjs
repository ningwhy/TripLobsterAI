#!/usr/bin/env node
// 上线前一次性比对：内置快照 vs CDN 最新版，逐条打印差异。
//
// ## 为什么不自动改文件（设计 §5 T01 第 5 条）
// 国务院安排会调整（2020 年春节就曾延长），自动覆盖会让「谁改的、改成什么」
// 无从追溯。本脚本只**报告**，人确认后跑 `holiday-snapshot.mjs` 显式重生成，
// 并在 PR 里留痕 —— 这是 §6.3「任何人工编辑须在 PR 说明中留痕」的落地形式。
//
// 用法：
//   node server/scripts/holiday-verify-live.mjs            # 当年 + 次年
//   node server/scripts/holiday-verify-live.mjs 2026       # 指定年份
//
// 退出码：0 = 无差异；1 = 有差异或取数/校验失败（CI 可据此拦截）。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cdnUrlOf, validateHolidayYear } from '../src/holiday.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SNAP_DIR = path.resolve(__dirname, '..', 'src', 'data', 'holiday-cn');

const currentYear = new Date().getUTCFullYear();
const years = process.argv.slice(2).map(Number).filter((n) => Number.isInteger(n) && n > 1900);
const targets = years.length ? years : [currentYear, currentYear + 1];

let problems = 0;

for (const year of targets) {
  console.log(`\n=== ${year} ===`);

  // ---- 快照侧 ----
  let snap = null;
  try {
    snap = validateHolidayYear(JSON.parse(fs.readFileSync(path.join(SNAP_DIR, `${year}.json`), 'utf8')), year);
  } catch (e) {
    console.log(`  ❌ 快照不可读或 schema 非法：${e.message}`);
    problems++;
    continue;
  }
  if (!snap) {
    console.log(`  ❌ 快照缺失或 schema 非法 —— P0-8 不允许上线`);
    problems++;
    continue;
  }

  // ---- CDN 侧 ----
  let live = null;
  try {
    const resp = await fetch(cdnUrlOf(year), { signal: AbortSignal.timeout(8000) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    live = validateHolidayYear(await resp.json(), year);
  } catch (e) {
    console.log(`  ⚠️  CDN 取数失败（${e.message}）—— 无法比对，快照仍可正常使用`);
    // 取不到线上不构成上线阻塞：快照在位即可（这正是 P0-8 兜底的意义）
    continue;
  }
  if (!live) {
    console.log(`  ⚠️  CDN 返回数据 schema 非法 —— 无法比对`);
    continue;
  }

  const snapMap = new Map(snap.days.map((d) => [d.date, d]));
  const liveMap = new Map(live.days.map((d) => [d.date, d]));
  const allDates = [...new Set([...snapMap.keys(), ...liveMap.keys()])].sort();

  const diffs = [];
  for (const date of allDates) {
    const a = snapMap.get(date);
    const b = liveMap.get(date);
    if (!a) {
      diffs.push(`  + 新增 ${date} ${b.name} ${b.isOffDay ? '放假' : '补班'}`);
    } else if (!b) {
      diffs.push(`  - 移除 ${date} ${a.name} ${a.isOffDay ? '放假' : '补班'}`);
    } else if (a.isOffDay !== b.isOffDay) {
      diffs.push(`  ~ 变更 ${date} ${a.name}：快照 ${a.isOffDay ? '放假' : '补班'} → CDN ${b.isOffDay ? '放假' : '补班'}`);
    } else if (a.name !== b.name) {
      diffs.push(`  ~ 改名 ${date}：${a.name} → ${b.name}`);
    }
  }

  if (diffs.length === 0) {
    console.log(`  ✅ 无差异（快照 ${snap.days.length} 条 / CDN ${live.days.length} 条）`);
  } else {
    console.log(`  ⚠️  ${diffs.length} 处差异：`);
    for (const d of diffs) console.log(d);
    console.log('     处理：确认后运行 `node server/scripts/holiday-snapshot.mjs` 重新生成快照。');
    problems++;
  }
}

console.log(
  problems === 0
    ? '\n✅ 全部年份无差异告警。'
    : `\n⚠️  ${problems} 个年份需要处理（详见上方输出）。本脚本不自动改文件。`,
);
process.exit(problems === 0 ? 0 : 1);
