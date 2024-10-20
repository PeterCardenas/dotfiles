" Allow nested jinja templates
unlet b:current_syntax
try
  syn include @JINJA syntax/jinja.vim
  syn region yamlTemplate start=+{%+ end=+%}+ oneline contains=@JINJA
  syn region yamlTemplateVar start=+{{+ end=+}}+ oneline contains=@JINJA
catch
endtry
let b:current_syntax = "yaml"

hi link yamlTemplateVar PreProc
hi link yamlMappingKey @property
