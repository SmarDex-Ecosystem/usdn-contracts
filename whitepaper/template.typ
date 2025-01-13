#import "@preview/graceful-genetics:0.2.0": template as base_template

// Customize graceful-genetics template
#let template(
  title: [],
  version: [],
  authors: (),
  date: (),
  abstract: [],
  keywords: (),
  doc,
) = [
  #set page(
    footer: context [
      #h(1fr)
      #counter(page).display()
      #h(1fr)
    ],
  )
  // invoke base template
  #show: base_template.with(
    title: title,
    authors: authors,
    abstract: abstract,
    keywords: keywords,
    make-venue: [],
    make-title: (
      title,
      authors,
      abstract,
      keywords,
    ) => {
      set par(spacing: 1em)
      set text(font: "TeX Gyre Heros")

      par(
        justify: false,
        text(24pt, fill: rgb("004b71"), title, weight: "bold"),
      )

      text(
        12pt,
        authors.enumerate().map(((i, author)) => [#author.name~#super[#(i + 1)]]).join(", "),
      )
      parbreak()

      for (i, author) in authors.enumerate() [
        #set text(8pt)
        #super[#(i + 1)]
        #{
          if author.institution != "" {
            [#author.institution ]
          }
        }
        #link("mailto:" + author.mail) \
      ]

      v(8pt)
      set text(10pt)
      set par(justify: true)

      [
        #heading(outlined: false, bookmarked: false)[Abstract]
        #text(font: "TeX Gyre Pagella", abstract)
        #v(3pt)
        *Keywords:* #text(font: "TeX Gyre Pagella", keywords.join("; ")) #h(1fr)
        Version #(version) #(date)
      ]
      v(18pt)
    },
  )
  // Configure equation numbering and spacing.
  #set math.equation(numbering: "(1)")
  // Configure appearance of equation references
  #show ref: it => {
    if it.element != none and it.element.func() == math.equation {
      // Override equation references.
      link(
        it.element.location(),
        text(
          fill: black,
          numbering(
            it.element.numbering,
            ..counter(math.equation).at(it.element.location()),
          ),
        ),
      )
    } else {
      // Other references as usual.
      it
    }
  }
  // Different style for level 3 headings
  #show heading.where(level: 3): set text(style: "italic", weight: "medium")
  // Set heading numbering
  #set heading(numbering: "1.")
  // Links
  #show link: set text(fill: blue.darken(40%))
  // Thin unbreakable space
  #show "_": sym.space.nobreak.narrow
  #show sym.approx: it => it + sym.wj

  // Main body
  #doc

  #bibliography("refs.bib", title: "References", full: true)
]
