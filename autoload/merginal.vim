"Use vimproc if available under windows to prevent opening a console window
function! merginal#system(command,...)
    if has('win32') && exists(':VimProcBang') "We don't need vimproc when we use linux
        if empty(a:000)
            return vimproc#system(a:command)
        else
            return vimproc#system(a:command,a:000[0])
        endif
    else
        if empty(a:000)
            return system(a:command)
        else
            return system(a:command,a:000[0])
        endif
    endif
endfunction

"Opens a file that belongs to a repo in a window that already belongs to that
"repo. Creates a new window if can't find suitable window.
function! merginal#openFileDecidedWindow(repo,fileName)
    "We have to check with bufexists, because bufnr also match prefixes of the
    "file name
    let l:fileBuffer=-1
    if bufexists(a:fileName)
        let l:fileBuffer=bufnr(a:fileName)
    endif

    "We have to check with bufloaded, because bufwinnr also matches closed
    "windows...
    let l:windowToOpenIn=-1
    if bufloaded(l:fileBuffer)
        let l:windowToOpenIn=bufwinnr(l:fileBuffer)
    endif

    "If we found an open window with the correct file, we jump to it
    if -1<l:windowToOpenIn
        execute l:windowToOpenIn.'wincmd w'
    else
        "Check if the previous window can be used
        let l:previousWindow=winnr('#')
        if s:isWindowADisposableWindowOfRepo(l:previousWindow,a:repo)
            execute winnr('#').'wincmd w'
        else
            "If the previous window can't be used, check if any open
            "window can be used
            let l:windowsToOpenTheFileIn=merginal#getListOfDisposableWindowsOfRepo(a:repo)
            if empty(l:windowsToOpenTheFileIn)
                "If no open window can be used, open a new Vim window
                new
            else
                execute l:windowsToOpenTheFileIn[0].'wincmd w'
            endif
        endif
        if -1<l:fileBuffer
            "If the buffer is already open, jump to it
            execute 'buffer '.l:fileBuffer
        else
            "Otherwise, load it
            execute 'edit '.fnameescape(a:fileName)
        endif
    endif
    diffoff "Just in case...
endfunction

"Check if the current window is modifiable, saved, and belongs to the repo
function! s:isCurrentWindowADisposableWindowOfRepo(repo)
    if !&modifiable
        return 0
    endif
    if &modified
        return 0
    endif
    try
        return a:repo==fugitive#repo()
    catch
        return 0
    endtry
endfunction

"Calls s:isCurrentWindowADisposableWindowOfRepo with a window number
function! s:isWindowADisposableWindowOfRepo(winnr,repo)
    let l:currentWindow=winnr()
    try
        execute a:winnr.'wincmd w'
        return s:isCurrentWindowADisposableWindowOfRepo(a:repo)
    finally
        execute l:currentWindow.'wincmd w'
    endtry
endfunction

"Get a list of windows that yield true with s:isWindowADisposableWindowOfRepo
function! merginal#getListOfDisposableWindowsOfRepo(repo)
    let l:result=[]
    let l:currentWindow=winnr()
    windo if s:isCurrentWindowADisposableWindowOfRepo(a:repo) | call add(l:result,winnr()) |  endif
    execute l:currentWindow.'wincmd w'
    return l:result
endfunction

"Get the repository that belongs to a window
function! s:getRepoOfWindow(winnr)
    "Ignore bad window numbers
    if a:winnr<=0
        return {}
    endif
    let l:currentWindow=winnr()
    try
        execute a:winnr.'wincmd w'
        return fugitive#repo()
    catch
        return {}
    finally
        execute l:currentWindow.'wincmd w'
    endtry
endfunction

"Reload the buffers
function! merginal#reloadBuffers()
    let l:currentWindow=winnr()
    try
        silent windo if ''==&buftype
                    \| edit
                    \| endif
    catch
        "do nothing
    endtry
    execute l:currentWindow.'wincmd w'
endfunction

"Exactly what it says on tin
function! merginal#runGitCommandInTreeReturnResult(repo,command)
    let l:dir=getcwd()
    execute 'cd '.fnameescape(a:repo.tree())
    try
        return merginal#system(a:repo.git_command().' '.a:command)
    finally
        execute 'cd '.fnameescape(l:dir)
    endtry
endfunction

"Like merginal#runGitCommandInTreeReturnResult but split result to lines
function! merginal#runGitCommandInTreeReturnResultLines(repo,command)
    let l:dir=getcwd()
    execute 'cd '.fnameescape(a:repo.tree())
    try
        return split(merginal#system(a:repo.git_command().' '.a:command),'\r\n\|\n\|\r')
    finally
        execute 'cd '.fnameescape(l:dir)
    endtry
endfunction

"Returns 1 if a new buffer was opened, 0 if it already existed
function! merginal#openTuiBuffer(bufferName,inWindow)
    let l:repo=fugitive#repo()

    let l:tuiBufferWindow=bufwinnr(bufnr(a:bufferName))

    if -1<l:tuiBufferWindow "Jump to the already open buffer
        execute l:tuiBufferWindow.'wincmd w'
    else "Open a new buffer
        if merginal#isMerginalWindow(a:inWindow)
            execute a:inWindow.'wincmd w'
            enew
        else
            40vnew
        endif
        setlocal buftype=nofile
        setlocal bufhidden=wipe
        setlocal nomodifiable
        setlocal winfixwidth
        setlocal winfixheight
        setlocal nonumber
        setlocal norelativenumber
        execute 'silent file '.a:bufferName
        call fugitive#detect(l:repo.dir())
    endif

    "At any rate, reassign the active repository
    let b:merginal_repo=l:repo

    "Check and return if a new buffer was created
    return -1==l:tuiBufferWindow
endfunction


"Check if a window belongs to Merginal
function! merginal#isMerginalWindow(winnr)
    if a:winnr<=0
        return 0
    endif
    let l:buffer=winbufnr(a:winnr)
    if l:buffer<=0
        return 0
    endif
    "check for the merginal repo buffer variable
    return !empty(getbufvar(l:buffer,'merginal_repo'))
endfunction


"For the branch in the specified line, retrieve:
" - type: 'local', 'remote' or 'detached'
" - isCurrent, isLocal, isRemote, isDetached
" - remote: the name of the remote or '' for local branches
" - name: the name of the branch, without the remote
" - handle: the named used for referring the branch in git commands
function! merginal#branchDetails(lineNumber)
    if !exists('b:merginal_repo')
        throw 'Unable to get branch details outside the merginal window'
    end
    let l:line=getline(a:lineNumber)
    let l:result={}


    "Check if this branch is the currently selected one
    let l:result.isCurrent=('*'==l:line[0])
    let l:line=l:line[2:]

    let l:detachedMatch=matchlist(l:line,'\v^\(detached from ([^/]+)%(/(.*))?\)$')
    if !empty(l:detachedMatch)
        let l:result.type='detached'
        let l:result.isLocal=0
        let l:result.isRemote=0
        let l:result.isDetached=1
        let l:result.remote=l:detachedMatch[1]
        let l:result.name=l:detachedMatch[2]
        if empty(l:detachedMatch[2])
            let l:result.handle=l:detachedMatch[1]
        else
            let l:result.handle=l:detachedMatch[1].'/'.l:detachedMatch[2]
        endif
        return l:result
    endif

    let l:remoteMatch=matchlist(l:line,'\v^remotes/([^/]+)%(/(\S*))%( \-\> (\S+))?$')
    if !empty(l:remoteMatch)
        let l:result.type='remote'
        let l:result.isLocal=0
        let l:result.isRemote=1
        let l:result.isDetached=0
        let l:result.remote=l:remoteMatch[1]
        let l:result.name=l:remoteMatch[2]
        if empty(l:remoteMatch[2])
            let l:result.handle=l:remoteMatch[1]
        else
            let l:result.handle=l:remoteMatch[1].'/'.l:remoteMatch[2]
        endif
        return l:result
    endif

    let l:result.type='local'
    let l:result.isLocal=1
    let l:result.isRemote=0
    let l:result.isDetached=0
    let l:result.remote=''
    let l:result.name=l:line
    let l:result.handle=l:line

    return l:result
endfunction


"Check if the current buffer's repo is in merge mode
function! merginal#isMergeMode()
    "Use glob() to check for file existence
    return !empty(glob(fugitive#repo().dir('MERGE_MODE')))
endfunction

"Open the branch list buffer for controlling buffers
function! merginal#openBranchListBuffer(...)
    if merginal#openTuiBuffer('Merginal:Branches',get(a:000,1,bufwinnr('Merginal:')))
        doautocmd User Merginal_BranchList
    endif

    "At any rate, refresh the buffer:
    call merginal#tryRefreshBranchListBuffer(1)
endfunction

augroup merginal
    autocmd User Merginal_BranchList nnoremap <buffer> R :call merginal#tryRefreshBranchListBuffer(0)<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> C :call <SID>checkoutBranchUnderCursor()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> cc :call <SID>checkoutBranchUnderCursor()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> ct :call <SID>trackBranchUnderCursor(0)<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> cT :call <SID>trackBranchUnderCursor(1)<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> A :call <SID>promptToCreateNewBranch()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> aa :call <SID>promptToCreateNewBranch()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> D :call <SID>deleteBranchUnderCursor()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> dd :call <SID>deleteBranchUnderCursor()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> M :call <SID>mergeBranchUnderCursor()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> mm :call <SID>mergeBranchUnderCursor()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> mf :call <SID>mergeBranchUnderCursorUsingFugitive()<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> ps :call <SID>remoteActionForBranchUnderCursor('push')<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> pl :call <SID>remoteActionForBranchUnderCursor('pull')<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> pf :call <SID>remoteActionForBranchUnderCursor('fetch')<Cr>
    autocmd User Merginal_BranchList nnoremap <buffer> gd :call <SID>diffWithBranchUnderCursor()<Cr>
augroup END

"If the current buffer is a branch list buffer - refresh it!
function! merginal#tryRefreshBranchListBuffer(jumpToCurrentBranch)
    if 'Merginal:Branches'==bufname('')
        let l:branchList=split(merginal#system(b:merginal_repo.git_command('branch','--all')),'\r\n\|\n\|\r')
        let l:currentLine=line('.')

        setlocal modifiable
        "Clear the buffer:
        normal ggdG
        "Write the branch list:
        call setline(1,l:branchList)
        setlocal nomodifiable


        if a:jumpToCurrentBranch
            "Find the current branch's index
            let l:currentBranchIndex=-1
            for i in range(len(l:branchList))
                if '*'==l:branchList[i][0]
                    let l:currentBranchIndex=i
                    break
                endif
            endfor
            if -1<l:currentBranchIndex
                "Jump to the current branch's line
                execute l:currentBranchIndex+1
            endif
        else
            execute l:currentLine
        endif
    endif
endfunction

"Exactly what it says on tin
function! s:checkoutBranchUnderCursor()
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'--no-pager checkout '.shellescape(l:branch.handle))
        call merginal#reloadBuffers()
        call merginal#tryRefreshBranchListBuffer(0)
    endif
endfunction

"Track what it says on tin
function! s:trackBranchUnderCursor(promptForName)
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        if !l:branch.isRemote
            throw 'Can not track - branch is not remote'
        endif
        let l:newBranchName=l:branch.name
        if a:promptForName
            let l:newBranchName=input('Track `'.l:branch.handle.'` as: ',l:newBranchName)
            if empty(l:newBranchName)
                echo ' '
                echo 'Branch tracking canceled by the user'
                return
            endif
        endif
        echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'--no-pager checkout -b '.shellescape(l:newBranchName).' --track '.shellescape(l:branch.handle))
        call merginal#reloadBuffers()
        call merginal#tryRefreshBranchListBuffer(0)
    endif
endfunction

"Uses the current branch as the source
function! s:promptToCreateNewBranch()
    if 'Merginal:Branches'==bufname('')
        let l:newBranchName=input('Branch `'.b:merginal_repo.head().'` to: ')
            if empty(l:newBranchName)
                echo ' '
                echo 'Branch creation canceled by the user'
                return
            endif
        echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'--no-pager checkout -b '.shellescape(l:newBranchName))
        call merginal#reloadBuffers()
        call merginal#tryRefreshBranchListBuffer(1)
    endif
endfunction

"Verifies the decision
function! s:deleteBranchUnderCursor()
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        let l:answer=0
        if l:branch.isLocal
            let l:answer='yes'==input('Delete branch `'.l:branch.handle.'`?(type "yes" to confirm) ')
        elseif l:branch.isRemote
            "Deleting remote branches needs a special warning
            let l:answer='yes-remote'==input('Delete remote(!) branch `'.l:branch.handle.'`?(type "yes-remote" to confirm) ')
        endif
        if l:answer
            if l:branch.isLocal
                echo ' '
                echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'--no-pager branch -D '.shellescape(l:branch.handle))
            else
                execute '!'.b:merginal_repo.git_command('push').' '.shellescape(l:branch.remote).' --delete '.shellescape(l:branch.name)
            endif
            call merginal#reloadBuffers()
            call merginal#tryRefreshBranchListBuffer(0)
        else
            echo ' '
            echo 'Branch deletion canceled by the user'
        endif
    endif
endfunction

"If there are merge conflicts, opens the merge conflicts buffer
function! s:mergeBranchUnderCursor()
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        echo ' '
        echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'merge --no-commit '.shellescape(l:branch.handle))
        if v:shell_error
            call merginal#reloadBuffers()
            call merginal#openMergeConflictsBuffer(winnr())
        endif
    endif
endfunction

"Use Fugitive's :Gmerge. It was added to Fugitive after I implemented
"Merginal's merge, and I don't want to remove it since it can still more
"comfortable for some.
function! s:mergeBranchUnderCursorUsingFugitive()
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        execute ':Gmerge '.l:branchName.handle
    endif
endfunction

"Exactly what it says on tin
function! s:remoteActionForBranchUnderCursor(remoteAction)
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        if !l:branch.isLocal
            throw 'Can not '.a:remoteAction.' - branch is not local'
        endif
        let l:remotes=merginal#runGitCommandInTreeReturnResultLines(b:merginal_repo,'remote')
        if empty(l:remotes)
            throw 'Can not '.a:remoteAction.' - no remotes defined'
        endif

        let l:chosenRemoteIndex=0
        if 1<len(l:remotes)
            let l:listForInputlist=map(copy(l:remotes),'v:key+1.") ".v:val')
            "Choose the correct text accoring to the action:
            if 'push'==a:remoteAction
                call insert(l:listForInputlist,'Choose remote to '.a:remoteAction.' `'.l:branch.handle.'` to:')
            else
                call insert(l:listForInputlist,'Choose remote to '.a:remoteAction.' `'.l:branch.handle.'` from:')
            endif
            let l:chosenRemoteIndex=inputlist(l:listForInputlist)

            "Check that the chosen index is in range
            if l:chosenRemoteIndex<=0 || len(l:remotes)<l:chosenRemoteIndex
                return
            endif

            let l:chosenRemoteIndex=l:chosenRemoteIndex-1
        endif

        let l:chosenRemote=l:remotes[l:chosenRemoteIndex]

        "Pulling requires the --no-commit flag
        if 'pull'==a:remoteAction
            execute '!'.b:merginal_repo.git_command(a:remoteAction,'--no-commit').' '.shellescape(l:chosenRemote).' '.shellescape(l:branch.handle)
            call merginal#reloadBuffers()
        else
            execute '!'.b:merginal_repo.git_command(a:remoteAction).' '.shellescape(l:chosenRemote).' '.shellescape(l:branch.handle)
        endif
        call merginal#tryRefreshBranchListBuffer(0)
    endif
endfunction


"Opens the diff files buffer
function! s:diffWithBranchUnderCursor()
    if 'Merginal:Branches'==bufname('')
        let l:branch=merginal#branchDetails('.')
        if l:branch.isCurrent
            throw 'Can not diff against the current branch'
        endif
        call merginal#openDiffFilesBuffer(l:branch)
    endif
endfunction



"Open the merge conflicts buffer for resolving merge conflicts
function! merginal#openMergeConflictsBuffer(...)
    let l:currentFile=expand('%:~:.')
    if merginal#openTuiBuffer('Merginal:Conflicts',get(a:000,1,bufwinnr('Merginal:')))
        doautocmd User Merginal_MergeConflicts
    endif

    "At any rate, refresh the buffer:
    call merginal#tryRefreshMergeConflictsBuffer(l:currentFile)
endfunction

augroup merginal
    autocmd User Merginal_MergeConflicts nnoremap <buffer> R :call merginal#tryRefreshMergeConflictsBuffer(0)<Cr>
    autocmd User Merginal_MergeConflicts nnoremap <buffer> <Cr> :call <SID>openMergeConflictUnderCursor()<Cr>
    autocmd User Merginal_MergeConflicts nnoremap <buffer> A :call <SID>addConflictedFileToStagingArea()<Cr>
    autocmd User Merginal_MergeConflicts nnoremap <buffer> aa :call <SID>addConflictedFileToStagingArea()<Cr>
augroup END

"Returns 1 if all merges are done
function! merginal#tryRefreshMergeConflictsBuffer(fileToJumpTo)
    if 'Merginal:Conflicts'==bufname('')
        "Get the list of unmerged files:
        let l:mergeConflicts=split(merginal#system(b:merginal_repo.git_command('ls-files','--unmerged')),'\r\n\|\n\|\r')
        "Split by tab - the first part is info, the second is the file name
        let l:mergeConflicts=map(l:mergeConflicts,'split(v:val,"\t")')
        "Only take the stage 1 files - stage 2 and 3 are the same files with
        "different hash, and we don't care about the hash here
        let l:mergeConflicts=filter(l:mergeConflicts,'v:val[0] =~ "\\v 1$"')
        "Take the file name - we no longer care about the info
        let l:mergeConflicts=map(l:mergeConflicts,'v:val[1]')
        "If the working copy is not the current dir, we can get wrong paths.
        "We need to resulve that:
        let l:mergeConflicts=map(l:mergeConflicts,'b:merginal_repo.tree(v:val)')
        "Make the paths as short as possible:
        let l:mergeConflicts=map(l:mergeConflicts,'fnamemodify(v:val,":~:.")')


        let l:currentLine=line('.')

        setlocal modifiable
        "Clear the buffer:
        normal ggdG
        "Write the branch list:
        call setline(1,l:mergeConflicts)
        setlocal nomodifiable
        if empty(l:mergeConflicts)
            return 1
        endif

        if empty(a:fileToJumpTo)
            execute l:currentLine
        else
            let l:lineNumber=search('\V\^'+escape(a:fileToJumpTo,'\')+'\$','cnw')
            if 0<l:lineNumber
                execute l:lineNumber
            else
                execute l:currentLine
            endif
        endif
    endif
    return 0
endfunction

"Exactly what it says on tin
function! s:openMergeConflictUnderCursor()
    if 'Merginal:Conflicts'==bufname('')
        let l:fileName=getline('.')
        if empty(l:fileName)
            return
        endif
        call merginal#openFileDecidedWindow(b:merginal_repo,l:fileName)
    endif
endfunction

"If that was the last merge conflict, automatically opens Fugitive's status
"buffer
function! s:addConflictedFileToStagingArea()
    if 'Merginal:Conflicts'==bufname('')
        let l:fileName=getline('.')
        if empty(l:fileName)
            return
        endif
        echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'--no-pager add '.shellescape(fnamemodify(l:fileName,':p')))

        if merginal#tryRefreshMergeConflictsBuffer(0)
            "If this returns 1, that means this is the last branch, and we
            "should open gufitive's status window
            let l:mergeConflictsBuffer=bufnr('')
            Gstatus
            let l:gitStatusBuffer=bufnr('')
            execute bufwinnr(l:mergeConflictsBuffer).'wincmd w'
            wincmd q
            execute bufwinnr(l:gitStatusBuffer).'wincmd w'
        endif
    endif
endfunction


"Open the diff files buffer for diffing agains another branch
function! merginal#openDiffFilesBuffer(diffBranch,...)
    if merginal#openTuiBuffer('Merginal:Diff',get(a:000,1,bufwinnr('Merginal:')))
        doautocmd User Merginal_DiffFiles
    endif

    let b:merginal_diffBranch=a:diffBranch

    "At any rate, refresh the buffer:
    call merginal#tryRefreshDiffFilesBuffer()
endfunction

augroup merginal
    autocmd User Merginal_DiffFiles nnoremap <buffer> R :call merginal#tryRefreshDiffFilesBuffer()<Cr>
    autocmd User Merginal_DiffFiles nnoremap <buffer> <Cr> :call <SID>openDiffFileUnderCursor()<Cr>
    autocmd User Merginal_DiffFiles nnoremap <buffer> ds :call <SID>openDiffFileUnderCursorAndDiff('s')<Cr>
    autocmd User Merginal_DiffFiles nnoremap <buffer> dv :call <SID>openDiffFileUnderCursorAndDiff('v')<Cr>
    autocmd User Merginal_DiffFiles nnoremap <buffer> co :call <SID>checkoutDiffFileUnderCursor()<Cr>
augroup END


"For the diff file in the specified line, retrieve:
" - type: 'added', 'deleted' or 'modified'
" - isAdded, isDeleted, isModified
" - fileInTree: the path of the file relative to the repo
" - fileFullPath: the full path to the file
function! merginal#diffFileDetails(lineNumber)
    if !exists('b:merginal_repo')
        throw 'Unable to get diff file details outside the merginal window'
    endif
    let l:line=getline(a:lineNumber)
    let l:result={}

    let l:matches=matchlist(l:line,'\v([ADM])\t(.*)$')

    if empty(l:matches)
        throw 'Unable to get diff files details for `'.l:line.'`'
    endif

    let l:result.isAdded=0
    let l:result.isDeleted=0
    let l:result.isModified=0
    if 'A'==l:matches[1]
        let l:result.type='added'
        let l:result.isAdded=1
    elseif 'D'==l:matches[1]
        let l:result.type='deleted'
        let l:result.isDeleted=1
    else
        let l:result.type='modified'
        let l:result.isModified=1
    endif

    let l:result.fileInTree=l:matches[2]
    let l:result.fileFullPath=b:merginal_repo.tree(l:matches[2])

    return l:result
endfunction

"If the current buffer is a branch list buffer - refresh it!
function! merginal#tryRefreshDiffFilesBuffer()
    if 'Merginal:Diff'==bufname('')
        let l:diffBranch=b:merginal_diffBranch
        let l:diffFiles=merginal#runGitCommandInTreeReturnResultLines(b:merginal_repo,'diff --name-status '.shellescape(l:diffBranch.handle))
        let l:currentLine=line('.')

        setlocal modifiable
        "Clear the buffer:
        normal ggdG
        "Write the diff files list:
        call setline(1,l:diffFiles)
        setlocal nomodifiable

        execute l:currentLine
    endif
endfunction

"Exactly what it says on tin
function! s:openDiffFileUnderCursor()
    if 'Merginal:Diff'==bufname('')
        let l:diffFile=merginal#diffFileDetails('.')

        if l:diffFile.isDeleted
            throw 'File does not exist in current buffer'
        endif

        call merginal#openFileDecidedWindow(b:merginal_repo,l:diffFile.fileFullPath)
    endif
endfunction

"Exactly what it says on tin
function! s:openDiffFileUnderCursorAndDiff(diffType)
    if a:diffType!='s' && a:diffType!='v'
        throw 'Bad diff type'
    endif
    if 'Merginal:Diff'==bufname('')
        let l:diffFile=merginal#diffFileDetails('.')

        if l:diffFile.isAdded
            throw 'File does not exist in other buffer'
        endif

        let l:repo=b:merginal_repo
        let l:diffBranch=b:merginal_diffBranch

        "Close currently open git diffs
        let l:currentWindowBuffer=winbufnr('.')
        try
            windo if 'blob'==get(b:,'fugitive_type','') && exists('w:fugitive_diff_restore')
                        \| bdelete
                        \| endif
        catch
            "do nothing
        finally
            execute bufwinnr(l:currentWindowBuffer).'wincmd w'
        endtry

        call merginal#openFileDecidedWindow(l:repo,l:diffFile.fileFullPath)

        execute ':G'.a:diffType.'diff '.fnameescape(l:diffBranch.handle)
    endif
endfunction

"Checks out the file from the other branch to the current branch
function! s:checkoutDiffFileUnderCursor()
    if 'Merginal:Diff'==bufname('')
        let l:diffFile=merginal#diffFileDetails('.')

        if l:diffFile.isAdded
            throw 'File does not exist in diffed buffer'
        endif

        let l:answer=1
        if !empty(glob(l:diffFile.fileFullPath))
            let l:answer='yes'==input('Override `'.l:diffFile.fileInTree.'`?(type "yes" to confirm) ')
        endif
        if l:answer
            echo merginal#runGitCommandInTreeReturnResult(b:merginal_repo,'--no-pager checkout '.shellescape(b:merginal_diffBranch.handle)
                        \.' -- '.shellescape(l:diffFile.fileFullPath))
            call merginal#reloadBuffers()
            call merginal#tryRefreshDiffFilesBuffer()
        else
            echo ' '
            echo 'File checkout canceled by the user'
        endif
    endif
endfunction