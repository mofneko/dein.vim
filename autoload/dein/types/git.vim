"=============================================================================
" FILE: git.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu at gmail.com>
"          Robert Nelson     <robert@rnelson.ca>
" License: MIT license
"=============================================================================

" Global options definition.
call dein#util#_set_default(
      \ 'g:dein#types#git#clone_depth', 0)
call dein#util#_set_default(
      \ 'g:dein#types#git#command_path', 'git')
call dein#util#_set_default(
      \ 'g:dein#types#git#default_hub_site', 'github.com')
call dein#util#_set_default(
      \ 'g:dein#types#git#default_protocol', 'https')
call dein#util#_set_default(
      \ 'g:dein#types#git#pull_command', 'pull --ff --ff-only')


function! dein#types#git#define() abort
  return s:type
endfunction

let s:type = {
      \ 'name': 'git',
      \ 'command': g:dein#types#git#command_path,
      \ 'executable': executable(g:dein#types#git#command_path),
      \ }

function! s:type.init(repo, options) abort
  if !self.executable
    return {}
  endif

  if a:repo =~# '^/\|^\a:[/\\]' && s:is_git_dir(a:repo.'/.git')
    " Local repository.
    return { 'type': 'git', 'local': 1 }
  elseif a:repo =~#
        \ '//\%(raw\|gist\)\.githubusercontent\.com/\|/archive/[^/]\+\.zip$'
    return {}
  endif

  let uri = self.get_uri(a:repo, a:options)
  if uri ==# ''
    return {}
  endif

  let directory = substitute(uri, '\.git$', '', '')
  let directory = substitute(directory, '^https:/\+\|^git@', '', '')
  let directory = substitute(directory, ':', '/', 'g')

  return { 'type': 'git',
        \  'path': dein#util#_get_base_path().'/repos/'.directory }
endfunction
function! s:type.get_uri(repo, options) abort
  if a:repo =~# '^/\|^\a:[/\\]'
    return s:is_git_dir(a:repo.'/.git') ? a:repo : ''
  endif

  if a:repo =~# '^git@'
    " Parse "git@host:name" pattern
    let protocol = 'ssh'
    let host = matchstr(a:repo[4:], '[^:]*')
    let name = a:repo[4 + len(host) + 1 :]
  else
    let protocol = matchstr(a:repo, '^.\{-}\ze://')
    let rest = a:repo[len(protocol):]
    let name = substitute(rest, '^://[^/]*/', '', '')
    let host = substitute(matchstr(rest, '^://\zs[^/]*\ze/'),
          \ ':.*$', '', '')
  endif
  if host ==# ''
    let host = g:dein#types#git#default_hub_site
  endif

  if protocol ==# ''
        \ || a:repo =~# '\<\%(gh\|github\|bb\|bitbucket\):\S\+'
        \ || has_key(a:options, 'type__protocol')
    let protocol = get(a:options, 'type__protocol',
          \ g:dein#types#git#default_protocol)
  endif

  if protocol !=# 'https' && protocol !=# 'ssh'
    call dein#util#_error(
          \ printf('Repo: %s The protocol "%s" is unsecure and invalid.',
          \ a:repo, protocol))
    return ''
  endif

  if a:repo !~# '/'
    call dein#util#_error(
          \ printf('vim-scripts.org is deprecated.'
          \ . ' You can use "vim-scripts/%s" instead.', a:repo))
    return ''
  else
    let uri = (protocol ==# 'ssh' &&
          \    (host ==# 'github.com' || host ==# 'bitbucket.com' ||
          \     host ==# 'bitbucket.org')) ?
          \ 'git@' . host . ':' . name :
          \ protocol . '://' . host . '/' . name
  endif

  return uri
endfunction

function! s:type.get_sync_command(plugin) abort
  if !isdirectory(a:plugin.path)
    let commands = []

    call add(commands, self.command)
    call add(commands, '-c')
    call add(commands, 'credential.helper=')
    call add(commands, 'clone')
    call add(commands, '--recursive')

    let depth = get(a:plugin, 'type__depth', g:dein#types#git#clone_depth)
    if depth > 0 && self.get_uri(a:plugin.repo, a:plugin) !~# '^git@'
      call add(commands, '--depth=' . depth)

      if get(a:plugin, 'rev', '') !=# ''
        call add(commands, '--branch')
        call add(commands, a:plugin.rev)
      endif
    endif

    call add(commands, self.get_uri(a:plugin.repo, a:plugin))
    call add(commands, a:plugin.path)

    return commands
  else
    let git = self.command

    let fetch_cmd = git . ' -c credential.helper= fetch '
    let remote_origin_cmd = git . ' remote set-head origin -a'
    let pull_cmd = git . ' ' . g:dein#types#git#pull_command
    let submodule_cmd = git . ' submodule update --init --recursive'

    " Note: "remote_origin_cmd" does not work when "depth" is specified.
    let depth = get(a:plugin, 'type__depth', g:dein#types#git#clone_depth)

    if dein#util#_is_powershell()
      let cmd = fetch_cmd
      if depth <= 0
        let cmd .= '; if ($?) { ' . remote_origin_cmd . ' }'
      endif
      let cmd .= '; if ($?) { ' . pull_cmd . ' }'
      let cmd .= '; if ($?) { ' . submodule_cmd . ' }'
    else
      let and = dein#util#_is_fish() ? '; and ' : ' && '
      let cmds = [fetch_cmd]
      if depth <= 0
        call add(cmds, remote_origin_cmd)
      endif
      let cmds += [pull_cmd, submodule_cmd]
      let cmd = join(cmds, and)
    endif

    return cmd
  endif
endfunction

function! s:type.get_revision_number(plugin) abort
  return s:git_get_revision(a:plugin.path)
endfunction
function! s:type.get_log_command(plugin, new_rev, old_rev) abort
  if !self.executable || a:new_rev ==# '' || a:old_rev ==# ''
    return []
  endif

  " NOTE: If the a:old_rev is not the ancestor of two branchs. Then do not use
  " %s^.  use %s^ will show one commit message which already shown last time.
  let is_not_ancestor = dein#install#_system(
        \ self.command . ' merge-base '
        \ . a:old_rev . ' ' . a:new_rev) ==# a:old_rev
  return printf(self.command .
        \ ' log %s%s..%s --graph --no-show-signature' .
        \ ' --pretty=format:"%%h [%%cr] %%s"',
        \ a:old_rev, (is_not_ancestor ? '' : '^'), a:new_rev)
endfunction
function! s:type.get_revision_lock_command(plugin) abort
  if !self.executable
    return []
  endif

  let rev = get(a:plugin, 'rev', '')
  if rev =~# '*'
    " Use the released tag (git 1.9.2 or above required)
    let output = dein#install#_system(
          \ [self.command, 'tag', rev,
          \  '--list', '--sort', '-version:refname'])
    let rev = get(split(output, "\n"), 0, '')
  endif
  if rev ==# ''
    " Fix detach HEAD.
    " Use symbolic-ref feature (git 1.8.7 or above required)
    let output = dein#install#_system(
          \ [self.command, 'symbolic-ref', '--short', 'HEAD'])
    let rev = get(split(output, "\n"), 0, '')
    if rev =~# 'fatal: '
      " Fix "fatal: ref HEAD is not a symbolic ref" error
      " NOTE: Should specify the default branch?
      let rev = 'main'
    endif
  endif

  return [self.command, 'checkout', rev, '--']
endfunction
function! s:type.get_rollback_command(plugin, rev) abort
  if !self.executable
    return []
  endif

  return [self.command, 'reset', '--hard', a:rev]
endfunction
function! s:type.get_diff_command(plugin, old_rev, new_rev) abort
  if !self.executable
    return []
  endif

  return [self.command, 'diff', a:old_rev . '..'. a:new_rev,
        \ '--', 'doc', 'README', 'README.md']
endfunction

function! s:is_git_dir(path) abort
  if isdirectory(a:path)
    let git_dir = a:path
  elseif filereadable(a:path)
    " check if this is a gitdir file
    " File starts with "gitdir: " and all text after this string is treated
    " as the path. Any CR or NLs are stripped off the end of the file.
    let buf = join(readfile(a:path, 'b'), "\n")
    let matches = matchlist(buf, '\C^gitdir: \(\_.*[^\r\n]\)[\r\n]*$')
    if empty(matches)
      return 0
    endif
    let path = fnamemodify(a:path, ':h')
    if fnamemodify(a:path, ':t') ==# ''
      " if there's no tail, the path probably ends in a directory separator
      let path = fnamemodify(path, ':h')
    endif
    let git_dir = s:join_paths(path, matches[1])
    if !isdirectory(git_dir)
      return 0
    endif
  else
    return 0
  endif

  " Git only considers it to be a git dir if a few required files/dirs exist
  " and are accessible inside the directory.
  " NOTE: We can't actually test file permissions the way we'd like to, since
  " getfperm() gives the mode string but doesn't tell us whether the user or
  " group flags apply to us. Instead, just check if dirname/. is a directory.
  " This should also check if we have search permissions.
  " I'm assuming here that dirname/. works on windows, since I can't test.
  " NOTE: Git also accepts having the GIT_OBJECT_DIRECTORY env var set instead
  " of using .git/objects, but we don't care about that.
  for name in ['objects', 'refs']
    if !isdirectory(s:join_paths(git_dir, name))
      return 0
    endif
  endfor

  " Git also checks if HEAD is a symlink or a properly-formatted file.
  " We don't really care to actually validate this, so let's just make
  " sure the file exists and is readable.
  " NOTE: It may also be a symlink, which can point to a path that doesn't
  " necessarily exist yet.
  let head = s:join_paths(git_dir, 'HEAD')
  if !filereadable(head) && getftype(head) !=# 'link'
    return 0
  endif

  " Sure looks like a git directory. There's a few subtleties where we'll
  " accept a directory that git itself won't, but I think we can safely ignore
  " those edge cases.
  return 1
endfunction

let s:is_windows = dein#util#_is_windows()

function! s:join_paths(path1, path2) abort
  " Joins two paths together, handling the case where the second path
  " is an absolute path.
  if s:is_absolute(a:path2)
    return a:path2
  endif
  if a:path1 =~ (s:is_windows ? '[\\/]$' : '/$') ||
        \ a:path2 =~ (s:is_windows ? '^[\\/]' : '^/')
    " the appropriate separator already exists
    return a:path1 . a:path2
  else
    " NOTE: I'm assuming here that '/' is always valid as a directory
    " separator on Windows. I know Windows has paths that start with \\?\ that
    " diasble behavior like that, but I don't know how Vim deals with that.
    return a:path1 . '/' . a:path2
  endif
endfunction

if s:is_windows
  function! s:is_absolute(path) abort
    return a:path =~# '^[\\/]\|^\a:'
  endfunction
else
  function! s:is_absolute(path) abort
    return a:path =~# '^/'
  endfunction
endif

" From minpac plugin manager
" https://github.com/k-takata/minpac
" https://github.com/junegunn/vim-plug/pull/937
function! s:isabsolute(dir) abort
  return a:dir =~# '^/' || (has('win32') && a:dir =~? '^\%(\\\|[A-Z]:\)')
endfunction

function! s:get_gitdir(dir) abort
  let gitdir = a:dir . '/.git'
  if isdirectory(gitdir)
    return gitdir
  endif
  try
    let line = readfile(gitdir)[0]
    if line =~# '^gitdir: '
      let gitdir = line[8:]
      if !s:isabsolute(gitdir)
        let gitdir = a:dir . '/' . gitdir
      endif
      if isdirectory(gitdir)
        return gitdir
      endif
    endif
  catch
  endtry
  return ''
endfunction

function! s:git_get_remote_origin_url(dir) abort
  let gitdir = s:get_gitdir(a:dir)
  if gitdir ==# ''
    return ''
  endif
  try
    let lines = readfile(gitdir . '/config')
    let [n, ll, url] = [0, len(lines), '']
    while n < ll
      let line = trim(lines[n])
      if stridx(line, '[remote "origin"]') != 0
        let n += 1
        continue
      endif
      let n += 1
      while n < ll
        let line = trim(lines[n])
        if line ==# '['
          break
        endif
        let url = matchstr(line, '^url\s*=\s*\zs[^ #]\+')
        if !empty(url)
          break
        endif
        let n += 1
      endwhile
      let n += 1
    endwhile
    return url
  catch
    return ''
  endtry
endfunction

function! s:git_get_revision(dir) abort
  let gitdir = s:get_gitdir(a:dir)
  if gitdir ==# ''
    return ''
  endif
  try
    let line = readfile(gitdir . '/HEAD')[0]
    if line =~# '^ref: '
      let ref = line[5:]
      if filereadable(gitdir . '/' . ref)
        return readfile(gitdir . '/' . ref)[0]
      endif
      for line in readfile(gitdir . '/packed-refs')
        if line =~# ' ' . ref
          return substitute(line, '^\([0-9a-f]*\) ', '\1', '')
        endif
      endfor
    endif
    return line
  catch
  endtry
  return ''
endfunction

function! s:git_get_branch(dir) abort
  let gitdir = s:get_gitdir(a:dir)
  if gitdir ==# ''
    return ''
  endif
  try
    let line = readfile(gitdir . '/HEAD')[0]
    if line =~# '^ref: refs/heads/'
      return line[16:]
    endif
    return 'HEAD'
  catch
    return ''
  endtry
endfunction
