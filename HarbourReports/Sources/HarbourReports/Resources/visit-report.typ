#let r = json("report.json")
#let ink = rgb("202c3a")
#let blue = rgb("355acb")
#set document(title: r.title, author: "Harbour")
#set text(font: "Libertinus Serif", size: 11pt, fill: ink, lang: r.language)
#set page(paper: "us-letter", margin: (x: 19mm, top: 18mm, bottom: 19mm),
  footer: context [#set text(size: 9pt, fill: rgb("657080"))
    #line(length: 100%, stroke: 0.4pt + rgb("d8dfe8"))
    #v(3pt)
    #grid(columns: (1fr, auto), [Harbour · #r.generated], counter(page).display("1 / 1", both: true))
  ])
#set par(leading: 0.7em)
#set heading(numbering: none)
#show heading.where(level: 1): it => block(above: 16pt, below: 8pt)[#text(size: 15pt, weight: "bold", fill: blue, it.body)]
#show heading.where(level: 2): it => block(above: 10pt, below: 6pt)[#text(size: 12pt, weight: "bold", it.body)]
#text(size: 10pt, tracking: 2pt, fill: blue)[HARBOUR]
#v(6pt)
#text(size: 29pt, weight: "bold")[#r.title]
#v(7pt)
#text(size: 12pt)[#r.period]
#v(10pt)
#block(fill: rgb("f0f3fa"), inset: 10pt, radius: 5pt, width: 100%)[#text(size: 10pt)[#r.context]]
#for section in r.sections {
  heading(level: 1, section.title)
  if section.items.len() == 0 and section.charts.len() == 0 { text(fill: rgb("657080"), r.empty) }
  for chart in section.charts {
    block(breakable: false)[
      #heading(level: 2, chart.title)
      #image(bytes(chart.svg), format: "svg", width: 100%)
      #text(size: 9pt, fill: rgb("657080"), chart.caption)
    ]
  }
  for item in section.items {
    block(breakable: true, above: 5pt, below: 6pt)[
      #text(weight: "bold", item.title)
      #if item.detail != "" { linebreak(); text(item.detail) }
    ]
  }
}
