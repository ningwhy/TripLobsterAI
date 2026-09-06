// 行程云同步：LWW（last-write-wins by updatedAt）+ 删除墓碑
import { requireAuth } from './auth.js';

export function registerSyncRoutes(app, db) {
  const auth = requireAuth(db);

  // 拉取：返回该用户全部行程（含墓碑），客户端做合并
  app.get('/api/sync/pull', auth, (req, res, next) => {
    try {
      const since = parseInt(req.query.since || '0', 10);
      const rows = db.prepare(
        'SELECT trip_id, data, updated_at, deleted, deleted_at FROM trips WHERE user_id = ? AND updated_at >= ?'
      ).all(req.userId, since);
      const trips = [];
      const deleted = [];
      for (const r of rows) {
        if (Number(r.deleted) === 1) {
          deleted.push({ tripId: r.trip_id, deletedAt: Number(r.deleted_at || r.updated_at) });
        } else {
          trips.push({ tripId: r.trip_id, data: JSON.parse(r.data), updatedAt: Number(r.updated_at) });
        }
      }
      res.json({ trips, deleted, serverTime: Date.now() });
    } catch (e) { next(e); }
  });

  // 推送：客户端把本地行程和删除记录推上来，服务端 LWW 合并
  app.post('/api/sync/push', auth, (req, res, next) => {
    try {
      const { trips = [], deleted = [] } = req.body || {};
      let applied = 0;
      let conflicts = 0;
      const getStmt = db.prepare('SELECT updated_at, deleted FROM trips WHERE user_id = ? AND trip_id = ?');
      const upStmt = db.prepare(`
        INSERT INTO trips (user_id, trip_id, data, updated_at, deleted, deleted_at)
        VALUES (?, ?, ?, ?, 0, NULL)
        ON CONFLICT(user_id, trip_id) DO UPDATE SET
          data = excluded.data, updated_at = excluded.updated_at, deleted = 0, deleted_at = NULL
      `);
      const delStmt = db.prepare(`
        INSERT INTO trips (user_id, trip_id, data, updated_at, deleted, deleted_at)
        VALUES (?, ?, '{}', ?, 1, ?)
        ON CONFLICT(user_id, trip_id) DO UPDATE SET
          deleted = 1, deleted_at = max(COALESCE(trips.deleted_at, 0), excluded.deleted_at), updated_at = excluded.updated_at
      `);

      for (const t of trips) {
        if (!t?.tripId || !t?.data || !t?.updatedAt) continue;
        const ts = Number(t.updatedAt);
        if (!Number.isFinite(ts)) continue;
        const cur = getStmt.get(req.userId, t.tripId);
        if (cur && Number(cur.updated_at) > ts) { conflicts++; continue; } // 服务端更新，忽略
        upStmt.run(req.userId, t.tripId, JSON.stringify(t.data), ts);
        applied++;
      }
      for (const d of deleted) {
        if (!d?.tripId) continue;
        const ts = Number(d.deletedAt || Date.now());
        const cur = getStmt.get(req.userId, d.tripId);
        if (cur && Number(cur.updated_at) > ts && Number(cur.deleted) === 0) { conflicts++; continue; }
        delStmt.run(req.userId, d.tripId, ts, ts);
        applied++;
      }
      res.json({ ok: true, applied, conflicts, serverTime: Date.now() });
    } catch (e) { next(e); }
  });
}
