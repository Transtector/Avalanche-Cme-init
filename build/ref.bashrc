# ~/.bashrc: executed by bash(1) for non-login shells.

# colors
red='\[\e[0;31m\]'
green='\[\e[0;32m\]'
cyan='\[\e[0;36m\]'
yellow='\[\e[1;33m\]'
purple='\[\e[0;35m\]'
NC='\[\e[0m\]' # no color - reset
 
PS1="${green}\u${NC}@${yellow}\h${NC}[${purple}\w${NC}:${red}\!${NC}] \$ "

