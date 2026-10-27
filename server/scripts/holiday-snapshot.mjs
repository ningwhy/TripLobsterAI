#!/usr/bin/env node
// 节假日快照生成脚本：从 CDN 拉 {year}.json → schema 校验 → 落盘。
//
// ## 为什么需要它（P0-8 上线前提）
// 运行时不能假设容器可写、也不能让每次冷启动都依赖 CDN。快照随代码走，
// 是「日历事实只有一份产地」这条纪律的物理保证：代码库里这份文件就是权威副本。
//
// ## 溯源字段（设计 §6.3 / PRD Q3）
// 写入 `papers`（国务院公告链接，入库不渲染）、`generatedAt`、`source`。
// 任何人工编辑都必须在 PR 说明里留痕。
//
// 用法：
//   node server/scripts/holiday-snapshot.mjs            # 当年 + 次年
//   node server/scripts/holiday-snapshot.mjs 2026 2027  # 指定年份
//
// ⚠️ 使用内建 fetch：不引入 axios / node-fetch（设计 §6.1）。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cdnUrlOf, validateHolidayYear } from '../src/holiday.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.resolve(__dirname, '..', 'src', 'data', 'holiday-cn');

const currentYear = new Date().getUTCFullYear();
const years = process.argv.slice(2).map(Number).filter((n) => Number.isInteger(n) && n > 1900);
const targets = years.length ? years : [currentYear, currentYear + 1];

fs.mkdirSync(OUT_DIR, { recursive: true });

let failed = 0;

for (const year of targets) {
  const url = cdnUrlOf(year);
  let raw = null;
  try {
    const resp = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    raw = await resp.json();
  } catch (e) {
    console.log(`FAIL ${year} 取数失败：${e.message}`);
    failed++;
    continue;
  }

  const data = validateHolidayYear(raw, year);
  if (!data) {
    console.log(`FAIL ${year} schema 校验不通过 —— 未写入任何文件（不把脏数据落盘）`);
    failed++;
    continue;
  }

  const offDays = data.days.filter((d) => d.isOffDay === true).length;
  const workDays = data.days.filter((d) => d.isOffDay === false).length;
  const out = {
    year: data.year,
    papers: data.papers,
    days: data.days,
    // ---- 溯源三件套（设计 §2.5）----
    source: url,
    generatedAt: new Date().toISOString(),
    note: `放假日 ${offDays} 天 / 调休补班 ${workDays} 天`,
  };

  const file = path.join(OUT_DIR, `${year}.json`);
  fs.writeFileSync(file, `${JSON.stringify(out, null, 2)}\n`, 'utf8');
  console.log(
    `OK   ${year} → ${path.relative(process.cwd(), file)}  ` +
      `days=${data.days.length}（放假 ${offDays} / 补班 ${workDays}）papers=${data.papers.length}` +
      (data.days.length === 0 ? '   ⚠️ 空壳：无覆盖，运行时判 unknown' : ''),
  );
}

console.log(
  failed === 0
    ? '\n全部年份写入成功。'
    : `\n有 ${failed} 个年份失败 —— P0-8 要求当年 + 次年快照**都**在位才允许上线。`,
);
process.exit(failed === 0 ? 0 : 1);
