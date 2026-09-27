# encoding: utf-8
# Génère carte/graph.json : nœuds (notes, thème) + liens (voisines TF-IDF)
# à partir de l'objet D embarqué dans notes/index.html et des titres de corpus-index.json.
# Usage : ruby scripts/build-graph.rb
require "json"
ROOT = File.expand_path("..", __dir__)
html = File.read(File.join(ROOT, "notes", "index.html"), encoding: "UTF-8")
m = html[/var D = (\{.*?\});/m, 1]
abort "objet D introuvable" unless m
D = JSON.parse(m)
titles = {}
JSON.parse(File.read(File.join(ROOT, "corpus-index.json"), encoding: "UTF-8"))["notes"].each { |n| titles[n["id"]] = n["title_fr"] }

themes = D["themes"] || {}
nb = D["nb"] || {}
deg = Hash.new(0)
seen = {}
links = []
nb.each do |id, arr|
  (arr || []).each do |t|
    next unless themes.key?(t)
    a, b = [id, t].sort
    key = "#{a}|#{b}"
    next if seen[key]
    seen[key] = true
    links << { "source" => a, "target" => b }
    deg[a] += 1; deg[b] += 1
  end
end
nodes = themes.keys.map do |id|
  { "id" => id, "title" => titles[id] || id, "theme" => themes[id], "deg" => deg[id] }
end

graph = { "nodes" => nodes, "links" => links, "labels" => D["labels"], "order" => D["order"] }
Dir.mkdir(File.join(ROOT, "carte")) unless Dir.exist?(File.join(ROOT, "carte"))
File.write(File.join(ROOT, "carte", "graph.json"), JSON.generate(graph))
puts "graph.json : #{nodes.length} nœuds, #{links.length} liens"
