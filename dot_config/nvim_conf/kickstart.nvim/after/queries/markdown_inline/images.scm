; extends

(inline_link
  (link_destination) @image.src
  (#lua-match? @image.src "^https://github%.com/user%-attachments/assets/[a-z0-9%-]+$")) @image
