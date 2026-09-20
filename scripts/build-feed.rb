#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
#
# build-feed.rb — régénère feed.xml (RSS) à partir de notes/index.html.
# Zéro dépendance (Ruby standard). Lancé automatiquement par GitHub Actions
# à chaque push touchant notes/index.html. Sortie déterministe (pas de
# commit parasite si le contenu n'a pas changé).
#
# Usage : ruby scripts/build-feed.rb [notes/index.html] [feed.xml]

require "cgi"
require "time"

SITE      = "https://pierrejeantribot.com"
NOTES_URL = "#{SITE}/notes/"
FEED_URL  = "#{SITE}/feed.xml"
TITLE     = "Pierre-Jean Tribot — Notes"
DESC      = "Notes analytiques de Pierre-Jean Tribot sur l'intelligence artificielle et ses conséquences dans la culture, l'éducation et les institutions."
EDITOR    = "pjtribot@crescendo-magazine.be (Pierre-Jean Tribot)"
AUTHOR    = "Pierre-Jean Tribot"

src  = ARGV[0] || "notes/index.html"
dest = ARGV[1] || "feed.xml"
html = File.read(src, encoding: "UTF-8")

MOIS = {
  "janvier"=>1,"février"=>2,"fevrier"=>2,"mars"=>3,"avril"=>4,"mai"=>5,"juin"=>6,
  "juillet"=>7,"août"=>8,"aout"=>8,"septembre"=>9,"octobre"=>10,"novembre"=>11,
  "décembre"=>12,"decembre"=>12
}

NAMED = {
  "&nbsp;"=>" ","&middot;"=>"·","&mdash;"=>"—","&ndash;"=>"–","&laquo;"=>"«",
  "&raquo;"=>"»","&rsquo;"=>"’","&lsquo;"=>"‘","&ldquo;"=>"“","&rdquo;"=>"”",
  "&hellip;"=>"…","&uarr;"=>"↑","&rarr;"=>"→","&rsaquo;"=>"›","&#9656;"=>"▸",
  "&eacute;"=>"é","&egrave;"=>"è","&agrave;"=>"à","&ccedil;"=>"ç","&euro;"=>"€","&oelig;"=>"œ",
  "&ecirc;"=>"ê","&icirc;"=>"î","&ocirc;"=>"ô","&ucirc;"=>"û","&acirc;"=>"â","&ugrave;"=>"ù",
  "&euml;"=>"ë","&iuml;"=>"ï","&uuml;"=>"ü","&ouml;"=>"ö","&auml;"=>"ä","&ntilde;"=>"ñ",
  "&Eacute;"=>"É","&Egrave;"=>"È","&Agrave;"=>"À","&Ccedil;"=>"Ç","&Ecirc;"=>"Ê","&Ocirc;"=>"Ô",
  "&Acirc;"=>"Â","&Icirc;"=>"Î","&Ucirc;"=>"Û","&AElig;"=>"Æ","&aelig;"=>"æ","&times;"=>"×"
}
def decode(s)
  NAMED.each { |k, v| s = s.gsub(k, v) }
  CGI.unescapeHTML(s)
end
def strip_tags(s) ; s.gsub(/<[^>]+>/, "") ; end
def clean(s) ; decode(strip_tags(s)).gsub(/\s+/, " ").strip ; end
def strip_point(s) ; s.sub(/<span class="point">\.<\/span>/, "") ; end
def xesc(s) ; s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;") ; end
def cdata(s) ; "<![CDATA[" + s.gsub("]]>", "]]&gt;") + "]]>" ; end

def parse_date(str, order)
  if (m = str.match(/(\d{1,2})\s+(\S+)\s+(\d{4})/))
    day = m[1].to_i; mon = MOIS[m[2].downcase] || 1; year = m[3].to_i
  elsif (m = str.match(/(\S+)\s+(\d{4})/)) && MOIS[m[1].downcase]
    day = 15; mon = MOIS[m[1].downcase]; year = m[2].to_i
  else
    return Time.new(2000, 1, 1, 12, 0, 0, "+02:00")
  end
  Time.new(year, mon, day, 12, 0, 0, "+02:00") - (order * 60)
end

# Corps FR d'une note (paragraphes + intertitres), en HTML, dans l'ordre.
def fr_body(article_inner)
  out = []
  article_inner.scan(/<(p|h3)\b([^>]*)>(.*?)<\/\1>/m) do |tag, attrs, inner|
    if tag == "p"
      next unless attrs =~ /\bdata-fr\b/
      body = decode(inner).gsub(/\s+/, " ").strip
      out << "<p>#{body}</p>" unless body.empty?
    else
      next if attrs =~ /\bdata-en\b/ # variante EN autonome
      txt = if attrs =~ /\bdata-fr\b/
              inner
            else
              (inner[/<span data-fr>(.*?)<\/span>/m, 1] || inner)
            end
      h = decode(strip_point(txt)).gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip
      out << "<h3>#{h}</h3>" unless h.empty?
    end
  end
  out.join("\n")
end

# Corps de chaque note par id
bodies = {}
html.scan(/<article class="texte" id="([^"]+)">(.*?)<\/article>/m).each do |(id, inner)|
  bodies[id] = fr_body(inner)
end

items = []
html.scan(/<article class="index-item">(.*?)<\/article>/m).each_with_index do |(block), idx|
  href = block[/<a\s+href="#([^"]+)"\s+class="index-title"/, 1]
  next unless href
  tblock = block[/class="index-title">(.*?)<\/a>/m, 1] || ""
  fr = (tblock[/<span data-fr>(.*?)<\/span>\s*<span data-en>/m, 1] ||
        tblock[/<span data-fr>(.*?)<\/span>/m, 1] || "")
  title = clean(strip_point(fr))
  resume = clean(block[/<p class="resume" data-fr>(.*?)<\/p>/m, 1] || "")
  date = clean(block[/<div class="date">.*?<span data-fr>(.*?)<\/span>/m, 1] || "")
  items << {
    title: title,
    link: "#{NOTES_URL}##{href}",
    date: parse_date(date, idx),
    desc: resume,
    content: bodies[href] || "<p>#{xesc(resume)}</p>"
  }
end

# Les vignettes d'index sont déjà en ordre chronologique décroissant (ordre du site).
# On force les pubDate à décroître strictement dans cet ordre, pour que les lecteurs
# RSS respectent l'ordre du site même quand une note n'a qu'un mois (jour ambigu).
prev = nil
items.each do |it|
  it[:date] = prev - 60 if prev && it[:date] >= prev
  prev = it[:date]
end

build_date = items.first ? items.first[:date] : Time.new(2026, 1, 1, 12, 0, 0, "+02:00")

xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
xml << %(<rss version="2.0"\n  xmlns:content="http://purl.org/rss/1.0/modules/content/"\n  xmlns:atom="http://www.w3.org/2005/Atom"\n  xmlns:dc="http://purl.org/dc/elements/1.1/">\n)
xml << %(  <channel>\n)
xml << %(    <title>#{xesc(TITLE)}</title>\n)
xml << %(    <link>#{NOTES_URL}</link>\n)
xml << %(    <atom:link href="#{FEED_URL}" rel="self" type="application/rss+xml" />\n)
xml << %(    <description>#{xesc(DESC)}</description>\n)
xml << %(    <language>fr</language>\n)
xml << %(    <copyright>#{xesc(AUTHOR)}</copyright>\n)
xml << %(    <managingEditor>#{xesc(EDITOR)}</managingEditor>\n)
xml << %(    <webMaster>#{xesc(EDITOR)}</webMaster>\n)
xml << %(    <pubDate>#{build_date.rfc822}</pubDate>\n)
xml << %(    <lastBuildDate>#{build_date.rfc822}</lastBuildDate>\n)
xml << %(    <ttl>1440</ttl>\n)
items.each do |it|
  xml << %(    <item>\n)
  xml << %(      <title>#{xesc(it[:title])}</title>\n)
  xml << %(      <link>#{xesc(it[:link])}</link>\n)
  xml << %(      <guid isPermaLink="true">#{xesc(it[:link])}</guid>\n)
  xml << %(      <pubDate>#{it[:date].rfc822}</pubDate>\n)
  xml << %(      <dc:creator>#{xesc(AUTHOR)}</dc:creator>\n)
  xml << %(      <description>#{cdata(it[:desc])}</description>\n)
  xml << %(      <content:encoded>#{cdata(it[:content])}</content:encoded>\n)
  xml << %(    </item>\n)
end
xml << %(  </channel>\n)
xml << %(</rss>\n)

File.write(dest, xml)
warn "feed.xml : #{items.size} notes → #{dest}"
