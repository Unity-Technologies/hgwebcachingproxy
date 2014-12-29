To run this test:
~/hg/tests/run-tests.py -li test-hgwebcachingproxy.t

'serve' is a requirement bug hghave is not available in $TESTDIR ...
# $ "$TESTDIR/hghave" serve || exit 80

  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > hgwebcachingproxy=
  > largefiles=
  > [largefiles]
  > usercache=/not/set
  > EOF

Test repo

  $ hg init test
  $ cd test
  $ cat >> .hg/hgrc <<EOF
  > [largefiles]
  > usercache=`pwd`/.hg/usercache
  > EOF
  $ echo f > f
  $ hg commit -qAm0
  $ echo l > l
  $ hg add --large l
  $ hg ci -qm1
  $ hg serve -p $HGPORT -d --pid-file=../hg1.pid -E ../server-error.log \
  >   --config web.push_ssl=False --config web.allow_push=*
  $ cd ..

Allow caching of test repo - create empty repo in its place
(configure custom usercache to test that largefiles really are transferred)

  $ mkdir $TESTTMP/proxycache
  $ hg init $TESTTMP/proxycache # repo in root
  $ cat >> $TESTTMP/proxycache/.hg/hgrc <<EOF
  > [largefiles]
  > usercache=$TESTTMP/proxycache/.hg/usercache
  > EOF
  $ hg proxy -p $HGPORT2 -d --pid-file=hg2.pid -E $TESTTMP/proxy-error.log \
  >   --anonymous http://localhost:$HGPORT/ $TESTTMP/proxycache \
  >   --config largefiles.usercache=$TESTTMP/proxycache/largefiles -v
  listening at http://*:$HGPORT2/ (bound to *:$HGPORT2) (glob)

  $ cat hg1.pid hg2.pid >> $DAEMON_PIDS

Helper function for keeping an eye on the proxy log

  $ showlog() { cat $TESTTMP/proxy-error.log; : > $TESTTMP/proxy-error.log; }


Clone via stream

  $ hg clone --uncompressed http://localhost:$HGPORT2/ clone-uncompressed \
  >   --config largefiles.usercache=$TESTTMP/clone-uncompressed-largefiles
  streaming all changes
  4 files to transfer, 649 bytes of data
  transferred * (glob)
  searching for changes
  no changes found
  updating to branch default
  getting changed largefiles
  1 largefiles updated, 0 removed
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog

Clone at revision

  $ hg clone http://localhost:$HGPORT2/ -r0 clone
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog
  $ cd clone
  $ cat >> .hg/hgrc <<EOF
  > [largefiles]
  > usercache=`pwd`/.hg/usercache
  > EOF

Pull all

  $ hg pull
  pulling from http://localhost:$HGPORT2/
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  (run 'hg update' to get a working copy)
  $ showlog

Update with largefiles

  $ hg up
  getting changed largefiles
  1 largefiles updated, 0 removed
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog

Push back

  $ echo >> f
  $ hg ci -qm2
  $ hg push
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  $ showlog
  $ hg push
  pushing to http://localhost:$HGPORT2/
  searching for changes
  no changes found
  [1]

Push largefile back

  $ echo >> l
  $ hg ci -m3
  $ hg push
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  $ showlog

Invalid URL

  $ hg id http://localhost:$HGPORT2/bad
  abort: HTTP Error 404: Not Found
  [255]
  $ showlog

  $ hg id http://localhost:$HGPORT2/something/..
  abort: HTTP Error 400: Bad Request
  [255]
  $ showlog

  $ hg id http://localhost:$HGPORT2/..
  abort: HTTP Error 400: Bad Request
  [255]
  $ showlog

check error log

  $ cd ..
  $ cat server-error.log
