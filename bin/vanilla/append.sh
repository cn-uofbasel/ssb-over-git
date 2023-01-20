#!/usr/bin/env bash
STORE=$1
KEY=$2
CONTENT=$3

cd $STORE

KEYFOUND=$(gpg --list-keys -k $KEY)
if [ -z "$KEYFOUND" ]; then
    echo "Key '$KEY' is invalid"
    exit 1
fi

BRANCH=$(git branch --list $KEY)
if [ -z "$BRANCH" ]; then
    echo "Branch $KEY does not exist, creating"
    echo ""
    PREVIOUS=""
else
    PREVIOUS="-p refs/heads/$KEY" 
fi

COMMIT=$(echo $CONTENT | GIT_COMMITTER_NAME=$KEY GIT_COMMITTER_EMAIL="" GIT_AUTHOR_NAME=$KEY GIT_AUTHOR_EMAIL="" git commit-tree --gpg-sign=$KEY $PREVIOUS 4b825dc)
git show $COMMIT --show-signature

git update-ref refs/heads/$KEY $COMMIT
