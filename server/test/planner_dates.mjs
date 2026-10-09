// FX-01 回归单测：addDays() 必须与时区无关
//
// 背景：旧实现 `new Date(iso + 'T00:00:00')` 按**本地时区**解析、`toISOString()` 按 **UTC** 输出，
// 东八区下 addDays('2026-10-01', 0) 会返回 '2026-09-30'（每一天系统性少 1 天）。
// multiCity.js 从 planner.js import 同一个 addDays，因此本用例同时守护两条管线。
//
// 运行：node test/planner_dates.mjs
//
// 三时区验证方式：在**同一进程内**切换 process.env.TZ（Node >= 16 支持运行时切换并重置 V8 日期缓存），
// 并在每个时区下先断言"时区确实生效了"（getTimezoneOffset 符合预期），避免"TZ 没切换但用例全绿"的假阳性。
// 注：本环境（沙箱）spawnSync 抛 EBUSY，无法用子进程方式，故改为进程内切换 + 生效校验。
import { addDays } from '../src/planner.js';

let failed = 0;

/** 断言并打印；失败计数。 */
function check(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ' | ' + extra : ''}`);
  if (!cond) failed++;
}

/** 在某个时区下执行一组断言（返回失败数）。 */
function runInZone(tz, expectedOffsets) {
  process.env.TZ = tz;
  let bad = 0;
  const eq = (name, actual, expected) => {
    const ok = actual === expected;
    console.log(`${ok ? 'PASS' : 'FAIL'} [${tz}] ${name}${ok ? '' : ` | 期望 ${expected} 实际 ${actual}`}`);
    if (!ok) bad++;
  };

  // 0) 先证明时区真的生效了（否则后面的"全绿"没有意义）
  const off = new Date('2026-10-01T00:00:00').getTimezoneOffset();
  eq('时区已生效（getTimezoneOffset 符合预期）', expectedOffsets.includes(off), true);
  if (!expectedOffsets.includes(off)) console.log(`       ↳ 实际 offset=${off} 分钟，预期之一 ${expectedOffsets.join('/')}`);

  // ---- 1. 基准（设计文档点名要求的三条）----
  eq('addDays(2026-10-01, 0) 恒等', addDays('2026-10-01', 0), '2026-10-01');
  eq('addDays(2026-10-01, 2) = 10-03', addDays('2026-10-01', 2), '2026-10-03');
  eq('addDays(2026-10-01, -1) = 09-30', addDays('2026-10-01', -1), '2026-09-30');

  // ---- 2. 跨月 / 跨年 / 平闰年边界 ----
  eq('跨月 10-31 +1', addDays('2026-10-31', 1), '2026-11-01');
  eq('跨月 11-01 -1', addDays('2026-11-01', -1), '2026-10-31');
  eq('跨年 12-31 +1', addDays('2026-12-31', 1), '2027-01-01');
  eq('跨年 01-01 -1', addDays('2026-01-01', -1), '2025-12-31');
  eq('平年 02-28 +1', addDays('2026-02-28', 1), '2026-03-01');
  eq('闰年 02-28 +1', addDays('2028-02-28', 1), '2028-02-29');
  eq('闰年 02-29 +1', addDays('2028-02-29', 1), '2028-03-01');
  eq('跨月大月 01-31 +1', addDays('2026-01-31', 1), '2026-02-01');

  // ---- 3. 天气 16 天窗口（WX-01/WX-02 依赖）：连续 17 天不得跳号 ----
  const golden = [
    '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04', '2026-10-05',
    '2026-10-06', '2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10',
    '2026-10-11', '2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15',
    '2026-10-16', '2026-10-17',
  ];
  let seqOk = true;
  let seqBad = '';
  for (let i = 0; i < golden.length; i++) {
    const got = addDays('2026-10-01', i);
    if (got !== golden[i]) { seqOk = false; seqBad = `i=${i} 期望 ${golden[i]} 实际 ${got}`; break; }
  }
  eq('连续 17 天窗口逐日对齐（黄金数据）', seqOk, true);
  if (seqBad) console.log(`       ↳ ${seqBad}`);

  // ---- 4. 长跨度（跨年）----
  eq('2026-10-01 +60', addDays('2026-10-01', 60), '2026-11-30');
  eq('2026-10-01 +92', addDays('2026-10-01', 92), '2027-01-01');

  // ---- 5. 非法入参：不得抛异常、不得静默产出错误日期 ----
  eq('空串原样返回', addDays('', 1), '');
  eq('null 原样返回', addDays(null, 1), '');
  eq('非日期串原样返回', addDays('not-a-date', 3), 'not-a-date');
  eq('带时间的 ISO 串取日期段', addDays('2026-10-01T12:00:00Z', 1), '2026-10-02');
  eq('NaN 偏移视为 0', addDays('2026-10-01', Number.NaN), '2026-10-01');
  eq('undefined 偏移视为 0', addDays('2026-10-01', undefined), '2026-10-01');

  // ---- 6. 与独立参考实现交叉验证（-400..+400 天）----
  // 参考实现走"UTC 毫秒累加"，不复用 Date.UTC 的年月日进位，可作为独立旁证
  const refAddDays = (iso, n) => {
    const [y, m, d] = iso.split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d) + n * 86400000);
    return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
  };
  let crossOk = true;
  let crossBad = '';
  for (let i = -400; i <= 400; i++) {
    const a = addDays('2026-03-01', i);
    const b = refAddDays('2026-03-01', i);
    if (a !== b) { crossOk = false; crossBad = `i=${i}: ${a} vs ${b}`; break; }
  }
  eq('与独立参考实现交叉验证（-400..+400 天）', crossOk, true);
  if (crossBad) console.log(`       ↳ ${crossBad}`);

  return bad;
}

console.log('=== addDays 时区无关性测试（FX-01）===');

const ZONES = [
  { tz: 'UTC', offsets: [0] },
  { tz: 'Asia/Shanghai', offsets: [-480] },                 // UTC+8，无夏令时
  { tz: 'America/New_York', offsets: [240, 300] },          // UTC-4(EDT) / UTC-5(EST)
];

for (const z of ZONES) {
  console.log(`\n-- 时区：TZ=${z.tz} --`);
  const bad = runInZone(z.tz, z.offsets);
  check(`三时区全绿 · ${z.tz}`, bad === 0, bad === 0 ? '' : `${bad} 条失败`);
}

// ---------- 反向验证：证明本测试确实能抓到 FX-01（不是"怎么写都过"）----------
console.log('\n-- 反向验证（旧实现复现，仅作证据，不计入失败数）--');
const legacyAddDays = (iso, n) => {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
};
process.env.TZ = 'Asia/Shanghai';
const legacyShanghai = legacyAddDays('2026-10-01', 0);
console.log(`旧实现 @Asia/Shanghai : addDays('2026-10-01',0) = ${legacyShanghai}`);
console.log(`新实现 @Asia/Shanghai : addDays('2026-10-01',0) = ${addDays('2026-10-01', 0)}`);
check('旧实现在东八区确实少一天（证明用例有效）', legacyShanghai === '2026-09-30' && addDays('2026-10-01', 0) === '2026-10-01',
  `旧=${legacyShanghai} 新=${addDays('2026-10-01', 0)}`);

console.log(failed ? `\n${failed} test(s) FAILED` : '\nALL TESTS PASSED');
process.exit(failed ? 1 : 0);
