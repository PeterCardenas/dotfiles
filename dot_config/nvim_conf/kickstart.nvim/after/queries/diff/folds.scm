; extends

; Upstream folds (block)/(hunks)/(hunk), but all three only exist inside a
; (block), which the grammar requires a leading "diff --git ..." command line to
; produce. A bare unified diff (`diff -u`, a pasted patch, `git diff` with the
; command line stripped) parses as flat lines under (source) and gets no folds
; at all, so match those runs of sibling lines directly.
; Per-file: the ---/+++ pair plus every hunk that follows it.
(source
  (old_file) @fold
  .
  (new_file) @fold
  .
  [
    (location)
    (context)
    (addition)
    (deletion)
  ]+ @fold)

; Per-hunk: the @@ location plus its change lines.
(source
  (location) @fold
  .
  [
    (context)
    (addition)
    (deletion)
  ]+ @fold)

; A change line whose context is empty (a bare " ") also ends the (block) it was in,
; so the rest of that hunk spills out as flat siblings — the usual shape for a GitHub
; PR diff, where upstream's (block) fold then only covers the header lines. Fold any
; leftover run of change lines that neither pattern above reached.
(source
  [
    (context)
    (addition)
    (deletion)
  ]+ @fold)
