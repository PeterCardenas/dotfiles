function __fish_is_token_nth
  set cmd (commandline -pc)
  set token_str (string replace -r -a '(^|\-).+?\s+' '' -- $cmd)
  set token_str (string replace -r -a '\s+' ' ' -- $token_str)
  set tokens (string split " " $token_str)
  if [ (count $tokens) -eq $argv[1] ]
    return 0
  end
  return 1
end

function __fish_is_token_ge_nth
  set cmd (commandline -pc)
  set token_str (string replace -r -a '(^|\-).+?\s+' '' -- $cmd)
  set token_str (string replace -r -a '\s+' ' ' -- $token_str)
  set tokens (string split " " $token_str)
  if test (count $tokens) -ge $argv[1]
    return 0
  end
  return 1
end
