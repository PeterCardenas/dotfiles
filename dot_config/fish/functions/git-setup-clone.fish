function git-setup-clone --description 'Apply the commit identity and author name to the current clone' -a identity
    git-config-identity "$identity"; or return 1
    git config --local user.name "Peter Cardenas"
end
