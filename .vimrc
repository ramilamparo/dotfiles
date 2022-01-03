" :W to write as sudo
command W :execute ':silent w !sudo tee % > /dev/null' | :edit!

set shiftwidth=4
set tabstop=4
set hlsearch

" Use system clipboard when copy pasting.
set clipboard=unnamedplus

" Keep buffers on memory when not in window. Do not unload inactive buffers.
set hidden

" Keep 1000 items in the history.
set history=1000

" Show the cursor position.
set ruler

" Show incomplete commands.
set showcmd

" Pressing tab in command line mode will show options.
set wildmenu

" The minimum amout of line to show before it scrolls.
set scrolloff=5

" Highlight search matches.
set hlsearch

" Enable incremental searching.
set incsearch

" Ignore cases, and make case sensitive if pattern contains capital letters.
set ignorecase
set smartcase

" Show line number
set number

" Create backup when editing.
" set backup

" Line break whole word instead in a character
set lbr

" Auto indent code.
set ai

" Indent text on brackets.
set si
