function ssh_attach -d "ssh and attach to existing tmux session" -a dest
    ssh-et -Y $dest -t "tmux attach; or tmux"
end
