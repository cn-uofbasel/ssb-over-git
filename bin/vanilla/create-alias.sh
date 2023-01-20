#!/usr/bin/env bash
DIRNAME=$(dirname "$0")
APPEND=$DIRNAME/append.sh

STORE=$1
ALIAS=$2
KEY=$3

if [ -z "$ALIAS" ]; then
    echo "Invalid empty alias"
fi

if [ -z "$KEY" ]; then
    echo "Invalid empty key"
else
    cd $STORE
    git symbolic-ref refs/heads/$ALIAS refs/heads/$KEY
    OUTPUT="$?"
    if [ $OUTPUT ]; then
        echo "Set symbolic reference $ALIAS for branch $KEY"
    else 
        echo "Error creating symbolic reference $ALIAS for branch $KEY"
    fi
fi

