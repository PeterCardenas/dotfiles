; extends

; Remove conceal from other link types
(full_reference_link
  [
    "["
    "]"
    (link_label)
  ] @noconceal)

(collapsed_reference_link
  [
    "["
    "]"
  ] @noconceal)

(shortcut_link
  [
    "["
    "]"
  ] @noconceal)

(full_reference_link
  (link_text) @markup.shortcut_link
  (#set! priority 110))

(shortcut_link
  (link_text) @markup.shortcut_link
  (#set! priority 110))
