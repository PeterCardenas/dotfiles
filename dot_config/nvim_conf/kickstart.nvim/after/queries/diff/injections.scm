; extends

; "New" version: context + addition lines combined
([
  (context)
  (addition)
] @injection.content
  (#diff-lang-inject! @injection.content)
  (#set! injection.combined))

; "Old" version: context + deletion lines combined separately
([
  (context)
  (deletion)
] @injection.content
  (#diff-lang-inject! @injection.content)
  (#set! injection.combined))
