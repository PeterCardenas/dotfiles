; extends

; Inject language into diff hunks based on the filename in the diff header
([
  (context)
  (deletion)
  (addition)
] @injection.content
  (#diff-lang-inject! @injection.content)
  (#offset! @injection.content 0 1 0 0))
