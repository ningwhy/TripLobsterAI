// 账号体系：scrypt 密码哈希 + 不透明会话令牌（存库、可撤销）
import crypto from 'node:crypto';

function hashPassword(pw) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(pw, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

function verifyPassword(pw, stored) {
  const [salt, hash] = String(stored).split(':');
  if (!salt || !hash) return false;
  const check = crypto.scryptSync(pw, salt, 64).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(check, 'hex'));
}

function createSession(db, userId) {
  const token = crypto.randomBytes(32).toString('hex');
  db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run(token, userId, Date.now());
  return token;
}

export function requireAuth(db) {
  return (req, res, next) => {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) return res.status(401).json({ error: '未登录' });
    const row = db.prepare('SELECT user_id FROM sessions WHERE token = ?').get(token);
    if (!row) return res.status(401).json({ error: '登录已过期' });
    req.userId = Number(row.user_id);
    next();
  };
}

export function registerAuthRoutes(app, db) {
  app.post('/api/auth/register', (req, res, next) => {
    try {
      const { username, password } = req.body || {};
      const name = String(username ?? '').trim();
      const pw = String(password ?? '');
      if (!name || name.length < 2) {
        return res.status(400).json({ error: '用户名至少2个字符' });
      }
      if (pw.length < 6) {
        return res.status(400).json({ error: '密码至少6位' });
      }
      const exists = db.prepare('SELECT id FROM users WHERE username = ?').get(name);
      if (exists) return res.status(409).json({ error: '用户名已存在' });
      const r = db.prepare('INSERT INTO users (username, pass_hash, created_at) VALUES (?, ?, ?)').run(name, hashPassword(password), Date.now());
      const userId = Number(r.lastInsertRowid);
      const token = createSession(db, userId);
      res.json({ token, username: name, userId });
    } catch (e) { next(e); }
  });

  app.post('/api/auth/login', (req, res, next) => {
    try {
      const { username, password } = req.body || {};
      const user = db.prepare('SELECT id, pass_hash FROM users WHERE username = ?').get(String(username ?? '').trim());
      if (!user || !verifyPassword(String(password ?? ''), user.pass_hash)) {
        return res.status(401).json({ error: '用户名或密码错误' });
      }
      const token = createSession(db, Number(user.id));
      res.json({ token, username: String(username).trim(), userId: Number(user.id) });
    } catch (e) { next(e); }
  });

  app.post('/api/auth/logout', requireAuth(db), (req, res) => {
    const h = req.headers.authorization || '';
    db.prepare('DELETE FROM sessions WHERE token = ?').run(h.slice(7));
    res.json({ ok: true });
  });

  app.get('/api/me', requireAuth(db), (req, res) => {
    const u = db.prepare('SELECT username FROM users WHERE id = ?').get(req.userId);
    res.json({ userId: req.userId, username: u?.username || null });
  });
}
