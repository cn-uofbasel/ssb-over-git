# SSB over Git

**SSB over Git** aims at simplifying the exploration of potential applications
that may benefit from a replication strategy based on directed-acyclic graphs
in order to be resilient to forked logs in the exceptional cases, while keeping
as many of the benefits of append-only logs in the correct and common case.
Hopefully, that will help inform future developments of SSB.

This project is built by analogy: we map the core concepts of SSB and
application-building conventions onto Git. Since Git is more general,
this is done by using the core plumbing primitives of Git and constraining
what operations are possible to obtain similar properties as those obtained
with append-only logs in SSB.

## Dependencies

Tested with:

* [GPG](https://www.gnupg.org/) >= 2.3.8
* [Git](https://git-scm.com/) >= 2.24.3 

If you succeed in replicating experiments with older versions,
make a Pull-Request with the version you tested.

## References

We use the terminology introduced [here](https://dl.acm.org/doi/abs/10.1145/3428662.3428794)
to map the different SSB concepts to Git primitives. Details on the SSB protocol are summarized
in this [guide](https://ssbc.github.io/scuttlebutt-protocol-guide). The git basic concepts
are covered in the so-called "plumbing"
[documentation](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain).

## Overview

We present our approach in 3 parts:
1. [Vanilla SSB](#1-vanilla-ssb): Replication of SSB's behaviour in Git
2. [Forking Problem](#2-the-problem-of-forks): We show how forks break eventual consistency
3. [Tolerating Forks](#3-tolerating-forks): We show how to replicate then detect forks

# 1. Vanilla SSB  

We first replicate the basic functionalities of SSB: 
1. [Identity](#identity)
2. [Store](#store)
3. [Signed message](#signed-message)
4. [Self-Certifying Log](#self-certifying-log) 
5. [Replication](#replication)
6. [Deletion](#deletion)

## Identity

Create an ed25519 identity with GPG:

````bash
   $ gpg --full-generate-key
````

Select `ECC (sign and encrypt)`, then `Curve 25519`. Other options depend on your personal circumstances.
Note the public key in the output. Example:

````bash
  pub   ed25519 2020-07-18 [SC] [expires: 2021-07-18]
        CE44B3CFC4C68B868A7AE868D87953FAD4BB4EC4
````

The public key in the example is `CE44..4EC4`. 

To make the following steps easier to follow, let's create 3 identities for
fictive participants: Bob, Alice and Eve. For each, redo the steps above and
assign their public key to a shell variable. For example, in the case of Bob
using the previous public key:

````bash
  $ export BOB=CE44B3CFC4C68B868A7AE868D87953FAD4BB4EC4;
```` 

In your case, replace the public key in with those generated locally by gpg.

## Store

A store is the local database in which we will store the logs. Using Git this
is a regular repository. Create one for Bob:

````
 $ mkdir bob-store 
 $ cd bob-store
 $ git init .
````

## Signed Message

A SSB message is similar to a signed Git commit in that it has the following properties:
1. `previous`: reference to a previous message (respectively commit)
2. `author`:  public key of the author (respectively author name, email, public key)
3. `sequence`: sequence number of the message (respectively no sequence number because Git supports more than logs)
4. `timestamp`: date-time at which the author claims to have created the message (idem)
5. `content`: string with maximum size of 8,192 Bytes (respectively commit
   message with upper bound 
   [implementation-specific](https://stackoverflow.com/questions/9733757/maximum-commit-message-size))
5. `signature`: ed25519 signature of 1-5 (respectively 1-2 + 4-5) 

Similar to a Git commit, a SSB message is identitied by the SHA hash of its
content, but uses SHA-256 instead of SHA-1. Git is [transitioning to use
SHA-256 as well](https://git-scm.com/docs/hash-function-transition/).
For presentation simplicity, in this document we simply just use
the default SHA-1 of Git. 

### Ignoring trees

Git commits require a valid tree reference so we use an empty tree for all
SSB messages. To obtain the reference to the empty tree, we simply write the
tree corresponding to the staging index (which should currently be empty):

````bash
  $ git write-tree
  4b825dc642cb6eb9a060e54bf8d69288fbee4904 
````

We can later refer to empty tree by the first hex characters `4b825dc`.

### Signing our first message

We create a signed message as a (detached) commit:

````bash
  $ FIRSTCOMMIT=$(echo 'First message' | GIT_COMMITTER_NAME=$BOB GIT_AUTHOR_NAME=$BOB git commit-tree 4b825dc --gpg-sign=$BOB)
````

The message content could also have been a valid JSON object.

## Self-Certifying Log

We now assign our first commit as the initial message of a log, using a Git
branch reference. We make that reference self-certifying by using the public key of 
the author as value:

````bash
  $ git update-ref refs/heads/$BOB $FIRSTCOMMIT
````

It is now listed as a branch:

````bash
  $ git branch
````

Git should display Bob's public key (`$BOB`).

To make things more convenient we also create a symbolic link to be able to use
a shorter and more memorable name:

````bash
  $ git symbolic-ref refs/heads/bob-frontier refs/heads/$BOB
````

We can also verify that Bob's log is consistent with their public key:

````bash
  $ git log --show-signature bob-frontier
````

### Append

We can now append a second message to Bob's log:

````bash
  $ SECONDCOMMIT=$(echo 'Second message' | GIT_COMMITTER_NAME=$BOB GIT_AUTHOR_NAME=$BOB git commit-tree --gpg-sign=$BOB -p bob-frontier)
  $ git update-ref refs/heads/$BOB $SECONDCOMMIT
````

Because `bob-frontier` is a symbolic reference, it now transitively points to `$SECONDCOMMIT`.

### List

We can list the Bob's messages from newest to oldest:

````bash
  $ git log --topo-order bob-frontier
````

We can list the same messages from oldest to newest (as is more common in SSB):

````bash
  $ git log --topo-order --reverse bob-frontier
````

We can also extract only the log's content:

````bash
  $ git log --topo-order --reverse --format=%s bob-frontier
````

## Replication

First, create a replica for Alice:

````bash
  $ cd ../
  $ mkdir alice-store
  $ cd alice-store
  $ git init .
  $ git write-tree
````

Pull the latest updates of Bob from Bob's store:

````bash
  $ git pull ../bob-store refs/heads/$BOB":"refs/heads/$BOB
````

Bob can also push his updates to Alice's store:

````bash
  $ cd ../bob-store
  $ git push ../alice-store bob-frontier":"refs/heads/$BOB
````

### Replication without connection

If Bob cannot directly access Alice's store, he can instead
package the updates into a bundle and send them through other
means (sneakernet, email, broadcast, etc.):

````bash
  $ git bundle create bob.updates refs/heads/$BOB # From bob-store
  $ cp bob.updates ../alice-store
````

Alice can then fetch the updates from the bundle:
````bash
  $ cd ../alice-store
  $ git fetch bob.updates refs/heads/$BOB":"refs/heads/$BOB
```` 

If Bob knows that Alice's store already possess updates up to
`BOB_FRONTIER_AT_ALICE`, Bob can create a smaller bundle with only the newer
updates:

````bash
  $ cd ../bob-store
  $ git bundle create bob.updates refs/heads/$BOB_FRONTIER_AT_ALICE".."refs/heads/$BOB
````

## Deletion

The messages of a log can be easily deleted from a store simply by removing all references to them then garbage collecting
the store:

````bash
  $ cd ../alice-store
  $ LAST=$(git show refs/heads/$BOB --format=%H) # store last commit hash
  $ git show $LAST
  $ git checkout --orphan temp                   # move to a temporary branch with no commits
  $ git branch -D $BOB                           # delete ref refs/heads/$BOB and logs/refs/heads/$BOB
  $ git gc --prune=now                           # Remove now unreachable objects (garbage collect)
  $ git show $LAST                               # Should return: "fatal: bad object ..."
````

Depending on the prior history of operations on the Git repository, there might still be references in git internals
 (ex: `.git/logs/HEAD`, `reflog`, `.git/FETCH_HEAD`, `.git/ORIG_HEAD`, etc) which prevent some deletion. These 
require a more careful cleanup. Once all references are removed, `git gc` will then remove the objects from the object 
database (`.git/objects`).


# 2. The Problem of Forks

Replication of updates, by push or pull, can happen between any pair of replicas as long as the following invariants are maintained:
1. **Single-writer**: All commits reachable from the frontier of an author (`refs/heads/KEY`) shall be from the same author. This restriction is necessary because Git does not prevent another author from appending to a log and having a reference that points to that new commit.
3. **No fork**: No two commits reachable from any frontier, shall have the same parent commit. In other words,
                the commit history should form a strict linked-list.
                
This will guarantee eventual consistency between all replicas. In effect, the absence of forks enables the fast-forwarding replication mode of Git for all updates.

However, in the presence of incorrect or malicious participants, we cannot assume that they will maintain those properties as they might deviate arbitrarily from the expected protocol. For example, Eve might maintain one different log for each participant she is interacting with so that each of them thinks they are interacting with a valid log. 

Let's see how this may play out with Git. For convenience, rather than retyping the full commands shown previously, we will use the following equivalent [helper scripts](./bin):
1. ```bin/vanilla/create-store.sh PATH```: create a store at `PATH`
2. ```bin/vanilla/append.sh STORE KEY CONTENT```: append `CONTENT` in `KEY` log within `STORE`

First, create a store for Eve:
````bash
  $ bin/vanilla/create-store.sh eve-store
````

Then create a first message for Eve:
````bash
  $ bin/vanilla/append.sh eve-store $EVE 'First Message'
````

Now create one message intended for Bob:
````bash
  $ bin/vanilla/append.sh eve-store $EVE 'Message for Bob'
````

Track the log specifically for Bob:
````bash
  $ cd eve-store
  $ git update-ref refs/heads/Eve-for-Bob refs/heads/$EVE
````

Rewind Eve's log to the parent commit:
````bash
  $ git update-ref refs/heads/$EVE $(git rev-parse refs/heads/$EVE~1)
````

Append a new message intended for Alice:
````bash
  $ cd ..
  $ bin/vanilla/append.sh eve-store $EVE 'Message for Alice'
````

Track the additional log specifically for Alice:
````bash
  $ cd eve-store
  $ git update-ref refs/heads/Eve-for-Alice refs/heads/$EVE
````

Now Eve can push different logs to Bob and Alice:
````bash
  $ git push ../bob-store refs/heads/Eve-for-Bob":"refs/heads/$EVE
  $ git push ../alice-store refs/heads/Eve-for-Alice":"refs/heads/$EVE
````

From within Bob's store or Alice's store, the log satisfies the single-write and no-fork properties:
````bash
  $ cd ../bob-store
  $ git log refs/heads/$EVE --topo-order --show-signature
  $ cd ../alice-store
  $ git log refs/heads/$EVE --topo-order --show-signature
````

If Eve had written that she was giving the same tokens to both Bob and Alice, both would now think they 
are the legitimate owner and Eve would have successfully double-spent the tokens. Moreover, the 
situation breaks eventual consistency because it is not possible for both Bob and Alice
to obtain a correct log that is consistent between both of their stores. This also
breaks the possibility to propagate Eve's updates directly between Bob and Alice, which 
effectively partitions the rest of the community according to which branch of the forked log 
they have first updated from:
````bash
  $ git pull ../bob-store refs/heads/$EVE":"refs/heads/$EVE # from alice-store
  From ../bob
  ! [rejected]        07318BA3E8FC2BBD468BC405A32F064B8DE7C8FF -> 07318BA3E8FC2BBD468BC405A32F064B8DE7C8FF  (non-fast-forward)
````


# 3. Tolerating Forks

## Replicating Forks

At the very minimum we would like to be able to at least replicate all branches of forks. These can be stored, for example, 
under where we got them from:

````bash
  $ # From alice-store:
  $ git update-ref refs/remotes/eve-store/$EVE refs/heads/$EVE # Remember we got these updates from Eve
  $ git fetch ../bob-store refs/heads/$EVE":"refs/remotes/bob-store/$EVE
````

## Detecting Forks

We can test whether multiple log replicas are actually branches by counting how many of the branches' tips cannot be reached from another. If 
the number is greater than 1 then there are as many branches:
````bash
  $ git merge-base --independent $(git for-each-ref "refs/remotes/*/$EVE" --format="%(refname)") | wc -l
````

There is also a nice visualization option for branches:
````bash
  $ git log refs/remotes/eve-store/$EVE refs/remotes/bob-store/$EVE --graph --format=oneline
````

# References

1. Signing Git Commits with a SSH Key: https://calebhearth.com/sign-git-with-ssh, https://git-scm.com/docs/git-config#Documentation/git-config.txt-gpgprogram
2. Signing Git Commits with GPG: https://mdleom.com/blog/2020/07/18/git-sign-commit-ed25519/
3. Git transition plan to SHA256: https://git-scm.com/docs/hash-function-transition/
4. Show disk usage for branches (Git >=2.31): https://github.com/git/git/commit/16950f8384afa5106b1ce57da07a964c2aaef3f7
5. Latency numbers every programmer should know: https://gist.github.com/jboner/2841832
6. Determining Updates to Transmit through a Connected Channel: 
    1. Packfile Negotiation: https://git-scm.com/docs/pack-protocol/2.2.3#_packfile_negotiation
    2. Git Protocol v2: https://opensource.googleblog.com/2018/05/introducing-git-protocol-version-2.html
    3. Background Maintenance: https://git-scm.com/docs/git-maintenance
7. Git Internals: [Packed Object Store](https://github.blog/2022-08-29-gits-database-internals-i-packed-object-store/), [Commit History Queries](https://github.blog/2022-08-30-gits-database-internals-ii-commit-history-queries/), [File History Queries](https://github.blog/2022-08-31-gits-database-internals-iii-file-history-queries/), [Distributed Synchronization](https://github.blog/2022-09-01-gits-database-internals-iv-distributed-synchronization/), [Scalability](https://github.blog/2022-09-02-gits-database-internals-v-scalability/)
    1. Internal use of Vector Clocks (Corrected Commit Date): https://github.blog/2022-08-30-gits-database-internals-ii-commit-history-queries/#generation-number-v2-corrected-commit-dates
    2. Bloom Filters for File Path Changes: https://github.blog/2022-08-31-gits-database-internals-iii-file-history-queries/#changed-path-bloom-filters
  


