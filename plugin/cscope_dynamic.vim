" vim: set foldmethod=marker:
"
" Copyright (c) 2014, Eric Garver
" All rights reserved.
" 
" Redistribution and use in source and binary forms, with or without
" modification, are permitted provided that the following conditions are met: 
" 
" 1. Redistributions of source code must retain the above copyright notice, this
"    list of conditions and the following disclaimer. 
" 2. Redistributions in binary form must reproduce the above copyright notice,
"    this list of conditions and the following disclaimer in the documentation
"    and/or other materials provided with the distribution. 
" 
" THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
" ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
" WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
" DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
" ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
" (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
" LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
" ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
" (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
" SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


"
" Vim Plugin to automatically update cscope when a buffer has been written.
"
if has("cscope")
if exists("g:cscope_dynamic_loaded")
    finish
endif
let g:cscope_dynamic_loaded = 1

" Section: Default variables and Tunables {{{1
"
if exists("g:cscopedb_big_file")
    let s:big_file = g:cscopedb_big_file
else
    let s:big_file = ".cscope.big"
endif
if exists("g:cscopedb_small_file")
    let s:small_file = g:cscopedb_small_file
else
    let s:small_file = ".cscope.small"
endif
if exists("g:cscopedb_auto_init")
    let s:auto_init = g:cscopedb_auto_init
else
    let s:auto_init = 1
endif
if exists("g:cscopedb_extra_files")
    let s:extra_files = g:cscopedb_extra_files
else
    let s:extra_files = ".cscope.extra.files"
endif
if exists("g:cscopedb_src_dirs_file")
    let s:src_dirs_file = g:cscopedb_src_dirs_file
else
    let s:src_dirs_file = ".cscope.dirs.file"
endif
if exists("g:cscopedb_auto_files")
    let s:auto_files = g:cscopedb_auto_files
else
    let s:auto_files = 1
endif
if exists("g:cscopedb_resolve_links")
    let s:resolve_links = g:cscopedb_resolve_links
else
    let s:resolve_links = 1
endif
if exists("g:cscopedb_lock_file")
    let s:lock_file = g:cscopedb_lock_file
else
    let s:lock_file = ".cscopedb.lock"
endif
if exists("g:cscopedb_big_min_interval")
    let s:big_min_interval = g:cscopedb_big_min_interval
else
    let s:big_min_interval = 180
endif

" Section: Internal script variables {{{1
"
let s:big_update = 0
let s:big_last_update = 0
let s:big_init = 0
let s:small_update = 0
let s:small_init = 0
let s:needs_reset = 0
let s:small_file_dict={}
let s:full_update_force = 0

" Section: Script functions {{{1

function! s:runShellCommand(cmd)
    " Use perl if we have it. Using :!<shell command>
    " breaks the tag stack for some reason.
    "
    if has('perl')
        silent execute "perl system('" . a:cmd . "')" | redraw!
    else 
        silent execute "!" . a:cmd | redraw!
    endif
endfunction

" Add the file to the small DB file list. {{{2
" This moves the file to the small cscope DB and triggers an update
" of the necessary databases.
"
function! s:smallListUpdate(file)
    let s:small_update = 1

    " If file moves to small DB then we also do a big DB update so
    " we don't end up with duplicate lookups.
    if s:resolve_links
        let path = fnamemodify(resolve(expand(a:file)), ":p:.")
    else
        let path = fnamemodify(expand(a:file), ":p:.")
    endif
    if !has_key(s:small_file_dict, path)
        let s:small_file_dict[path] = 1
        let s:big_update = 1
        call writefile(keys(s:small_file_dict), expand(s:small_file) . ".files")
    endif
endfunction

" Update any/all of the DBs {{{2
"
function! s:dbUpdate()
    if s:small_update != 1 && s:big_update != 1
        return
    endif

    if filereadable(expand(s:lock_file))
        return
    endif

    " Limit how often a big DB update can occur.
    "
    if s:small_update != 1 && s:big_update == 1
        if localtime() < s:big_last_update + s:big_min_interval
            return
        endif
    endif

    let cmd = ""

    " Touch lock file synchronously
    call s:runShellCommand("touch ".s:lock_file)
    
    " Do small update first. We'll do big update
    " after the small updates are done.
    "
    if s:small_update == 1
        let cmd .= "(cscope -kbR "
        if s:full_update_force
            let cmd .= "-u "
        else 
            let cmd .= "-U "
        endif
        let cmd .= "-i".s:small_file.".files -f".s:small_file
        let cmd .= "; rm ".s:lock_file
        let cmd .= ") &>/dev/null &"

        let s:small_update = 2
    else
        " Build auto file list
        "
        if filereadable(expand(s:src_dirs_file))
            let src_dirs = ""
            for path in readfile(expand(s:src_dirs_file))
                let src_dirs .= " ".path
            endfor
        else 
            let src_dirs = " . "
        endif

        let cmd .= "("
        let cmd .= "set -f;" " turn off sh globbing
        if s:auto_files
            " Do the find command a 'portable' way
            let cmd .= "find ".src_dirs." -name *.c   -or -name *.h -or"
            let cmd .=       " -name *.C   -or -name *.H -or"
            let cmd .=       " -name *.c++ -or -name *.h++ -or"
            let cmd .=       " -name *.cxx -or -name *.hxx -or"
            let cmd .=       " -name *.cpp -or -name *.hpp"
            let cmd .=       " -type f"
        else
            let cmd .= "echo "  " dummy so following cat command does not hang.
        endif

        " trick to combine extra file list below and auto list above
        "
        let cmd .= "| cat - "

        " Append extra file list if present
        "
        if filereadable(expand(s:extra_files))
            let cmd .= s:extra_files
        endif

        " prune entries that are in the small DB
        "
        if !empty(s:small_file_dict)
            let cmd .= " | grep -v -f".s:small_file.".files "
        endif

        let cmd .= "> ".s:big_file.".files"

        " Build the tags
        "
        let cmd .= " && nice cscope -kqbR "
        if s:full_update_force
            let cmd .= "-u "
        else 
            let cmd .= "-U "
        endif
        let cmd .= "-i".s:big_file.".files -f".s:big_file
        let cmd .= "; rm ".s:lock_file
        let cmd .= ") &>/dev/null &"

        let s:big_update = 2
        let s:full_update_force = 0
    endif

    call s:runShellCommand(cmd)

    let s:needs_reset = 1
    if exists("*Cscope_dynamic_update_hook")
        call Cscope_dynamic_update_hook(1)
    endif
endfunction

" Reset/add the cscope DB connection if the database was recently {{{2
" updated/created and the update has finished.
"
function! s:dbReset()
    if !s:needs_reset || filereadable(expand(s:lock_file))
        return
    endif

    if s:small_update == 2
        if !s:small_init
            silent execute "cs add " . s:small_file
            let s:small_init = 1
        else
            silent cs reset
        endif
        let s:small_update = 0
    elseif s:big_update == 2
        if !s:big_init
            silent execute "cs add " . s:big_file
            let s:big_init = 1
        else
            silent cs reset
        endif
        let s:big_update = 0
        let s:big_last_update = localtime()
    endif
    let s:needs_reset = 0

    " Don't call hook if there are small updates left.
    " Big update has backoff delay, so we call hook even if
    " big has an update pending.
    if s:small_update != 1
        if exists("*Cscope_dynamic_update_hook")
            call Cscope_dynamic_update_hook(0)
        endif
    endif
endfunction

function! s:dbTick()
    call s:dbReset()
    call s:dbUpdate()
endfunction

" Do a FULL DB update {{{2
"
function! s:dbFullUpdate()
    let s:big_update = 1
    if !empty(s:small_file_dict)
        let s:small_update = 1
    endif

    call s:dbUpdate()
endfunction

" Enable/init dynamic cscope updates {{{2
"
function! s:init()
    " Blow away cscope connections (allows re-init)
    "
    silent! execute "cs kill " . s:big_file
    silent! execute "cs kill " . s:small_file
    let s:big_init = 0
    let s:big_last_update = 0
    let s:small_init = 0

    " If they DBs exist, then add them before the update.
    if filereadable(expand(s:big_file))
        silent execute "cs add " . s:big_file
        let s:big_init = 1
    endif
    if filereadable(expand(s:small_file))
        silent execute "cs add " . s:small_file
        let s:small_init = 1

        " Seed the cscopedb_small_file_dict dictionary with the file list
        " from the small DB.
        "
        for path in readfile(expand(s:small_file) . ".files")
            let s:small_file_dict[path] = 1
        endfor
    endif

    call s:installAutoCommands()
    call s:dbFullUpdate()
endfunction

" Force full update of DB {{{2
"
function! s:initForce()
    let s:full_update_force = 1
    call s:init()
endfunction

" Section: Autocommands {{{1
"
function! s:installAutoCommands()
    augroup cscopedb_augroup
        au!
        au BufWritePre *.[cChH],*.[cChH]{++,xx,pp} call <SID>smallListUpdate(expand("<afile>"))
        au BufWritePost *.[cChH],*.[cChH]{++,xx,pp} call <SID>dbUpdate()
        au FileChangedShellPost *.[cChH],*.[cChH]{++,xx,pp} call <SID>dbFullUpdate()
        au QuickFixCmdPre,CursorHoldI,CursorHold,WinEnter,CursorMoved * call <SID>dbTick()
    augroup END
endfunction

" Section: Maps {{{1
"
noremap <unique> <Plug>CscopeDBInit :call <SID>initForce()<CR>

" Autoinit: {{{1
"
" If big cscope DB exists then automatically init the plugin.
" Means we launch vim from a location that we've already started using
" the plugin from.
"
if s:auto_init
    if filereadable(expand(s:big_file))
        call s:init()
    endif
endif

endif
