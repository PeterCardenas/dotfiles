; extends

; Remove conceal from other link types
(full_reference_link
  [
    "["
    "]"
    (link_label)
  ] @markup.link
  (#set! priority 105)
  (#unset! conceal))

(collapsed_reference_link
  [
    "["
    "]"
  ] @markup.link
  (#set! priority 105)
  (#unset! conceal))

(shortcut_link
  [
    "["
    "]"
  ] @markup.link
  (#set! priority 105)
  (#unset! conceal))
