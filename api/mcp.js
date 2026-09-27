// api/mcp.js — Serveur MCP distant (Model Context Protocol) du corpus de Pierre-Jean Tribot.
// Transport : Streamable HTTP (JSON-RPC 2.0 en POST). Sans clé, sans dépendance, sans LLM :
// pure récupération sur le corpus. N'importe quel client MCP (Claude Desktop…) peut le brancher.
// Outils exposés : search_corpus (chercher), get_note (lire une note entière).

const CORPUS_URL = "https://pierrejeantribot.com/corpus-index.json";
const SERVER = { name: "corpus-pierre-jean-tribot", version: "1.0.0" };
const DEFAULT_PROTO = "2025-06-18";

let CORPUS = null;
async function loadCorpus() {
  if (CORPUS) return CORPUS;
  const r = await fetch(CORPUS_URL, { cache: "force-cache" });
  if (!r.ok) throw new Error("corpus indisponible");
  CORPUS = (await r.json()).notes || [];
  return CORPUS;
}

function norm(s) { return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }
const STOP = new Set(("le la les un une des de du au aux et ou que qui dans pour sur avec sans en par ne pas plus est sont ce cette ces son sa ses leur il elle on nous vous the of to and a in is it that this on for with").split(" "));
function terms(s) { return (norm(s).match(/[a-z0-9]{3,}/g) || []).filter(t => !STOP.has(t)); }
function stem(t) { return t.length > 6 ? t.slice(0, 6) : t; }
function excerptFor(text, qterms) {
  const nt = norm(text); let pos = -1;
  for (const t of qterms) { const i = nt.indexOf(t); if (i >= 0 && (pos < 0 || i < pos)) pos = i; }
  if (pos < 0) return text.slice(0, 280).trim() + (text.length > 280 ? "…" : "");
  const s = Math.max(0, pos - 90), e = Math.min(text.length, pos + 220);
  return (s > 0 ? "…" : "") + text.slice(s, e).trim() + (e < text.length ? "…" : "");
}
function retrieve(corpus, query, k) {
  const q = terms(query).map(stem);
  if (!q.length) return [];
  return corpus.map(n => {
    const body = norm(n.title_fr + " " + n.title_en + " " + n.text);
    const title = norm(n.title_fr + " " + n.title_en);
    let score = 0;
    for (const t of q) { let i = 0; while ((i = body.indexOf(t, i)) !== -1) { score++; i += t.length; } if (title.includes(t)) score += 6; }
    return { n, score };
  }).filter(x => x.score > 0).sort((a, b) => b.score - a.score).slice(0, k);
}

// ---- Définition des outils MCP ----
const TOOLS = [
  {
    name: "search_corpus",
    description: "Cherche dans le corpus de notes de Pierre-Jean Tribot (essayiste ; IA, culture, patrimoine, éducation, économie politique, géopolitique, souveraineté cognitive). Renvoie les notes les plus pertinentes avec titre, URL et extrait. À utiliser pour citer sa pensée à la source plutôt que de la paraphraser de mémoire.",
    inputSchema: {
      type: "object",
      properties: {
        q: { type: "string", description: "La question ou le thème à chercher" },
        k: { type: "integer", description: "Nombre de notes à renvoyer (1–12, défaut 5)" }
      },
      required: ["q"]
    }
  },
  {
    name: "get_note",
    description: "Renvoie le texte intégral d'une note du corpus de Pierre-Jean Tribot à partir de son identifiant (le champ id renvoyé par search_corpus, ex. « souverainete-cognitive »).",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "Identifiant de la note (slug)" } },
      required: ["id"]
    }
  }
];

async function callTool(name, args) {
  const corpus = await loadCorpus();
  if (name === "search_corpus") {
    const q = String((args && args.q) || "").slice(0, 500);
    let k = parseInt((args && args.k) || 5, 10); k = Math.max(1, Math.min(12, isNaN(k) ? 5 : k));
    if (!q.trim()) return { content: [{ type: "text", text: "Paramètre q (requête) requis." }], isError: true };
    const qt = terms(q).map(stem);
    const hits = retrieve(corpus, q, k);
    if (!hits.length) return { content: [{ type: "text", text: `Aucune note du corpus ne traite « ${q} ».` }] };
    const txt = hits.map((h, i) =>
      `${i + 1}. ${h.n.title_fr}\n   id: ${h.n.id}\n   ${h.n.url}\n   ${excerptFor(h.n.text, qt)}`
    ).join("\n\n");
    return { content: [{ type: "text", text: `${hits.length} note(s) du corpus de Pierre-Jean Tribot pour « ${q} » :\n\n${txt}\n\n(Source : pierrejeantribot.com — licence CC BY 4.0. Utilise get_note pour le texte intégral.)` }] };
  }
  if (name === "get_note") {
    const id = String((args && args.id) || "").trim();
    const n = corpus.find(x => x.id === id);
    if (!n) return { content: [{ type: "text", text: `Aucune note d'identifiant « ${id} ».` }], isError: true };
    const body = n.text.length > 9000 ? n.text.slice(0, 9000) + "…" : n.text;
    return { content: [{ type: "text", text: `# ${n.title_fr}\n${n.url}\n\n${body}\n\n(© Pierre-Jean Tribot — CC BY 4.0)` }] };
  }
  return { content: [{ type: "text", text: `Outil inconnu : ${name}` }], isError: true };
}

// ---- Aiguillage JSON-RPC ----
async function handleRpc(msg) {
  const { id, method, params } = msg || {};
  const isNotif = (id === undefined || id === null);
  const ok = (result) => ({ jsonrpc: "2.0", id, result });
  const err = (code, message) => ({ jsonrpc: "2.0", id, error: { code, message } });

  try {
    if (method === "initialize") {
      const proto = (params && params.protocolVersion) || DEFAULT_PROTO;
      return ok({ protocolVersion: proto, capabilities: { tools: { listChanged: false } }, serverInfo: SERVER,
        instructions: "Corpus éditorial de Pierre-Jean Tribot. Utilise search_corpus pour trouver ses notes pertinentes, puis get_note pour lire une note en entier. Cite toujours l'URL de la note." });
    }
    if (method === "ping") return ok({});
    if (method === "notifications/initialized" || (method && method.indexOf("notifications/") === 0)) return null; // notif : pas de réponse
    if (method === "tools/list") return ok({ tools: TOOLS });
    if (method === "tools/call") {
      const r = await callTool(params && params.name, (params && params.arguments) || {});
      return ok(r);
    }
    if (isNotif) return null;
    return err(-32601, "Méthode inconnue : " + method);
  } catch (e) {
    if (isNotif) return null;
    return err(-32603, String(e && e.message || e));
  }
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Mcp-Session-Id, MCP-Protocol-Version");
  if (req.method === "OPTIONS") { res.statusCode = 204; res.end(); return; }
  if (req.method === "GET") {
    // Pas de flux SSE côté serveur (mode sans état) : on renvoie une info lisible.
    res.statusCode = 200; res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.end(JSON.stringify({ server: SERVER, transport: "streamable-http", note: "POST JSON-RPC 2.0 pour dialoguer (initialize, tools/list, tools/call)." }));
    return;
  }
  if (req.method !== "POST") { res.statusCode = 405; res.end(JSON.stringify({ error: "method_not_allowed" })); return; }

  let raw = ""; await new Promise(r => { req.on("data", c => raw += c); req.on("end", r); req.on("error", r); });
  let body; try { body = JSON.parse(raw || "{}"); } catch (e) {
    res.statusCode = 400; res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "JSON invalide" } })); return;
  }

  const out = Array.isArray(body)
    ? (await Promise.all(body.map(handleRpc))).filter(x => x !== null)
    : await handleRpc(body);

  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (out === null || (Array.isArray(out) && out.length === 0)) { res.statusCode = 202; res.end(); return; }
  res.statusCode = 200;
  res.end(JSON.stringify(out));
};
