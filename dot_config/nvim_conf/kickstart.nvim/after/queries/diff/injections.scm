; extends

; "New" version: context + addition lines combined
(block
  (old_file
    (filename) @_injection.filename.old)
  (new_file
    (filename) @_injection.filename.new)
  (hunks
    (hunk
      (changes
        [
          (context)
          (addition)
        ] @injection.content)))
  (#diff-lang-inject! @injection.content @_injection.filename.new @_injection.filename.old)
  (#set! injection.combined))

; "Old" version: context + deletion lines combined separately
(block
  (old_file
    (filename) @_injection.filename.old)
  (new_file
    (filename) @_injection.filename.new)
  (hunks
    (hunk
      (changes
        [
          (context)
          (deletion)
        ] @injection.content)))
  (#diff-lang-inject! @injection.content @_injection.filename.new @_injection.filename.old)
  (#set! injection.combined))
