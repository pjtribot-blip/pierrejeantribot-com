# encoding: utf-8
# Génère une page statique crawlable par note : /notes/<slug>/index.html
# (balises Open Graph / Twitter / JSON-LD propres à la note + redirection JS
#  vers la SPA /notes/#<slug>). Reconstruit aussi sitemap.xml.
# Usage : ruby scripts/build-note-pages.rb   (depuis la racine du dépôt)
require "fileutils"

ROOT   = File.expand_path("..", __dir__)
SRC    = File.join(ROOT, "notes", "index.html")
SITE   = "https://pierrejeantribot.com"
OGIMG  = "#{SITE}/og-notes.png"
html   = File.read(SRC, encoding: "UTF-8")

MOIS = { "janvier"=>1,"février"=>2,"fevrier"=>2,"mars"=>3,"avril"=>4,"mai"=>5,
         "juin"=>6,"juillet"=>7,"août"=>8,"aout"=>8,"septembre"=>9,"octobre"=>10,
         "novembre"=>11,"décembre"=>12,"decembre"=>12 }

def strip(s)
  s = s.gsub(/&nbsp;/, " ").gsub(/&middot;/, "·").gsub(/&amp;/, "&")
       .gsub(/&laquo;/, "«").gsub(/&raquo;/, "»").gsub(/&#8239;/, " ")
       .gsub(%r{<span class="point">\.</span>}, "").gsub(/<[^>]+>/, "")
  s.gsub(/\s+/, " ").strip
end

def esc(s)  # pour attribut HTML
  s.gsub("&", "&amp;").gsub('"', "&quot;").gsub("<", "&lt;").gsub(">", "&gt;")
end

def iso(date_fr)
  return nil unless date_fr
  if (m = date_fr.downcase.match(/(\d{1,2})\s+(\S+)\s+(\d{4})/))
    d, mo, y = m[1].to_i, MOIS[m[2]], m[3].to_i
  elsif (m = date_fr.downcase.match(/(\S+)\s+(\d{4})/))
    d, mo, y = 15, MOIS[m[1]], m[2].to_i
  end
  return nil unless mo
  format("%04d-%02d-%02d", y, mo, d)
end

# Découpe les vignettes d'index
items = html.split('<article class="index-item">').drop(1)
notes = []
items.each do |blk|
  blk = blk.split("</article>").first
  next unless blk
  slug = blk[/class="index-title"[^>]*href="#([^"]+)"/, 1] ||
         blk[/href="#([^"]+)"[^>]*class="index-title"/, 1]
  next unless slug
  a = blk[/class="index-title".*?<\/a>/m] || ""
  tfr = a[/<span data-fr>(.*?)<\/span>\s*<span data-en>/m, 1] || a[/<span data-fr>(.*?)<\/span>/m, 1]
  ten = a[/<span data-en>(.*?)<\/span>\s*<\/a>/m, 1] || a[/<span data-en>(.*?)<\/span>/m, 1]
  rfr = blk[/<p class="resume" data-fr>(.*?)<\/p>/m, 1]
  ren = blk[/<p class="resume" data-en>(.*?)<\/p>/m, 1]
  dfr = blk[/<div class="date">.*?<span data-fr>(.*?)<\/span>/m, 1]
  den = blk[/<div class="date">.*?<span data-en>(.*?)<\/span>/m, 1]
  notes << {
    slug: slug,
    title_fr: strip(tfr || slug), title_en: strip(ten || tfr || slug),
    res_fr: strip(rfr || ""), res_en: strip(ren || rfr || ""),
    date_fr: strip(dfr || ""), date_en: strip(den || dfr || ""),
    iso: iso(strip(dfr || ""))
  }
end

raise "aucune note trouvée" if notes.empty?

def page(n, site, ogimg)
  url  = "#{site}/notes/#{n[:slug]}/"
  desc = n[:res_fr]
  desc = desc[0, 297] + "…" if desc.length > 300
  descen = n[:res_en]
  descen = descen[0, 297] + "…" if descen.length > 300
  jsonld = {
    "@context" => "https://schema.org", "@type" => "Article",
    "headline" => n[:title_fr],
    "description" => desc,
    "inLanguage" => "fr",
    "datePublished" => n[:iso],
    "author" => { "@type" => "Person", "name" => "Pierre-Jean Tribot" },
    "publisher" => { "@type" => "Person", "name" => "Pierre-Jean Tribot" },
    "url" => url,
    "mainEntityOfPage" => url,
    "image" => ogimg,
    "isPartOf" => { "@type" => "Blog", "name" => "Pierre-Jean Tribot — Notes", "url" => "#{site}/notes/" }
  }.reject { |_, v| v.nil? }
  require "json"
  cdate = n[:iso] ? n[:iso].tr("-", "/") : nil          # Google Scholar : YYYY/MM/DD
  cite = +""
  cite << %(<meta name="citation_title" content="#{esc(n[:title_fr])}">\n)
  cite << %(    <meta name="citation_author" content="Pierre-Jean Tribot">\n)
  cite << %(    <meta name="citation_publication_date" content="#{cdate}">\n) if cdate
  cite << %(    <meta name="citation_online_date" content="#{cdate}">\n) if cdate
  cite << %(    <meta name="citation_language" content="fr">\n)
  cite << %(    <meta name="citation_public_url" content="#{url}">\n)
  cite << %(    <meta name="citation_fulltext_world_readable" content="">\n)
  cite << %(    <meta name="DC.title" content="#{esc(n[:title_fr])}">\n)
  cite << %(    <meta name="DC.creator" content="Pierre-Jean Tribot">\n)
  cite << %(    <meta name="DC.date" content="#{n[:iso]}">\n) if n[:iso]
  cite << %(    <meta name="DC.language" content="fr">\n)
  cite << %(    <meta name="DC.publisher" content="Pierre-Jean Tribot">\n)
  cite << %(    <meta name="DC.type" content="Text">\n)
  cite << %(    <meta name="DC.description" content="#{esc(desc)}">)
  <<~HTML
    <!DOCTYPE html>
    <html lang="fr">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>#{esc(n[:title_fr])} — Pierre-Jean Tribot</title>
    <meta name="description" content="#{esc(desc)}">
    <link rel="canonical" href="#{url}">
    <meta name="robots" content="index,follow,max-image-preview:large">
    <meta name="author" content="Pierre-Jean Tribot">
    <meta name="theme-color" content="#f5efe2">
    <meta property="og:type" content="article">
    <meta property="og:site_name" content="Pierre-Jean Tribot">
    <meta property="og:title" content="#{esc(n[:title_fr])}">
    <meta property="og:description" content="#{esc(desc)}">
    <meta property="og:url" content="#{url}">
    <meta property="og:image" content="#{ogimg}">
    <meta property="og:locale" content="fr_FR">
    <meta property="og:locale:alternate" content="en_US">
    #{n[:iso] ? %(<meta property="article:published_time" content="#{n[:iso]}">) : ""}
    <meta property="article:author" content="Pierre-Jean Tribot">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="#{esc(n[:title_fr])}">
    <meta name="twitter:description" content="#{esc(desc)}">
    <meta name="twitter:image" content="#{ogimg}">
    #{cite}
    <link rel="alternate" type="application/rss+xml" title="Pierre-Jean Tribot — Notes (RSS)" href="#{site}/feed.xml">
    <noscript><meta http-equiv="refresh" content="0;url=/notes/#slug-noscript"></noscript>
    <script type="application/ld+json">#{JSON.generate(jsonld)}</script>
    <style>
    :root{--fond:#f5efe2;--texte:#1a1a1a;--mute:#5a5a5a;--accent:#7a3e2a}
    body{margin:0;background:var(--fond);color:var(--texte);font-family:"EB Garamond",Georgia,serif;line-height:1.6}
    main{max-width:620px;margin:0 auto;padding:64px 32px}
    .k{font-family:"JetBrains Mono",monospace;font-size:11px;letter-spacing:.2em;text-transform:uppercase;color:var(--accent)}
    h1{font-size:38px;font-weight:400;letter-spacing:-.02em;line-height:1.1;margin:18px 0 14px}
    p{font-size:18px;color:var(--mute)}
    a.lire{display:inline-block;margin-top:20px;font-family:"JetBrains Mono",monospace;font-size:13px;color:var(--accent);text-decoration:none;border-bottom:1px solid var(--accent);padding-bottom:2px}
    </style>
    </head>
    <body>
    <main>
      <span class="k">Pierre-Jean Tribot · note</span>
      <h1>#{esc(n[:title_fr])}</h1>
      <p>#{esc(n[:res_fr])}</p>
      <a class="lire" href="/notes/##{n[:slug]}">lire la note →</a>
    </main>
    <script>
    (function(){
      var slug=#{n[:slug].to_json};
      var p=new URLSearchParams(location.search);
      var en=(p.get('lang')==='en')||(location.hash==='#en');
      location.replace('/notes/#'+slug+(en?'-en':''));
    })();
    </script>
    </body>
    </html>
  HTML
end

# Écrit les pages
count = 0
notes.each do |n|
  dir = File.join(ROOT, "notes", n[:slug])
  FileUtils.mkdir_p(dir)
  html_out = page(n, SITE, OGIMG).gsub("/notes/#slug-noscript", "/notes/##{n[:slug]}")
  File.write(File.join(dir, "index.html"), html_out)
  count += 1
end

# Reconstruit sitemap.xml : pages fixes + une entrée par note
today = Time.now.strftime("%Y-%m-%d")
fixed = [
  ["#{SITE}/",                       "monthly", "1.0"],
  ["#{SITE}/notes/",                 "weekly",  "0.9"],
  ["#{SITE}/corpus/",                "weekly",  "0.8"],
  ["#{SITE}/tableau/",               "monthly", "0.8"],
  ["#{SITE}/methode/",               "monthly", "0.7"],
  ["#{SITE}/glossaire.html",         "monthly", "0.6"],
  ["#{SITE}/confidentialite.html",   "yearly",  "0.2"]
]
sm = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
sm << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
fixed.each do |loc, cf, pr|
  sm << "  <url>\n    <loc>#{loc}</loc>\n    <lastmod>#{today}</lastmod>\n    <changefreq>#{cf}</changefreq>\n    <priority>#{pr}</priority>\n  </url>\n"
end
notes.each do |n|
  sm << "  <url>\n    <loc>#{SITE}/notes/#{n[:slug]}/</loc>\n"
  sm << "    <lastmod>#{n[:iso] || today}</lastmod>\n"
  sm << "    <changefreq>monthly</changefreq>\n    <priority>0.6</priority>\n  </url>\n"
end
sm << "</urlset>\n"
File.write(File.join(ROOT, "sitemap.xml"), sm)

puts "pages notes générées : #{count}"
puts "sitemap.xml : #{fixed.length} pages fixes + #{notes.length} notes"
