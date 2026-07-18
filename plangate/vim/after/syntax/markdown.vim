" PlanGate review markers — highlight layered on top of markdown (loads after it).
" > Q: (open question — needs the reviewer) uses the Todo group (attention/highlight);
" > A: (answer) uses the Comment group (dimmed). Linked to standard groups so it adapts
" to ANY colorscheme. Revert: delete this file.
"
" Install: copy into ~/.vim/after/syntax/markdown.vim
"          (Neovim: ~/.config/nvim/after/syntax/markdown.vim)
"
" Want fixed colors instead? Replace the two `highlight default link` lines, e.g.:
"   highlight planReviewQ guifg=#fab387 gui=bold ctermfg=216 cterm=bold
"   highlight planReviewA guifg=#6c7086 gui=italic ctermfg=245 cterm=italic

syntax match planReviewQ /^\s*> Q:.*/ containedin=ALL
syntax match planReviewA /^\s*> A:.*/ containedin=ALL
highlight default link planReviewQ Todo
highlight default link planReviewA Comment
