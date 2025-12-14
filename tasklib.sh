#!/usr/bin/env sh

# tasklib.sh is a collection of shell functions to help a programmer
# nimbly set up new tasks of mutiple repositories at a time using git
# worktrees, and also maintain a set of environment variables per
# task.

if [ -z "$TASKS_DIR" ]
then
    export TASKS_DIR="$HOME/tasks/"
fi

if [ -z "$REPOS_DIR" ]
then
    export REPOS_DIR="$HOME/repos/"
fi


# t.rcinit performs all rc init functions -- put this into your rc
# file after sourcing tasklib.sh.
t_rcinit() {
    if [ -n "$TASK_SHELL_ENTER" ]
    then
	export TASK="$TASK_SHELL_ENTER"
	unset "$TASK_SHELL_ENTER"
	t_enter "$TASK_SHELL_ENTER"
    fi
}

t_err() {
    echo "tasklib error:" "$@" >&2
}

t_log() {
    echo "[tasklib]" "$@"
}

t_dbg() {
    if [ -n "$tdebug" ]
    then
	echo "[tasklib:debug]" "$@"
    fi
}

# t.new creates a new task, by creating the directories for it and
# sourcing the create rc file and the flavor rc file if a --flavor
# argument was passed.
t_new() {
    argslist=""
    task=""
    for arg in "$@"
    do
	case "$arg" in
	    --*=*)
		# Remove prefix, export
		export "${arg#--}"
		argslist="${argslist}\n${arg#--}"
		t_dbg "exported: ${arg#--}"		
		;;
	    --*)
		export "${arg#--}=1"
		argslist="${argslist}\n${arg#--}=1"
		t_dbg "exported bool: ${arg#--}=1"
		;;
	    *)
		task="$arg"
		t_dbg "setting task: $task"		
		break
		;;
	esac
    done

    t_dbg "args: ${argslist}"
    if [ -z "$task" ]
    then
	echo "t.new needs a ticket, usage:"
	echo "t.new [options...] <ticket-name>"
	return
    fi

    export TASK="$task"
    mkdir -p "$TASKS_DIR/$task/src"
    mkdir -p "$TASKS_DIR/$task/etc"
    if ! cd "$TASKS_DIR/$task"
    then
	t_err "unable to cd to task directory"
	return
    fi
    export TASK_LOC="$TASKS_DIR/$task"

    if [ -f "$HOME/.trc/create" ]
    then
	# shellcheck disable=SC1091
	. "$HOME/.trc/create"
    fi

    if [ -n "$flavor" ] && [ -d "$HOME/.trc/flavors/$flavor" ]
    then
	echo ". $HOME/.trc/flavors/$flavor" >> "$TASKS_DIR/$TASK/etc/.taskrc"
    fi

    {
	printf "%s\n" "${argslist}";
	printf "TASK=%s\n" "$TASK";
	printf "TASK_LOC=%s\n" "$TASK_LOC";
    } >> "$TASK_LOC/etc/.taskrc"

    echo "ok, created $TASK in $TASKS_DIR/$TASK."
    if [ -z "$noenter" ]
    then
	t_enter "$TASK"
    fi
}


# t.enter enters the ticket environment in the current shell instance.
t_enter() {
    if [ -z "$1" ]
    then
	echo "you need to specify a task as the first argument."
	return
    fi

    glbl_rcfile="$HOME/.trc/enter"

    if [ -f "$glbl_rcfile" ]
    then
	t_dbg "sourcing global rcfile: $glbl_rcfile"
	# shellcheck disable=SC1090	
	. "$glbl_rcfile"
    fi

    lcl_rcfile="$TASKS_DIR/$1/etc/.taskrc"

    if [ -f "$lcl_rcfile" ]
    then
	t_dbg "sourcing local rcfile: $lcl_rcfile"
	# shellcheck disable=SC1090	
	. "$lcl_rcfile"
    fi
    if [ -d "$TASK_LOC" ]
    then
	if ! cd "$TASK_LOC"
	then
	    t_err "unable to cd to task location $TASK_LOC"
	    return
	fi
    else
	echo "there is no task $1?"
    fi
}

t_shell() {
    if [ -z "$1" ]
    then
	t_err "you need to specify a task as the first argument."
	return
    fi    
    TASK_SHELL_ENTER="$1" "$SHELL" -i
}

t_worktree() {
    if [ -z "$1" ]
    then
	t_err "you need to specify a repository as the first argument."
	return
    fi
    if [ -z "$TASK" ]
    then
	t_err "you are not currently working on a task."
	return
    fi
    repodir="$REPOS_DIR/$1"

    if ! [ -d "$repodir" ]
    then
	t_err "the repo directory: $repodir doesn't exist."
	return
    fi

    if [ -z "$2" ]
    then
	wdir="TASK_LOC/src/$1"
    elif [ -d "$(dirname "$TASK_LOC/src/$2")" ]
    then
	wdir="$TASK_LOC/src/$2"
	t_log "cloning relative path $2 to $wdir"
    else
	wdir="$2"
    fi

    if [ -z "$3" ]
    then
	head="origin/HEAD"
    else
	t_log "using starting point $3"
	head="$3"
    fi
    
    git -C "$repodir" worktree add -b "$TASK" "$wdir" "$head"
}

t_cd() {
    if [ -z "$1" ]
    then
	cd "$TASK_LOC" || {
	    t_err "unable to cd to task location: $TASK_LOC.";
	    return;
	}
    elif [ -d "$TASK_LOC/$1" ]
    then
	cd "$TASK_LOC/$1" || {
	    t_err "unable to cd to location: $TASK_LOC/$1";
	    return;
	}
    elif [ -d "$TASK_LOC/src/$1" ]
    then
	cd "$TASK_LOC/src/$1" || {
	    t_err "unable to cd to location: $TASK_LOC/src/$1";
	    return;
	}
    else
	found=$(find "$TASK_LOC" -name "$1" | head -1)
	if [ -z "$found" ]
	then
	    t_err "unable to find $1"
	    return
	fi
	if [ -d "$found" ]
	then
	    cd "$found" || {
		t_err "can't cd to $found";
		return;
	    }
	else
	    cd "$(dirname "$found")" || {
		t_err "can't cd to $(dirname "$found")";
		return;
	    }
	fi
    fi
}

t_install_files() {
    if ! [ -d "./.git" ] || ! [ -f "./tasklib.sh" ]
    then
	t_err "can't install from here, I need to be in the tasklib git."
	return
    fi

    t_log "making the .trc directory"
    mkdir -p "$HOME/.trc"
    t_log "making tasklib symlink..."
    if ! ln -s "$PWD/tasklib.sh" "$HOME/.trc/tasklib.sh"
    then
	if ! [ -h "$HOME/.trc/tasklib.sh" ]
	then
	    t_err "tasklib.sh exists and isn't a symlink..."
	    return
	else
	    t_log "symlink exists, continuing..."
	fi
    fi
	   
    mkdir -p "$HOME/.trc/flavors"

    if [ -n "$1" ] && [ -d "$PWD/templates/$1" ]
    then
	cp -R "$PWD/templates/$1" "$HOME/.trc/" || {
	    t_err "copying template $1 failed.";
	    return;
	}
    elif ! [ -f "$HOME/.trc/create" ] && ! [ -f "$HOME/.trc/enter" ]
    then
	t_log "no template specified, creating touchfiles..."
	printf "# This script sourced on create\n" >>  "$HOME/.trc/create"
	printf "# This script sourced on enter\n" >>  "$HOME/.trc/enter"
	mkdir -p "$HOME/.trc/flavors" || {
	    t_err "unable to make flavors dir"
	}
    fi

    chmod a+x "$HOME/.trc/create"
    chmod a+x "$HOME/.trc/enter"        
}

__t_rcfile() {
    if echo "$SHELL" | grep "zsh" >/dev/null
    then
	if [ -f "$HOME/.zprofile" ]
	then
	    echo "$HOME/.zprofile"
	else
	    echo "$HOME/.zshrc"
	fi
	return
    fi
    echo "$HOME/.bashrc"
}

# t_install_rc installs the rc hooks -- source the tasklib.sh file,
# and execute the t_rcinit func.
t_install_rc() {
    # shellcheck disable=SC2016
    t_log "installing hooks in $(__t_rcfile)"
    if ! grep '. $HOME/.trc/tasklib.sh' "$(__t_rcfile)" > /dev/null
    then
	{
	    echo "# source tasklib.sh - task utilities";
	    # shellcheck disable=SC2016
	    echo '. $HOME/.trc/tasklib.sh';
	} >> "$(__t_rcfile)"
    fi

    if ! grep 't_rcinit' "$(__t_rcfile)" > /dev/null
    then
	echo "t_rcinit" >> "$(__t_rcfile)"
    fi
}

t_help() {
    cat <<_EOF_
tasklib.sh functions --
  t_new [options...] <task-name> - create a new task.

    This creates a new task by creating the task directory layout and
    sourcing the rc file in $HOME/.trc/create, and entering the new
    task with t_enter.

    each option is stripped of initial dashes and exported in the
    local ticket rc file so that when you enter the ticket those env
    vars are created.

    special options --

    flavor -- if --flavor=<flavor> is passed then the ticket rc file
    will also source the rcfile for the flavor in
    $HOME/.trc/flavors/<flavor> on entry.


  t_enter <task-name> - enters the task.


  t_shell <task-name> - enters the task in a new subshell.


  t_worktree <repository> - creates a git worktree for the repository
  in the task's source folder.

_EOF_
}

# t_install installs tasklib.sh locally.
t_install() {
    t_log "installing files..."
    t_install_files "$@"
    t_install_rc "$@"
}

t_update() {
    t_err "not implemented"
}

case "$1" in
    install)
	shift
	t_install "$@"
	;;
    update)
	t_update
	;;
    *)
	;;
esac

    
