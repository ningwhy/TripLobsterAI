// LLM 增强层（可选）：任何 OpenAI 兼容接口，配置于 .env
// 未配置时 isLlmEnabled() 返回 false，规划全部走规则引擎
export function isLlmEnabled() {
  return Boolean(process.env.LLM_API_KEY && process.env.LLM_BASE_URL && process.env.LLM_MODEL);
}

export async function llmChat(messages, { timeoutMs = 30000, jsonMode = false } = {}) {
  if (!isLlmEnabled()) return null;
  const base = process.env.LLM_BASE_URL.replace(/\/$/, '');
  const body = {
    model: process.env.LLM_MODEL,
    messages,
    temperature: 0.3,
  };
  if (jsonMode) body.response_format = { type: 'json_object' };
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const resp = await fetch(`${base}/chat/completions`, {
      method: 'POST',
      signal: ctrl.signal,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.LLM_API_KEY}`,
      },
      body: JSON.stringify(body),
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    return data?.choices?.[0]?.message?.content || null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
