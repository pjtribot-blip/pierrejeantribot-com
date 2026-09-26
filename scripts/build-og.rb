# encoding: utf-8
# Génère une image Open Graph (1200×630) par note dans /og/<slug>.png,
# aux couleurs du site, avec le titre de la note.
# Chaîne macOS sans dépendance : SVG (toile 1200×1200, bande centrée 630)
#   -> qlmanage (rendu) -> sips (recadrage centré 1200×630).
# Usage : ruby scripts/build-og.rb   (depuis la racine du dépôt)
require "json"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
OGDIR = File.join(ROOT, "og")
TMP  = File.join(ROOT, ".ogtmp")
FileUtils.mkdir_p(OGDIR); FileUtils.mkdir_p(TMP)

notes = JSON.parse(File.read(File.join(ROOT, "corpus-index.json"), encoding: "UTF-8"))["notes"]

def xml(s); s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;"); end

# Enveloppe gloutonne : renvoie [lignes] pour une taille de police donnée.
# Georgia gras ≈ 0.56em d'avance moyenne ; largeur utile ~1000px (marge 80 + garde).
def wrap(title, size)
  cpl = (1000.0 / (0.56 * size)).floor
  words = title.split(/\s+/)
  lines = []; cur = ""
  words.each do |w|
    trial = cur.empty? ? w : cur + " " + w
    if trial.length <= cpl then cur = trial
    else lines << cur unless cur.empty?; cur = w end
  end
  lines << cur unless cur.empty?
  lines
end

def layout(title)
  [72, 60, 52, 46, 40].each do |size|
    lines = wrap(title, size)
    max = size >= 60 ? 2 : 3
    return [size, lines] if lines.length <= max
  end
  [40, wrap(title, 40)[0, 4]]
end

def svg(title)
  size, lines = layout(title)
  lh = (size * 1.12).round
  center = 340                            # centre vertical du bloc titre dans la bande
  first = center - (lines.length - 1) * lh / 2.0 + size * 0.34
  tspans = lines.each_with_index.map do |ln, i|
    y = (first + i * lh).round
    last = (i == lines.length - 1)
    txt = xml(ln)
    txt += %(<tspan fill="#7a3e2a">.</tspan>) if last
    %(<text x="80" y="#{y}" font-family="Georgia, 'Times New Roman', serif" font-size="#{size}" font-weight="600" fill="#1a1a1a">#{txt}</text>)
  end.join("\n  ")
  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1200" viewBox="0 0 1200 1200">
    <rect width="1200" height="1200" fill="#f5efe2"/>
    <g transform="translate(0,285)">
      <rect x="0" y="0" width="1200" height="630" fill="#f5efe2"/>
      <rect x="0" y="0" width="1200" height="8" fill="#7a3e2a"/>
      <text x="80" y="112" font-family="Georgia, serif" font-size="25" letter-spacing="3" fill="#7a3e2a">PIERRE-JEAN TRIBOT &#183; NOTE</text>
      #{tspans}
      <text x="80" y="562" font-family="Georgia, serif" font-size="25" fill="#5a5a5a">pierrejeantribot.com</text>
    </g>
    </svg>
  SVG
end

count = 0
notes.each do |n|
  slug = n["id"]; title = n["title_fr"].to_s
  sp = File.join(TMP, "#{slug}.svg")
  File.write(sp, svg(title))
  system("qlmanage", "-t", "-s", "1200", "-o", TMP, sp, out: File::NULL, err: File::NULL)
  thumb = File.join(TMP, "#{slug}.svg.png")
  unless File.exist?(thumb)
    warn "échec qlmanage: #{slug}"; next
  end
  png = File.join(OGDIR, "#{slug}.png")
  FileUtils.cp(thumb, png)
  system("sips", "-c", "630", "1200", png, out: File::NULL, err: File::NULL)
  count += 1
end

FileUtils.rm_rf(TMP)
puts "images OG générées : #{count} dans /og/"
