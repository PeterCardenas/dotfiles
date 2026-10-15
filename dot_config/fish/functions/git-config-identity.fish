function git-config-identity --description 'Configure repository signing from an XDG Git identity' -a identity
    set -l config_home "$HOME/.config"
    if set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"
        set config_home "$XDG_CONFIG_HOME"
    end
    set -l identity_file "$config_home/git/identities/$identity"
    set -l user_email (git config --file "$identity_file" --get user.email)
    set -l signing_key (git config --file "$identity_file" --get user.signingkey)
    if test -z "$user_email"; or test -z "$signing_key"
        print_error "Git identity must define user.email and user.signingkey: $identity_file"
        return 1
    end
    git config --local user.email "$user_email"; or return 1
    git config --local user.signingkey "$signing_key"; or return 1
    git config --local commit.gpgSign true
end
