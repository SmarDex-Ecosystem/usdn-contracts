#import "@preview/graceful-genetics:0.2.0": template as base_template

// Customize graceful-genetics template
#let template(
  title: [],
  authors: (),
  abstract: [],
  keywords: (),
  doc,
) = [
  // Configure equation numbering and spacing.
  #set math.equation(numbering: "(1)")
  // Configure appearance of equation references
  #show ref: it => {
    if it.element != none and it.element.func() == math.equation {
      // Override equation references.
      link(
        it.element.location(),
        numbering(
          it.element.numbering,
          ..counter(math.equation).at(it.element.location()),
        ),
      )
    } else {
      // Other references as usual.
      it
    }
  }
  // invoke base template
  #show: base_template.with(
    title: title,
    authors: authors,
    abstract: abstract,
    keywords: keywords,
    make-venue: [],
  )
  // Different style for level 3 headings
  #show heading.where(level: 3): set text(style: "italic", weight: "medium")
  #doc
]
