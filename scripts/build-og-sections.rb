# encoding: utf-8
# Cartes Open Graph (1200×630) pour les pages de section → /og/section-<nom>.png
# Même chaîne macOS que build-og.rb : SVG (toile 1200×1200, bande centrée 630)
#   -> qlmanage -> sips (recadrage 1200×630).
require "fileutils"

ROOT = File.expand_path("..", __dir__)
OGDIR = File.join(ROOT, "og")
TMP  = File.join(ROOT, ".ogtmp")
FileUtils.mkdir_p(OGDIR); FileUtils.mkdir_p(TMP)

# nom de fichier => [titre, sous-titre]
SECTIONS = {
  "corpus"    => ["Corpus.",                  "Cartographie d'un corpus organisé et citable"],
  "tableau"   => ["Le tableau d'affichage.",  "Des thèses datées, confrontées au réel"],
  "methode"   => ["Méthode.",                 "L'IA comme outillage du sujet compétent"],
  "recherche" => ["Recherche.",               "Chercher dans le corpus, plein texte"],
  "dossier"   => ["Pierre-Jean Tribot.",      "Historien · éditeur · IA & culture"],
  "dialogue"  => ["Parler avec ma pensée.",   "Un agent qui répond à partir du corpus"]
}

def xml(s); s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;"); end

def svg(title, sub)
  # titre : accent sur le point final si présent
  t = xml(title)
  if t.end_with?(".")
    t = t[0..-2] + %(<tspan fill="#7a3e2a">.</tspan>)
  end
  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200">
    <rect width="1200" height="1200" fill="#f5efe2"/>
    <g transform="translate(0,285)">
      <rect x="0" y="0" width="1200" height="630" fill="#f5efe2"/>
      <rect x="0" y="0" width="1200" height="8" fill="#7a3e2a"/>
      <text x="80" y="112" font-family="Georgia, serif" font-size="25" letter-spacing="3" fill="#7a3e2a">PIERRE-JEAN TRIBOT</text>
      <text x="80" y="330" font-family="Georgia, 'Times New Roman', serif" font-size="66" font-weight="600" fill="#1a1a1a">#{t}</text>
      <text x="80" y="398" font-family="Georgia, serif" font-size="30" fill="#5a5a5a">#{xml(sub)}</text>
      <text x="80" y="562" font-family="Georgia, serif" font-size="25" fill="#5a5a5a">pierrejeantribot.com</text>
    </g>
    </svg>
  SVG
end

count = 0
SECTIONS.each do |name, (title, sub)|
  sp = File.join(TMP, "section-#{name}.svg")
  File.write(sp, svg(title, sub))
  system("qlmanage", "-t", "-s", "1200", "-o", TMP, sp, out: File::NULL, err: File::NULL)
  thumb = File.join(TMP, "section-#{name}.svg.png")
  unless File.exist?(thumb); warn "échec: #{name}"; next; end
  png = File.join(OGDIR, "section-#{name}.png")
  FileUtils.cp(thumb, png)
  system("sips", "-c", "630", "1200", png, out: File::NULL, err: File::NULL)
  count += 1
end

FileUtils.rm_rf(TMP)
puts "cartes OG de section générées : #{count} dans /og/section-*.png"
