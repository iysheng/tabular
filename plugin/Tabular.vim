" Tabular:     Align columnar data using regex-designated column boundaries
" Maintainer:  Matthew Wozniski (godlygeek@gmail.com)
" Date:        Thu, 03 May 2012 20:49:32 -0400
" Version:     1.0
"
" Long Description:
" Sometimes, it's useful to line up text.  Naturally, it's nicer to have the
" computer do this for you, since aligning things by hand quickly becomes
" unpleasant.  While there are other plugins for aligning text, the ones I've
" tried are either impossibly difficult to understand and use, or too simplistic
" to handle complicated tasks.  This plugin aims to make the easy things easy
" and the hard things possible, without providing an unnecessarily obtuse
" interface.  It's still a work in progress, and criticisms are welcome.
"
" License:
" Copyright (c) 2012, Matthew J. Wozniski
" All rights reserved.
"
" Redistribution and use in source and binary forms, with or without
" modification, are permitted provided that the following conditions are met:
"     * Redistributions of source code must retain the above copyright notice,
"       this list of conditions and the following disclaimer.
"     * Redistributions in binary form must reproduce the above copyright
"       notice, this list of conditions and the following disclaimer in the
"       documentation and/or other materials provided with the distribution.
"     * The names of the contributors may not be used to endorse or promote
"       products derived from this software without specific prior written
"       permission.
"
" THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ``AS IS'' AND ANY EXPRESS
" OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
" OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
" NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY DIRECT, INDIRECT,
" INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
" LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
" OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
" LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
" NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
" EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

" Abort if running in vi-compatible mode or the user doesn't want us.
if &cp || exists('g:tabular_loaded')
  if &cp && &verbose
    echo "Not loading Tabular in compatible mode."
  endif
  finish
endif

let g:tabular_loaded = 1

" Stupid vimscript crap                                                   {{{1
let s:savecpo = &cpo
set cpo&vim

" Private Things                                                          {{{1

" Dictionary of command name to command
" 定义了一个字典
let s:TabularCommands = {}

" Generate tab completion list for :Tabularize                            {{{2
" Return a list of commands that match the command line typed so far.
" NOTE: Tries to handle commands with spaces in the name, but Vim doesn't seem
"       to handle that terribly well... maybe I should give up on that.
" 返回一个匹配到 command line 的 commands 的 list，
function! s:CompleteTabularizeCommand(argstart, cmdline, cursorpos)
  let names = keys(s:TabularCommands)
" b 表示当前缓冲区, 如果在当前缓冲区定义了新的而 TabularCommand
" 那么也要和这些 command 进行比对
  if exists("b:TabularCommands")
    let names += keys(b:TabularCommands)
  endif

  " a 表示函数参数
  " 贪婪匹配开头的所有空格,匹配 1 个以上非空格的内容，然后再贪婪匹配所有的空格
  " 将上述格式的内容全部删除？？？
  let cmdstart = substitute(a:cmdline, '^\s*\S\+\s*', '', '')

  " 从 names 中逐个过滤 cmd
  " =~# 检查是否匹配右侧的表达式，匹配大小写
  " ^ 表示开头
  " \V 表示非常 nomagic
  " 将 cmdstart 中的 \ 符号追加一个反斜杠 \, 即 \ -> \\
  " 过滤出来符合 expr2 的内容
  " filter({expr1}, {expr2})
  return filter(names, 'v:val =~# ''^\V'' . escape(cmdstart, ''\'')')
endfunction

" Choose the proper command map from the given command line               {{{2
" Returns [ command map, command line with leading <buffer> removed ]
function! s:ChooseCommandMap(commandline)
  " 获取当前文件全局变量 TabularCommands
  let map = s:TabularCommands
  " 获取传递的形参
  let cmd = a:commandline

  " 如果 cmd 是以 buffer 加空格开头的
  " =~# 表示判断是否可以匹配右侧的表达式，匹配大小写
  if cmd =~# '^<buffer>\s\+'
    " 如果当前 buffer 没有定义 TabularCommands 变量,那么定义这个变量为字典并且为空
    if !exists('b:TabularCommands')
      let b:TabularCommands = {}
    endif
    let map = b:TabularCommands
    " 删除 buffer 开头后面紧跟的所有空格和 tab 符号
    let cmd = substitute(cmd, '^<buffer>\s\+', '', '')
  endif

  " 返回这个 map 和 cmd
  return [ map, cmd ]
endfunction

" Parse '/pattern/format' into separate pattern and format parts.         {{{2
" If parsing fails, return [ '', '' ]
function! s:ParsePattern(string)
  if a:string[0] != '/'
    return ['','']
  endif

  let pat = '\\\@<!\%(\\\\\)\{-}\zs/' . tabular#ElementFormatPattern() . '*$'
  let format = matchstr(a:string[1:-1], pat)
  if !empty(format)
    let format = format[1 : -1]
    let pattern = a:string[1 : -len(format) - 2]
  else
    let pattern = a:string[1 : -1]
  endif

  return [pattern, format]
endfunction

" Split apart a list of | separated expressions.                          {{{2
function! s:SplitCommands(string)
  if a:string =~ '^\s*$'
    return []
  endif

  let end = match(a:string, "[\"'|]")

  " Loop until we find a delimiting | or end-of-string
  while end != -1 && (a:string[end] != '|' || a:string[end+1] == '|')
    if a:string[end] == "'"
      let end = match(a:string, "'", end+1) + 1
      if end == 0
        throw "No matching end single quote"
      endif
    elseif a:string[end] == '"'
      " Find a " preceded by an even number of \ (or 0)
      let pattern = '\%(\\\@<!\%(\\\\\)*\)\@<="'
      let end = matchend(a:string, pattern, end+1) + 1
      if end == 0
        throw "No matching end double quote"
      endif
    else " Found ||
      let end += 2
    endif

    let end = match(a:string, "[\"'|]", end)
  endwhile

  if end == 0 || a:string[0 : end - (end > 0)] =~ '^\s*$'
    throw "Empty element"
  endif

  if end == -1
    let rv = [ a:string ]
  else
    let rv = [ a:string[0 : end-1] ] + s:SplitCommands(a:string[end+1 : -1])
  endif

  return rv
endfunction

" Public Things                                                           {{{1

" Command associating a command name with a simple pattern command        {{{2
" AddTabularPattern[!] [<buffer>] name /pattern[/format]
"
" If <buffer> is provided, the command will only be available in the current
" buffer, and will be used instead of any global command with the same name.
"
" If a command with the same name and scope already exists, it is an error,
" unless the ! is provided, in which case the existing command will be
" replaced.
"
" pattern is a regex describing the delimiter to be used.
"
" format describes the format pattern to be used.  The default will be used if
" none is provided.
com! -nargs=+ -bang AddTabularPattern
   \ call AddTabularPattern(<q-args>, <bang>0)

function! AddTabularPattern(command, force)
  try
    let [ commandmap, rest ] = s:ChooseCommandMap(a:command)

    let name = matchstr(rest, '.\{-}\ze\s*/')
    let pattern = substitute(rest, '.\{-}\s*\ze/', '', '')

    let [ pattern, format ] = s:ParsePattern(pattern)

    if empty(name) || empty(pattern)
      throw "Invalid arguments!"
    endif

    if !a:force && has_key(commandmap, name)
      throw string(name) . " is already defined, use ! to overwrite."
    endif

    let command = "tabular#TabularizeStrings(a:lines, " . string(pattern)

    if !empty(format)
      let command .=  ", " . string(format)
    endif

    let command .= ")"

    let commandmap[name] = { 'pattern' : pattern, 'commands' : [ command ] }
  catch
    echohl ErrorMsg
    echomsg "AddTabularPattern: " . v:exception
    echohl None
  endtry
endfunction

" Command associating a command name with a pipeline of functions         {{{2
" AddTabularPipeline[!] [<buffer>] name /pattern/ func [ | func2 [ | func3 ] ]
"
" If <buffer> is provided, the command will only be available in the current
" buffer, and will be used instead of any global command with the same name.
"
" If a command with the same name and scope already exists, it is an error,
" unless the ! is provided, in which case the existing command will be
" replaced.
"
" pattern is a regex that will be used to determine which lines will be
" filtered.  If the cursor line doesn't match the pattern, using the command
" will be a no-op, otherwise the cursor and all contiguous lines matching the
" pattern will be filtered.
"
" Each 'func' argument represents a function to be called.  This function
" will have access to a:lines, a List containing one String per line being
" filtered.
" 这个函数将会访问 a:lines, 一个由每一行的 string 构成的 list
com! -nargs=+ -bang AddTabularPipeline
   \ call AddTabularPipeline(<q-args>, <bang>0)

" command: multiple_spaces
" force: / / map(a:lines, "substitute(v:val, '  *', '  ', 'g')") | \
" tabular#TabularizeStrings(a:lines, '  ', 'l0')
function! AddTabularPipeline(command, force)
  try
    let [ commandmap, rest ] = s:ChooseCommandMap(a:command)

    let name = matchstr(rest, '.\{-}\ze\s*/')
    let pattern = substitute(rest, '.\{-}\s*\ze/', '', '')

    let commands = matchstr(pattern, '^/.\{-}\\\@<!\%(\\\\\)\{-}/\zs.*')
    let pattern = matchstr(pattern, '/\zs.\{-}\\\@<!\%(\\\\\)\{-}\ze/')

    if empty(name) || empty(pattern)
      throw "Invalid arguments!"
    endif

    if !a:force && has_key(commandmap, name)
      throw string(name) . " is already defined, use ! to overwrite."
    endif

    let commandlist = s:SplitCommands(commands)

    if empty(commandlist)
      throw "Must provide a list of functions!"
    endif

	" 向 map 中添加模式和对应的命令
    let commandmap[name] = { 'pattern' : pattern, 'commands' : commandlist }
  catch
    echohl ErrorMsg
    echomsg "AddTabularPipeline: " . v:exception
    echohl None
  endtry
endfunction

" Tabularize /pattern[/format]                                            {{{2
" Tabularize name
"
" Align text, either using the given pattern, or the command associated with
" the given name.
com! -nargs=* -range -complete=customlist,<SID>CompleteTabularizeCommand
   \ Tabularize <line1>,<line2>call Tabularize(<q-args>)

function! Tabularize(command, ...) range
  let piperange_opt = {}
  if a:0
    let piperange_opt = a:1
  endif

  if empty(a:command)
    if !exists("s:last_tabularize_command")
      echohl ErrorMsg
      echomsg "Tabularize hasn't been called yet; no pattern/command to reuse!"
      echohl None
      return
    endif
  else
    let s:last_tabularize_command = a:command
  endif

  let command = s:last_tabularize_command

  let range = a:firstline . ',' . a:lastline

  try
    let [ pattern, format ] = s:ParsePattern(command)

    if !empty(pattern)
      let cmd  = "tabular#TabularizeStrings(a:lines, " . string(pattern)

      if !empty(format)
        let cmd .= "," . string(format)
      endif

      let cmd .= ")"

      exe range . 'call tabular#PipeRangeWithOptions(pattern, [ cmd ], '
                      \ . 'piperange_opt)'
    else
      if exists('b:TabularCommands') && has_key(b:TabularCommands, command)
        let usercmd = b:TabularCommands[command]
      elseif has_key(s:TabularCommands, command)
        let usercmd = s:TabularCommands[command]
      else
        throw "Unrecognized command " . string(command)
      endif

      exe range . 'call tabular#PipeRangeWithOptions(usercmd["pattern"], '
                      \ . 'usercmd["commands"], piperange_opt)'
    endif
  catch
    echohl ErrorMsg
    echomsg "Tabularize: " . v:exception
    echohl None
    return
  endtry
endfunction

" GTabularize /pattern[/format]                                           {{{2
" GTabularize name
"
" Align text on only matching lines, either using the given pattern, or the
" command associated with the given name.  Mnemonically, this is similar to
" the :global command, which takes some action on all rows matching a pattern
" in a range.  This command is different from normal :Tabularize in 3 ways:
"   1) If a line in the range does not match the pattern, it will be left
"      unchanged, and not in any way affect the outcome of other lines in the
"      range (at least, normally - but Pipelines can and will still look at
"      non-matching rows unless they are specifically written to be aware of
"      tabular#DoGTabularize() and handle it appropriately).
"   2) No automatic range determination - :Tabularize automatically expands
"      a single-line range (or a call with no range) to include all adjacent
"      matching lines.  That behavior does not make sense for this command.
"   3) If called without a range, it will act on all lines in the buffer (like
"      :global) rather than only a single line
com! -nargs=* -range=% -complete=customlist,<SID>CompleteTabularizeCommand
   \ GTabularize <line1>,<line2>
   \ call Tabularize(<q-args>, { 'mode': 'GTabularize' } )

" Stupid vimscript crap, part 2                                           {{{1
let &cpo = s:savecpo
unlet s:savecpo

" vim:set sw=2 sts=2 fdm=marker:
