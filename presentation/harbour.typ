#import "@preview/touying:0.7.3": *
#import themes.simple: *
#show: simple-theme.with(aspect-ratio: "16-9", primary: black, header: none, footer-right: none, subslide-preamble: block(below: 24pt, text(36pt, weight: "bold", utils.display-current-heading(level: 2))))
#set text(font: "Arial", size: 23pt)
#set heading(numbering: none)
#set par(leading: 0.65em)
#let print-version = sys.inputs.at("print", default: "false") == "true"
#let still(name) = image("../docs/screenshots/" + name + ".png", height: 245pt)

== Harbour
#text(size: 46pt, weight: "bold")[On-device health support]
#v(0.7em)
A native iPhone prototype for older adults and the people helping them.
#v(1em)
#text(size: 18pt)[CSI4900 · Honours project · November 2026]

== Interfaces
#text(size: 18pt)[Simple mode and caregiver tools share the same saved records.]
#if print-version { still("233-guided-simple-home") }

== Request processing
#v(0.7em)
Speech or text → local model → source checks
#v(0.6em)
Read saved data, or open the existing editor.
#v(0.6em)
Record changes require confirmation.

== App walkthrough
#text(size: 18pt)[Actual native app · fictional saved data · real local chat inference]
#if print-version { still("237-guided-readings") }

== Medication names
#text(size: 18pt)[8,299 English/French entries · Health Canada DPD]
#if print-version { still("244-guided-medicine-confirmation") }

== Visit review
#text(size: 18pt)[Saved demo summary · authored fixture, not a live extraction result]
#if print-version { still("247-guided-visit-review") }

== Text evaluation
#v(0.6em)
#table(columns: (2.4fr, 1fr, 1fr), stroke: none, inset: 8pt,
  [*Check*], [*Alex · 0.5B*], [*Sam · 1.5B*],
  [Correct complete outcome], [14/16], [14/16],
  [Negated requests routed correctly], [0/2], [0/2],
  [Negated writes blocked by validation], [2/2], [2/2],
)
#v(0.3em)
#text(size: 18pt)[153 deterministic core tests pass. This 16-case model subset does not measure speech accuracy or visit-summary quality.]

== Further evaluation
#v(0.7em)
- Usability with older adults and caregivers
- Canadian English and French speech, including medication names
- Negation, timing and follow-ups on unseen visit transcripts
- Latency and memory across real phones

== Sources
#text(size: 20pt)[
Health Canada · Drug Product Database extract, published November 2, 2026

Apple · Speech contextual strings and AnalysisContext documentation

Harbour · Reproducible text probes, native UI tests and source manifests
]
