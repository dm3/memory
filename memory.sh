#!/bin/env sh

MEMORY_LOG='/dev/null'
MEMORY_REPO='/tmp/repo1'
MEMORY_FAKE_FILE='memory.fake'
INITIAL_COMMIT_MSG='INITIAL_COMMIT'

function memory_view {
    cd "$MEMORY_REPO"
    git log --pretty=tformat:'%s @ %ai' | grep -v "$INITIAL_COMMIT_MSG"
    cd - > /dev/null
}

function memory_store {
    # URL is mandatory as the first argument
    if [[ -e $1 ]]; then
        echo 'Cannot store an empty URL!'
        return -1
    fi

    # Description is optional
    if [[ -e $2 ]]; then
        message="{$1}"
    else
        message="{$1} $2"
    fi

    # Create a repo if it doesn't exist already
    if [[ ! -d $MEMORY_REPO ]]; then
        echo "Creating a memory repository at $MEMORY_REPO"
        git init "$MEMORY_REPO" >> "$MEMORY_LOG"
        cd "$MEMORY_REPO"
        touch "$MEMORY_FAKE_FILE"
        git add .
        git ci -a -m "$INITIAL_COMMIT_MSG" > "$MEMORY_LOG"
        cd - > /dev/null
    fi

    # go into the repository as git cannot operate outside of it using a path.
    cd $MEMORY_REPO

    # the easiest way to fool git into allowing an "empty" commit
    # need to look into a better way.
    echo 'a' >> "$MEMORY_FAKE_FILE"

    git ci -a -m "$message" > "$MEMORY_LOG"

    # go back
    cd - > /dev/null
}
