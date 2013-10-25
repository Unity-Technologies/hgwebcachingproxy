  $ "$TESTDIR/hghave" serve || exit 80

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

  $ cat hg1.pid hg2.pid >> $DAEMON_PIDS

Helper function for keeping an eye on the proxy log

  $ showlog() { cat $TESTTMP/proxy-error.log; : > $TESTTMP/proxy-error.log; }


Clone via stream

  $ hg clone --uncompressed http://localhost:$HGPORT2/ clone-uncompressed \
  >   --config largefiles.usercache=$TESTTMP/clone-uncompressed-largefiles
  streaming all changes
  4 files to transfer, 649 bytes of data
  transferred * (glob)
  updating to branch default
  getting changed largefiles
  1 largefiles updated, 0 removed
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog
  listening at http://*:$HGPORT2/ (bound to *:$HGPORT2) (glob)
  None@/  cmd: capabilities  args: 
  None@/ - pulling
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 2 changesets with 2 changes to 2 files
  calling hook changegroup.lfiles: <function *> (glob)
  None@/  cmd: branchmap  args: 
  None@/  cmd: stream_out  args: 
  None@/  cmd: listkeys  args: namespace=bookmarks
  None@/  cmd: capabilities  args: 
  None@/  cmd: batch  args: cmds=statlfile sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  None@/ - fetching cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store
  None@/  cmd: getlfile  args: sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store

Clone at revision

  $ hg clone http://localhost:$HGPORT2/ -r0 clone
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog
  None@/  cmd: capabilities  args: 
  None@/  cmd: lookup  args: key=0
  None@/  cmd: batch  args: cmds=lheads ;known nodes=
  None@/  cmd: getbundle  args: common=0000000000000000000000000000000000000000 heads=7a99bc7d64297385042c2683666eca3b4bcdbc8b
  1 changesets found
  None@/  cmd: listkeys  args: namespace=phases
  None@/  cmd: listkeys  args: namespace=bookmarks
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
  None@/  cmd: capabilities  args: 
  None@/  cmd: listkeys  args: namespace=bookmarks
  None@/  cmd: batch  args: cmds=lheads ;known nodes=7a99bc7d64297385042c2683666eca3b4bcdbc8b
  None@/  cmd: getbundle  args: common=7a99bc7d64297385042c2683666eca3b4bcdbc8b heads=a2d542ae417acd2cb7089ef7d6ea66d09d8f74e9
  1 changesets found
  None@/  cmd: listkeys  args: namespace=phases

Update with largefiles

  $ hg up
  getting changed largefiles
  1 largefiles updated, 0 removed
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog
  None@/  cmd: capabilities  args: 
  None@/  cmd: batch  args: cmds=statlfile sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store
  None@/  cmd: getlfile  args: sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store
  found cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5 in store

Push back

  $ echo >> f
  $ hg ci -qm2
  $ hg push
  pushing to http://localhost:$HGPORT2/
  searching for changes
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  $ showlog
  None@/  cmd: capabilities  args: 
  None@/  cmd: batch  args: cmds=lheads ;known nodes=524af1007f13d00d669f97853b771c2799d00964
  None@/  cmd: batch  args: cmds=lheads ;known nodes=524af1007f13d00d669f97853b771c2799d00964
  None@/  cmd: branchmap  args: 
  None@/  cmd: branchmap  args: 
  None@/  cmd: listkeys  args: namespace=bookmarks
  None@/  cmd: unbundle  args: heads=686173686564 c4d7a87b500fd624ce5956dc80a084b3fb0c5f4f
  calling unbundle remotely
  searching for changes
  all local heads known remotely
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  calling hook changegroup.lfiles: <function checkrequireslfiles at *> (glob)
  None@/  cmd: listkeys  args: namespace=phases
  None@/  cmd: listkeys  args: namespace=bookmarks
  $ hg push
  pushing to http://localhost:$HGPORT2/
  searching for changes
  searching for changes
  no changes found
  [1]

Push largefile back

  $ echo >> l
  $ hg ci -m3
  $ hg push
  pushing to http://localhost:$HGPORT2/
  searching for changes
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
  $ showlog
  None@/  cmd: capabilities  args: 
  None@/  cmd: batch  args: cmds=lheads ;known nodes=524af1007f13d00d669f97853b771c2799d00964
  None@/  cmd: batch  args: cmds=lheads ;known nodes=524af1007f13d00d669f97853b771c2799d00964
  None@/  cmd: listkeys  args: namespace=phases
  None@/  cmd: listkeys  args: namespace=bookmarks
  None@/  cmd: capabilities  args: 
  None@/  cmd: batch  args: cmds=lheads ;known nodes=b41fb2726e9e347f87905e11a4eb1a038a884c45
  None@/  cmd: batch  args: cmds=statlfile sha=8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68
  None@/ - 8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68 not available remotely
  None@/  cmd: putlfile  args: sha=8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68
  calling putlfile remotely
  None@/  cmd: batch  args: cmds=lheads ;known nodes=b41fb2726e9e347f87905e11a4eb1a038a884c45
  None@/  cmd: branchmap  args: 
  None@/  cmd: branchmap  args: 
  None@/  cmd: listkeys  args: namespace=bookmarks
  None@/  cmd: unbundle  args: heads=686173686564 347b0146adf30138db9a9136a8f854d3c3b1629d
  calling unbundle remotely
  searching for changes
  all local heads known remotely
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  calling hook changegroup.lfiles: <function checkrequireslfiles at *> (glob)
  None@/  cmd: listkeys  args: namespace=phases
  None@/  cmd: listkeys  args: namespace=bookmarks

Invalid URL

  $ hg id http://localhost:$HGPORT2/bad
  abort: HTTP Error 404: Not Found
  [255]
  $ showlog
  None@bad  cmd: capabilities  args: 
  error with path 'bad': repository $TESTTMP/proxycache/bad not found

  $ hg id http://localhost:$HGPORT2/something/..
  abort: HTTP Error 400: Bad Request
  [255]
  $ showlog
  bad request path 'something/..'

  $ hg id http://localhost:$HGPORT2/..
  abort: HTTP Error 400: Bad Request
  [255]
  $ showlog
  bad request path '..'

check error log

  $ cd ..
  $ cat server-error.log
