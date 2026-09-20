// api/chat.js — Fonction serverless Vercel : « Parler avec ma pensée ».
// Proxy vers l'API Anthropic, ANCRÉ sur le corpus de notes (récupération + « cite ou refuse »).
// La clé API reste côté serveur (variable d'env ANTHROPIC_API_KEY). Aucune dépendance npm.

const CORPUS_URL = "https://pierrejeantribot.com/corpus-index.json";
const MODEL = process.env.ANTHROPIC_MODEL || "claude-sonnet-5";
const TOP_K = 4;              // notes envoyées au modèle par question
const MAX_NOTE_CHARS = 6000;  // borne par note (coût)
const MAX_TOKENS = 1400;      // borne la réponse (coût) — assez pour une réponse de fond complète

let CORPUS = null; // cache d'invocation à chaud

// Garde-fou coût/abus : plafond par IP (best-effort, en mémoire d'instance à chaud).
// Protection robuste globale = Vercel KV/Redis (évolution possible). Ici : casse le harcèlement simple.
const RL = new Map();
const RL_MAX = 12;                 // questions max par fenêtre
const RL_WINDOW = 10 * 60 * 1000;  // 10 minutes
const MAX_HISTORY = 8;             // derniers tours envoyés au modèle (coût)
function clientIp(req) {
  const xff = req.headers["x-forwarded-for"];
  return (xff ? String(xff).split(",")[0] : (req.socket && req.socket.remoteAddress) || "?").trim();
}
function rateLimited(ip) {
  const now = Date.now();
  const arr = (RL.get(ip) || []).filter(t => now - t < RL_WINDOW);
  if (arr.length >= RL_MAX) { RL.set(ip, arr); return true; }
  arr.push(now); RL.set(ip, arr);
  if (RL.size > 800) { for (const [k, v] of RL) { if (!v.some(t => now - t < RL_WINDOW)) RL.delete(k); } }
  return false;
}

async function loadCorpus() {
  if (CORPUS) return CORPUS;
  const r = await fetch(CORPUS_URL, { cache: "force-cache" });
  if (!r.ok) throw new Error("corpus indisponible");
  CORPUS = (await r.json()).notes || [];
  return CORPUS;
}

function norm(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}
const STOP = new Set(("le la les un une des de du au aux et ou que qui dans pour sur avec sans " +
  "en par ne pas plus est sont ce cette ces son sa ses leur il elle on nous vous the of to and " +
  "a in is it that this on for with").split(" "));
function terms(s) {
  return (norm(s).match(/[a-zàâäéèêëïîôöùûüç0-9]{3,}/g) || []).filter(t => !STOP.has(t));
}

function stem(t) { return t.length > 6 ? t.slice(0, 6) : t; } // radical grossier (couvre les variantes : travaille/travailler…)
function retrieve(corpus, query, k) {
  const q = terms(query).map(stem);
  if (!q.length) return corpus.slice(0, k);
  const scored = corpus.map(n => {
    const body = norm(n.title_fr + " " + n.title_en + " " + n.text);
    const title = norm(n.title_fr + " " + n.title_en);
    let score = 0;
    for (const t of q) {
      let i = 0;
      while ((i = body.indexOf(t, i)) !== -1) { score++; i += t.length; }
      if (title.includes(t)) score += 6; // fort boost titre
    }
    return { n, score };
  }).sort((a, b) => b.score - a.score);
  const hits = scored.filter(x => x.score > 0).slice(0, k).map(x => x.n);
  return hits.length ? hits : corpus.slice(0, k);
}

const SYSTEM = [
  "Tu es « la pensée » du corpus de notes de Pierre-Jean Tribot — éditeur francophone, rédacteur en chef de Crescendo Magazine, qui écrit sur l'IA, la culture, l'éducation et la souveraineté cognitive.",
  "",
  "RÈGLES ABSOLUES :",
  "1. Réponds UNIQUEMENT à partir des extraits de notes fournis plus bas. N'utilise aucune connaissance générale extérieure au corpus.",
  "2. Cite systématiquement, entre parenthèses, le titre des notes sur lesquelles tu t'appuies.",
  "3. Si la réponse n'est pas dans les extraits fournis, dis-le explicitement (« Ce n'est pas traité dans le corpus ») et oriente vers la ou les notes les plus proches. N'invente jamais une position.",
  "4. Registre du corpus : diagnostiquer plutôt que commenter, argumenter plutôt que réciter. Français (ou anglais) sobre, précis, sans emphase creuse.",
  "5. Réponds dans la langue de la question.",
  "6. Tu n'es pas Pierre-Jean Tribot en personne : tu es la voix de son corpus. Reste concis (quelques paragraphes au plus)."
].join("\n");

async function readBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string" && req.body) { try { return JSON.parse(req.body); } catch (e) { return {}; } }
  const raw = await new Promise((resolve) => {
    let d = ""; req.on("data", c => d += c); req.on("end", () => resolve(d)); req.on("error", () => resolve(""));
  });
  try { return JSON.parse(raw || "{}"); } catch (e) { return {}; }
}

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (req.method !== "POST") { res.statusCode = 405; res.end(JSON.stringify({ error: "method_not_allowed" })); return; }

  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) { res.statusCode = 500; res.end(JSON.stringify({ error: "cle_api_absente", message: "ANTHROPIC_API_KEY non configurée dans Vercel." })); return; }

  if (rateLimited(clientIp(req))) {
    res.statusCode = 429;
    res.end(JSON.stringify({ error: "trop_de_requetes", message: "Trop de questions en peu de temps. Réessayez dans quelques minutes." }));
    return;
  }

  try {
    const body = await readBody(req);
    // Historique de conversation (mémoire) : soit un tableau messages[{role,content}], soit une question simple.
    let history = [];
    if (Array.isArray(body.messages)) {
      history = body.messages
        .filter(m => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string" && m.content.trim())
        .slice(-MAX_HISTORY)
        .map(m => ({ role: m.role, content: m.content.slice(0, 2000) }));
    } else if (body.question) {
      history = [{ role: "user", content: String(body.question).slice(0, 2000) }];
    }
    if (!history.length || history[history.length - 1].role !== "user") {
      res.statusCode = 400; res.end(JSON.stringify({ error: "question_vide" })); return;
    }
    const q = history[history.length - 1].content.trim(); // dernière question, pour la récupération
    if (q.length > 1000) { res.statusCode = 400; res.end(JSON.stringify({ error: "question_trop_longue" })); return; }

    const corpus = await loadCorpus();
    const picked = retrieve(corpus, q, TOP_K);
    const context = picked.map(n =>
      "### " + n.title_fr + " (" + n.url + ")\n" + n.text.slice(0, MAX_NOTE_CHARS)
    ).join("\n\n---\n\n");

    const payload = {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: SYSTEM + "\n\n=== EXTRAITS DU CORPUS ===\n\n" + context,
      messages: history
    };

    const ar = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify(payload)
    });
    if (!ar.ok) {
      const t = await ar.text();
      res.statusCode = 502;
      res.end(JSON.stringify({ error: "api_amont", status: ar.status, detail: t.slice(0, 300) }));
      return;
    }
    const data = await ar.json();
    const blocks = Array.isArray(data.content) ? data.content : [];
    const answer = blocks.filter(b => b && b.type === "text" && b.text).map(b => b.text).join("\n").trim();
    const out = {
      answer: answer,
      sources: picked.map(n => ({ title: n.title_fr, title_en: n.title_en, url: n.url }))
    };
    if (!answer) {
      out._debug = {
        model: data.model,
        stop_reason: data.stop_reason,
        types: blocks.map(b => b && b.type),
        api_error: data.error || null
      };
    }
    res.statusCode = 200;
    res.end(JSON.stringify(out));
  } catch (e) {
    res.statusCode = 500;
    res.end(JSON.stringify({ error: "erreur_serveur", message: String(e && e.message || e) }));
  }
};
