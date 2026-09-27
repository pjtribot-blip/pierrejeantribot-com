// api/search.js — API publique de RÉCUPÉRATION sur le corpus de Pierre-Jean Tribot.
// Aucune clé requise, aucune dépendance : renvoie les notes les plus pertinentes
// pour une requête (id, titre, URL, extrait). Pensée pour être appelée comme
// OUTIL par un agent IA (Claude, ChatGPT…) ou par tout site tiers.
// Ex : GET /api/search?q=souveraineté%20cognitive&k=5
//      -> { query, count, results:[{id,title_fr,title_en,url,score,excerpt}] }

const CORPUS_URL = "https://pierrejeantribot.com/corpus-index.json";
const DEFAULT_K = 5;
const MAX_K = 12;
const EXCERPT = 280;

let CORPUS = null;
async function loadCorpus() {
  if (CORPUS) return CORPUS;
  const r = await fetch(CORPUS_URL, { cache: "force-cache" });
  if (!r.ok) throw new Error("corpus indisponible");
  CORPUS = (await r.json()).notes || [];
  return CORPUS;
}

// Garde-fou d'abus : plafond souple par IP (best-effort, mémoire d'instance).
const RL = new Map(), RL_MAX = 60, RL_WINDOW = 5 * 60 * 1000;
function clientIp(req) {
  const xff = req.headers["x-forwarded-for"];
  return (xff ? String(xff).split(",")[0] : (req.socket && req.socket.remoteAddress) || "?").trim();
}
function rateLimited(ip) {
  const now = Date.now();
  const arr = (RL.get(ip) || []).filter(t => now - t < RL_WINDOW);
  if (arr.length >= RL_MAX) { RL.set(ip, arr); return true; }
  arr.push(now); RL.set(ip, arr);
  if (RL.size > 1000) { for (const [k, v] of RL) { if (!v.some(t => now - t < RL_WINDOW)) RL.delete(k); } }
  return false;
}

function norm(s) { return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }
const STOP = new Set(("le la les un une des de du au aux et ou que qui dans pour sur avec sans en par ne pas plus est sont ce cette ces son sa ses leur il elle on nous vous the of to and a in is it that this on for with").split(" "));
function terms(s) { return (norm(s).match(/[a-z0-9]{3,}/g) || []).filter(t => !STOP.has(t)); }
function stem(t) { return t.length > 6 ? t.slice(0, 6) : t; }

function excerptFor(text, qterms) {
  const nt = norm(text);
  let pos = -1;
  for (const t of qterms) { const i = nt.indexOf(t); if (i >= 0 && (pos < 0 || i < pos)) pos = i; }
  if (pos < 0) return text.slice(0, EXCERPT).trim() + (text.length > EXCERPT ? "…" : "");
  const start = Math.max(0, pos - 80), end = Math.min(text.length, pos + 200);
  return (start > 0 ? "…" : "") + text.slice(start, end).trim() + (end < text.length ? "…" : "");
}

function retrieve(corpus, query, k) {
  const q = terms(query).map(stem);
  if (!q.length) return [];
  return corpus.map(n => {
    const body = norm(n.title_fr + " " + n.title_en + " " + n.text);
    const title = norm(n.title_fr + " " + n.title_en);
    let score = 0;
    for (const t of q) {
      let i = 0; while ((i = body.indexOf(t, i)) !== -1) { score++; i += t.length; }
      if (title.includes(t)) score += 6;
    }
    return { n, score };
  }).filter(x => x.score > 0).sort((a, b) => b.score - a.score).slice(0, k);
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (req.method === "OPTIONS") { res.statusCode = 204; res.end(); return; }

  if (rateLimited(clientIp(req))) {
    res.statusCode = 429;
    res.end(JSON.stringify({ error: "rate_limited", message: "Trop de requêtes. Réessayez dans quelques minutes." }));
    return;
  }

  try {
    let q = "", k = DEFAULT_K;
    if (req.method === "GET") {
      const u = new URL(req.url, "https://x");
      q = u.searchParams.get("q") || u.searchParams.get("query") || "";
      k = parseInt(u.searchParams.get("k") || DEFAULT_K, 10);
    } else if (req.method === "POST") {
      let raw = ""; await new Promise(r => { req.on("data", c => raw += c); req.on("end", r); req.on("error", r); });
      let b = {}; try { b = JSON.parse(raw || "{}"); } catch (e) {}
      q = b.q || b.query || ""; k = parseInt(b.k || DEFAULT_K, 10);
    } else {
      res.statusCode = 405; res.end(JSON.stringify({ error: "method_not_allowed" })); return;
    }
    q = String(q).slice(0, 500).trim();
    k = Math.max(1, Math.min(MAX_K, isNaN(k) ? DEFAULT_K : k));
    if (!q) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: "query_vide", usage: "GET /api/search?q=<votre question>&k=5" }));
      return;
    }

    const corpus = await loadCorpus();
    const qt = terms(q).map(stem);
    const hits = retrieve(corpus, q, k);
    const out = {
      query: q,
      count: hits.length,
      source: "Corpus de Pierre-Jean Tribot — pierrejeantribot.com",
      license: "CC BY 4.0",
      results: hits.map(h => ({
        id: h.n.id,
        title_fr: h.n.title_fr,
        title_en: h.n.title_en,
        url: h.n.url,
        score: h.score,
        excerpt: excerptFor(h.n.text, qt)
      }))
    };
    res.statusCode = 200;
    res.end(JSON.stringify(out));
  } catch (e) {
    res.statusCode = 500;
    res.end(JSON.stringify({ error: "erreur_serveur", message: String(e && e.message || e) }));
  }
};
