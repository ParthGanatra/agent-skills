" PlanGate — prose-friendly reading for markdown, tuned for the plan review pane.
" Applies to all markdown (the review file is just markdown). Revert: delete this file.
"
" Install: copy into ~/.vim/after/ftplugin/markdown.vim
"          (Neovim: ~/.config/nvim/after/ftplugin/markdown.vim)

" Soft-wrap at word boundaries, indented, so paragraphs read cleanly in a narrow pane.
setlocal wrap linebreak breakindent
" Reclaim width in the split — line numbers/sign column rarely matter in prose.
setlocal nonumber norelativenumber signcolumn=no
" Render markdown formatting (bold/italic/links/code); keep the cursor line raw for editing.
setlocal conceallevel=2 concealcursor=

" PlanGate review-marker navigation:
"   ]q / [q  -> next / prev open question  (> Q:)
"   ]a       -> jump to the next empty answer slot (> A:) and start typing
nnoremap <buffer><silent> ]q :call search('^\s*> Q:', 'W')<CR>
nnoremap <buffer><silent> [q :call search('^\s*> Q:', 'bW')<CR>
nnoremap <buffer><silent><expr> ]a search('^\s*> A:\s*$', 'W') ? 'A ' : ''
