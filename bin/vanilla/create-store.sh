#!/usr/bin/env bash
STORENAME=$1
mkdir -p $STORENAME
cd $STORENAME 
git init .
git write-tree >/dev/null
