function __fish_is_token_eq_nth
  set tokens (commandline -poc)
  set token_str (string replace -ra '(^|\-).+?\s+' '' -- $tokens)
  set token_str (string replace -ra '\s+' ' ' -- $token_str)
  set tokens (string split " " "$token_str")
  if [ (count $tokens) -eq $argv[1] ]
    return 0
  end
  return 1
end

function __fish_is_token_ge_nth
  set tokens (commandline -poc)
  if test (count $tokens) -ge $argv[1]
    return 0
  end
  return 1
end
