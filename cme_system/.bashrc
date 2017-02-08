# ~/.bashrc: executed by bash(1) for non-login shells.

# colors
red='\[\e[0;31m\]'
green='\[\e[0;32m\]'
cyan='\[\e[0;36m\]'
yellow='\[\e[1;33m\]'
purple='\[\e[0;35m\]'
NC='\[\e[0m\]' # no color - reset
bold=`tput bold`
normal=`tput sgr0`
 
PS1="${debian_chroot:+($debian_chroot)}${green}\u${NC}@${yellow}\h${NC}[${purple}\w${NC}:${red}\!${NC}] \$ "
 
# Uncomment the following lines to make `ls' be colorized:
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls='ls $LS_OPTIONS'

