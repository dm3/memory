#!/bin/env sh

INITIAL_COMMIT_MSG='INITIAL_COMMIT'

if [[ -z "$MEMORY_HOME" ]] || [[ -z "$MEMORY_REPO" ]] || [[ -z "$MEMORY_LOG" ]]; then
    echo "Source the .memoryrc configuration!"
    return
fi

function memory_push {
    if [[ ! -d "$MEMORY_REPO" ]]; then
        echo "Memory repository doesn't exist at $MEMORY_REPO!"
        return
    fi

    cd "$MEMORY_REPO"

    push_url=`git remote -v | grep '(push)' | awk '{print $2}' | sed 's_.*\/\(.*\/.*$\)_git@github.com:\1_'`
    git push "$push_url" --all

    cd - > /dev/null
}

function memory_github_retrieve {
    if [[ -z "$1" ]]; then
        echo "Github username must be provided as the first argument!"
        return
    fi

    if [[ -z "$2" ]]; then
        echo "Github repository name must be provided as the second argument!"
        return
    fi

    if [[ ! -d "$MEMORY_REPO" ]]; then
        echo "Creating memory at $MEMORY_REPO"
        mkdir -p "$MEMORY_REPO"
    else
        if [[ -d "$MEMORY_REPO/.git" ]]; then
            echo "Git repository already exists in $MEMORY_REPO!"
            return
        fi
    fi

    git clone "git://github.com/$1/$2.git" "$MEMORY_REPO"

    cd "$MEMORY_REPO"

    git branch --track gh-pages origin/gh-pages

    cd - > /dev/null
}

# associates existing memory repo with a github repo
function memory_github_assoc {
    if [[ ! -d "$MEMORY_REPO" ]]; then
        echo "Memory repository doesn't exist at $MEMORY_REPO!"
        return
    fi

    if [[ -z "$1" ]]; then
        echo "Github username must be provided as the first argument!"
        return
    fi

    if [[ -z "$2" ]]; then
        echo "Github repository name must be provided as the second argument!"
        return
    fi

    cd "$MEMORY_REPO"

    git remote add origin "git://github.com/$1/$2.git"

    cd - > /dev/null
}

# Generates the view in the gh_pages branch of the memory repo.
# This will have to be done in a sane language.
function memory_generate_view {
    if [[ ! -d $MEMORY_REPO ]]; then
        echo "Memory repository doesn't exist at $MEMORY_REPO!"
        return
    fi

    cd "$MEMORY_REPO"

    # gh-pages must already exist
    # It wouldn't be too hard to create it anyways, but lets not
    # allow too many options, shall we?
    if [[ -z `git branch | grep gh-pages` ]]; then
        echo "Memory repo is corrupted! No gh-pages branch exists!"
        return
    fi
    git checkout gh-pages

    entries=`git log --pretty=tformat:%s -b master | grep -v "$INITIAL_COMMIT_MSG"`

    # generate index.html
    echo "<html><head><title>Memory links!</title></head><body><table>" > index.html
    echo "$entries" | while read entry; do
        echo "<tr>" >> index.html
        url=`echo "$entry" | sed 's/{\(.*\)}.*/\1/'`
        description=`echo "$entry" | sed 's/.*} \(.*\)$/\1/'`
        echo "<td><a href=\"$url\">$description</a></td>" >> index.html
        echo "</tr>" >> index.html
    done
    echo "</table></body></html>" >> index.html
    git add . >> "$MEMORY_LOG"
    git ci -a -m 'Regenerated memory view page.' >> "$MEMORY_LOG"

    git checkout master
    cd - > /dev/null
}

# Tags are stored in git notes with each tag on a new line to leverage the
# cat_sort_uniq merge strategy.
#
# $1 - hash of the entry - mandatory
# $2..n - tags to be appended to the entry, non-unique tags will be dropped
function memory_tag {
    if [[ -z $1 ]]; then
        echo "Specify the hash of the entry!"
        return
    fi

    cd "$MEMORY_REPO"
    # get the hash of the stored entry
    entry=`git log --pretty=tformat:%H | grep "$1"`

    if [[ -z $entry ]]; then
        echo "Hash $1 doesn't exist in the memory repository!"
        return
    fi

    # get contents of the notes for the entry
    existing_note=`git notes | grep $entry | awk '{print $1}'`
    tags=''
    if [[ ! -z $existing_note ]]; then
        tags=`git show $existing_note`
    fi

    # remove the first argument (as it's a hash) and append new tags one by one
    # each on a new line
    shift
    for tag in $@; do
        tags="$tags"$'\n'"$tag"
    done

    # I tried to be clever and use git note merge -s cat_sort_uniq
    # but it didn't work as you can only merge already existing notes
    tags=`echo "$tags" | sort | uniq`

    git notes add $entry -f -m "$tags"

    cd - > /dev/null
}

function memory_view {
    if [[ ! -d $MEMORY_REPO ]]; then
        echo "Memory repository doesn't exist at $MEMORY_REPO!"
        return
    fi

    cd "$MEMORY_REPO"
    git log --pretty=tformat:'[%h] - %s @ %ai' | grep -v "$INITIAL_COMMIT_MSG"
    cd - > /dev/null
}

# $1 - URL - mandatory
function memory_store {
    if [[ -z $1 ]]; then
        echo 'Cannot store an empty URL!'
        return
    fi

    if [[ "$1" == 'http://'* ]]; then
        # check the submitted url for liveness
        curl -If "$1" &>> "$MEMORY_LOG"
        if [[ "$?" -gt 0 ]]; then
            echo "$1 seems to be offline!"
            return
        fi
    else
        echo "$1 is not an URL!"
        return
    fi

    # Description is optional
    if [[ -z $2 ]]; then
        message="{$1}"
    else
        message="{$1} $2"
    fi

    # Create a repo if it doesn't exist already
    if [[ ! -d $MEMORY_REPO ]]; then
        echo "Creating a memory repository at $MEMORY_REPO"
        git init "$MEMORY_REPO" >> "$MEMORY_LOG"
        cd "$MEMORY_REPO"
        git ci --allow-empty -m "$INITIAL_COMMIT_MSG" > "$MEMORY_LOG"

        # create a gh-pages branch beforehand so that it wouldn't be possible
        # to push without it.
        git co -B gh-pages
        git co master

        cd - > /dev/null

    fi

    # go into the repository as git cannot operate outside of it using a path.
    cd $MEMORY_REPO

    git ci --allow-empty -m "$message" >> "$MEMORY_LOG"

    # go back
    cd - > /dev/null
}
