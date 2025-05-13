" Allow nested jinja templates
unlet b:current_syntax
try
  syn include @JINJA syntax/jinja.vim
  syn region yamlTemplate start=+{%+ end=+%}+ contains=@JINJA keepend transparent
  syn region yamlTemplateVar start=+{{+ end=+}}+ oneline contains=@JINJA containedin=yamlFlowString,yamlPlainScalar keepend
catch
endtry
let b:current_syntax = "yaml"

" Redeclare variables for correcting key highlighting
let s:ns_char = '\%([\n\r\uFEFF \t]\@!\p\)'
let s:ns_word_char = '[[:alnum:]_\-]'
let s:ns_uri_char  = '\%(%\x\x\|'.s:ns_word_char.'\|[#/;?:@&=+$,.!~*''()[\]]\)'
let s:ns_tag_char  = '\%(%\x\x\|'.s:ns_word_char.'\|[#/;?:@&=+$.~*''()]\)'
let s:c_indicator      = '[\-?:,[\]{}#&*!|>''"%@`]'
let s:c_flow_indicator = '[,[\]{}]'

let s:ns_anchor_char = substitute(s:ns_char, '\v\C[\zs', '\=s:c_flow_indicator[1:-2]', '')
let s:ns_char_without_c_indicator = substitute(s:ns_char, '\v\C[\zs', '\=s:c_indicator[1:-2]', '')

let s:_collection = '[^\@!\(\%(\\\.\|\[^\\\]]\)\+\)]'
let s:_neg_collection = '[^\(\%(\\\.\|\[^\\\]]\)\+\)]'
function s:SimplifyToAssumeAllPrintable(p)
    return substitute(a:p, '\V\C\\%('.s:_collection.'\\@!\\p\\)', '[^\1]', '')
endfunction
let s:ns_char = s:SimplifyToAssumeAllPrintable(s:ns_char)
let s:ns_anchor_char = s:SimplifyToAssumeAllPrintable(s:ns_anchor_char)
let s:ns_char_without_c_indicator = s:SimplifyToAssumeAllPrintable(s:ns_char_without_c_indicator)

function s:SimplifyAdjacentCollections(p)
    return substitute(a:p, '\V\C'.s:_collection.'\\|'.s:_collection, '[\1\2]', 'g')
endfunction
let s:ns_uri_char = s:SimplifyAdjacentCollections(s:ns_uri_char)
let s:ns_tag_char = s:SimplifyAdjacentCollections(s:ns_tag_char)

let s:c_verbatim_tag = '!<'.s:ns_uri_char.'\+>'
let s:c_named_tag_handle     = '!'.s:ns_word_char.'\+!'
let s:c_secondary_tag_handle = '!!'
let s:c_primary_tag_handle   = '!'
let s:c_tag_handle = '\%('.s:c_named_tag_handle.
            \         '\|'.s:c_secondary_tag_handle.
            \         '\|'.s:c_primary_tag_handle.'\)'
let s:c_ns_shorthand_tag = s:c_tag_handle . s:ns_tag_char.'\+'
let s:c_non_specific_tag = '!'
let s:c_ns_tag_property = s:c_verbatim_tag.
            \        '\|'.s:c_ns_shorthand_tag.
            \        '\|'.s:c_non_specific_tag

let s:c_ns_anchor_name = s:ns_anchor_char.'\+'
let s:c_ns_anchor_property =  '&'.s:c_ns_anchor_name
let s:c_ns_alias_node      = '\*'.s:c_ns_anchor_name
let s:c_ns_properties      = '\%(\%('.s:c_ns_tag_property.'\|'.s:c_ns_anchor_property.'\)\s\+\)\+'

let s:ns_directive_name = s:ns_char.'\+'

let s:ns_local_tag_prefix  = '!'.s:ns_uri_char.'*'
let s:ns_global_tag_prefix = s:ns_tag_char.s:ns_uri_char.'*'
let s:ns_tag_prefix = s:ns_local_tag_prefix.
            \    '\|'.s:ns_global_tag_prefix

let s:ns_plain_safe_out = s:ns_char
let s:ns_plain_safe_in  = '\%('.s:c_flow_indicator.'\@!'.s:ns_char.'\)'

let s:ns_plain_safe_in = substitute(s:ns_plain_safe_in, '\V\C\\%('.s:_collection.'\\@!'.s:_neg_collection.'\\)', '[^\1\2]', '')
let s:ns_plain_safe_in_without_colhash = substitute(s:ns_plain_safe_in, '\V\C'.s:_neg_collection, '[^\1:#]', '')
let s:ns_plain_safe_out_without_colhash = substitute(s:ns_plain_safe_out, '\V\C'.s:_neg_collection, '[^\1:#]', '')

let s:ns_plain_first_in  = '\%('.s:ns_char_without_c_indicator.'\|[?:\-]\%('.s:ns_plain_safe_in.'\)\@=\)'
let s:ns_plain_first_out = '\%('.s:ns_char_without_c_indicator.'\|[?:\-]\%('.s:ns_plain_safe_out.'\)\@=\)'

let s:ns_plain_char_in  = '\%('.s:ns_char.'#\|:'.s:ns_plain_safe_in.'\|'.s:ns_plain_safe_in_without_colhash.'\)'
let s:ns_plain_char_out = '\%('.s:ns_char.'#\|:'.s:ns_plain_safe_out.'\|'.s:ns_plain_safe_out_without_colhash.'\)'

let s:ns_plain_out = s:ns_plain_first_out . s:ns_plain_char_out.'*'
let s:ns_plain_in  = s:ns_plain_first_in  . s:ns_plain_char_in.'*'

" Space must be after colon to be a key
" Remove after
" https://github.com/neovim/neovim/commit/a5d5b9f36b2fca6b1400d73c230b257f53de4ae5
" is merged to a release
syn clear yamlFlowMappingKey
execute 'syn match yamlFlowMappingKey /'.s:ns_plain_in.'\%(\s\+'.s:ns_plain_in.'\)*\ze\s*:\s+/ contained '.
            \'nextgroup=yamlFlowMappingDelimiter skipwhite'

hi link yamlTemplateVar PreProc
hi link yamlMappingKey @property
hi link yamlPlainScalar @string
hi link yamlBlockString @string
hi link yamlBlockCollectionItemStart @punctuation.delimiter
hi link yamlNull @constant.builtin

unlet s:ns_char s:ns_word_char s:ns_uri_char s:ns_tag_char s:c_indicator s:c_flow_indicator
            \ s:ns_anchor_char s:ns_char_without_c_indicator s:_collection s:_neg_collection
            \ s:c_verbatim_tag s:c_named_tag_handle s:c_secondary_tag_handle s:c_primary_tag_handle
            \ s:c_tag_handle s:c_ns_shorthand_tag s:c_non_specific_tag s:c_ns_tag_property
            \ s:c_ns_anchor_name s:c_ns_anchor_property s:c_ns_alias_node s:c_ns_properties
            \ s:ns_directive_name s:ns_local_tag_prefix s:ns_global_tag_prefix s:ns_tag_prefix
            \ s:ns_plain_safe_out s:ns_plain_safe_in s:ns_plain_safe_in_without_colhash s:ns_plain_safe_out_without_colhash
            \ s:ns_plain_first_in s:ns_plain_first_out s:ns_plain_char_in s:ns_plain_char_out s:ns_plain_out s:ns_plain_in
delfunction s:SimplifyAdjacentCollections
delfunction s:SimplifyToAssumeAllPrintable
