#!/bin/env sh

INITIAL_COMMIT_MSG='INITIAL_COMMIT'
AUTO_MERGE_MSG='Merge branch'

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
    git push "$push_url" refs/notes/* master gh-pages

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

    git clone "git://github.com/$1/$2.git" "$MEMORY_REPO" >> "$MEMORY_LOG"

    cd "$MEMORY_REPO"

    # enable note sharing
    git config --add remote.origin.fetch +refs/notes/*:refs/notes/*
    git branch --track gh-pages origin/gh-pages
    git pull >> "$MEMORY_LOG"

    echo "Memory repository initialized using $1/$2!"

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
    git checkout gh-pages >> "$MEMORY_LOG"
    git pull >> "$MEMORY_LOG"
    rsync -r "$MEMORY_HOME/js" "$MEMORY_HOME/css" "$MEMORY_REPO"

    # format: {hash}{link} name
    entries=`git log --pretty=tformat:'{%h}%s' -b master | grep -v "$INITIAL_COMMIT_MSG" | grep -v "$AUTO_MERGE_MSG"`

    # an array of javascript objects containing all of the commits for client-side rendering.
    # Example of an object:
    # {
    #     hash: 'asgdas1',
    #     url: 'http://some.nice.link',
    #     description: 'Link',
    #     tags: 'cool nice'
    # }
    data='var data=['

    # generate index.html
    echo '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">' > index.html
    echo '<html><head><title>Memory links!</title>' >> index.html
    echo '<script src="js/underscore-min.js"></script>' >> index.html
    echo '<script src="js/jquery-1.6.2.min.js"></script>' >> index.html
    echo '<link rel="stylesheet" type="text/css" href="css/style.css" />' >> index.html
    echo '</head><body>' >> index.html

    echo '<div id="wrap">' >> index.html
    echo '<div id="header"></div>' >> index.html
    echo '<div id="contents"><ul id="links">' >> index.html
    while read entry; do
        hash=`echo "$entry" | sed 's/{\(.*\)}{.*$/\1/'`
        echo "<li id=\"$hash\">" >> index.html

        url=`echo "$entry" | sed 's/{.*}{\(.*\)}.*/\1/'`
        description=`echo "$entry" | sed 's/.*} \(.*\)$/\1/'`
        echo "<a href=\"$url\">$description</a>" >> index.html

        # get tags for the entry
        tags=''
        # check if a note exists (hackish)
        git notes show $hash &> "$MEMORY_LOG"
        if [[ 0 -eq $? ]]; then
            alltags=`git notes show $hash`
            for t in $alltags; do
                tags="$tags,$t"
            done
            tags="${tags/,/}"
            echo "<div class=\"tags\">[$tags]</div>" >> index.html
        fi

        echo '</li>' >> index.html

        # add an object to the array (escape single quotes)
        data="$data {hash:'$hash',url:'${url//\'/\'}',description:'${description//\'/\'}',tags:'$tags'},"
    # avoid piping as otherwise `while` body will execute in a subshell
    # and variables will not be accessible after `done`
    done < <( echo "$entries" )
    echo '</ul></div></div>' >> index.html

    # append the object
    echo '<script type="text/javascript">' >> index.html
    echo "${data%%,}];" >> index.html # remove the trailing comma
    echo '</script>' >> index.html
    echo '<script src="js/view.js"></script>' >> index.html
    echo '</body></html>' >> index.html

    # perform git actions
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
    git log --pretty=tformat:'[%h] - %s @ %ai' --show-notes | grep -v "$INITIAL_COMMIT_MSG" | grep -v "$AUTO_MERGE_MSG"
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

        # enable note sharing
        git config --add remote.origin.fetch +refs/notes/*:refs/notes/*

        # create a gh-pages branch beforehand so that it wouldn't be possible
        # to push without it.
        git co -B gh-pages
        git co master

        cd - > /dev/null

    fi

    # go into the repository as git cannot operate outside of it using a path.
    cd $MEMORY_REPO

    git co master && git pull >> "$MEMORY_LOG" && git ci --allow-empty -m "$message" >> "$MEMORY_LOG"

    # go back
    cd - > /dev/null
}
