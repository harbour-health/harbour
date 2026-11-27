#let r = json("report.json")
#let ink = rgb("181818")
#let muted = rgb("606060")
#let blue = rgb("365dce")
#set document(title: r.title, author: "Harbour")
#set text(font: "Lato", size: 10.5pt, fill: ink, lang: r.language)
#set page(paper: "us-letter", margin: (x: 20mm, top: 18mm, bottom: 20mm),
  header: context if counter(page).get().first() > 1 {
    set text(size: 9pt, fill: muted)
    grid(columns: (1fr, auto), [Harbour], r.title)
  },
  footer: context [
    #line(length: 100%, stroke: 0.5pt + rgb("e5e5e5"))
    #v(5pt)
    #set text(size: 9pt, fill: muted)
    #grid(columns: (1fr, auto), [Harbour · #r.generated], counter(page).display("1 / 1", both: true))
  ])
#set par(leading: 0.65em, spacing: 8pt)
#set heading(numbering: none)
#show heading.where(level: 1): it => block(above: 16pt, below: 8pt, sticky: true)[
  #stack(dir: ttb, spacing: 6pt,
    text(size: 16pt, weight: "bold", it.body),
    line(length: 100%, stroke: 0.5pt + rgb("e5e5e5")))
]
#show heading.where(level: 2): it => block(above: 10pt, below: 8pt)[#text(size: 11pt, weight: "bold", it.body)]
#let mark = bytes("<svg xmlns='http://www.w3.org/2000/svg' width='28' height='28' viewBox='0 0 28 28'><g fill='#365dce' transform='rotate(-12 14 14)'><rect x='3' y='3' width='9' height='9' rx='2.5'/><rect x='16' y='3' width='9' height='9' rx='2.5'/><rect x='3' y='16' width='9' height='9' rx='2.5'/><rect x='16' y='16' width='9' height='9' rx='2.5'/></g></svg>")
#grid(columns: (24pt, 1fr), column-gutter: 7pt, align: horizon,
  image(mark, format: "svg", width: 24pt), text(size: 13pt, weight: "bold")[Harbour])
#v(18pt)
#text(size: 27pt, weight: "bold")[#r.title]
#v(7pt)
#text(size: 11pt, fill: muted)[#r.period]
#v(10pt)
#text(size: 9.5pt, fill: muted)[#r.context]
#for section in r.sections {
  heading(level: 1, section.title)
  if section.items.len() == 0 and section.charts.len() == 0 { text(fill: muted, r.empty) }
  for chart in section.charts {
    block(breakable: false, below: 12pt)[
      #heading(level: 2, chart.title)
      #block(fill: rgb("f5f5f5"), inset: 6pt, radius: 12pt, width: 100%)[#image(bytes(chart.svg), format: "svg", width: 100%)]
      #v(5pt)
      #text(size: 9pt, fill: muted, chart.caption)
    ]
  }
  for item in section.items {
    block(breakable: true, above: 6pt, below: 8pt)[
      #text(weight: "bold", item.title)
      #if item.detail != "" { linebreak(); text(fill: muted, item.detail) }
    ]
  }
}
