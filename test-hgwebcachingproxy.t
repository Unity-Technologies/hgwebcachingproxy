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
  $ hg serve -p $HGPORT -d --pid-file=../hg1.pid -A $TESTTMP/server.log \
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
  $ hg proxy -p $HGPORT2 -d --pid-file=hg2.pid -A $TESTTMP/proxy.log \
  >   --anonymous http://localhost:$HGPORT/ $TESTTMP/proxycache \
  >   --config largefiles.usercache=$TESTTMP/proxycache/largefiles -v
  listening at http://*:$HGPORT2/ (bound to *:$HGPORT2) (glob)

  $ cat hg1.pid hg2.pid >> $DAEMON_PIDS

Helper function for keeping an eye on the proxy log

  $ showlog() {
  >   echo "proxy:"
  >   cut -d']' -f2-  $TESTTMP/proxy.log
  >   : > $TESTTMP/proxy.log
  >   echo "server:"
  >   cut -d']' -f2- $TESTTMP/server.log
  >   : > $TESTTMP/server.log
  > }


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
  proxy:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=branchmap HTTP/1.1" 200 -
   "GET /?cmd=stream_out HTTP/1.1" 200 -
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3Da2d542ae417acd2cb7089ef7d6ea66d09d8f74e9
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=statlfile+sha%3Dcde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
   "GET /?cmd=getlfile HTTP/1.1" 200 - x-hgarg-1:sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  server:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3D
   "GET /?cmd=getbundle HTTP/1.1" 200 - x-hgarg-1:common=0000000000000000000000000000000000000000&heads=a2d542ae417acd2cb7089ef7d6ea66d09d8f74e9
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=statlfile+sha%3Dcde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
   "GET /?cmd=getlfile HTTP/1.1" 200 - x-hgarg-1:sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5

Clone at revision

  $ hg clone http://localhost:$HGPORT2/ -r0 clone
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog
  proxy:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=lookup HTTP/1.1" 200 - x-hgarg-1:key=0
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3D
   "GET /?cmd=getbundle HTTP/1.1" 200 - x-hgarg-1:common=0000000000000000000000000000000000000000&heads=7a99bc7d64297385042c2683666eca3b4bcdbc8b
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
  server:
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
  proxy:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3D7a99bc7d64297385042c2683666eca3b4bcdbc8b
   "GET /?cmd=getbundle HTTP/1.1" 200 - x-hgarg-1:common=7a99bc7d64297385042c2683666eca3b4bcdbc8b&heads=a2d542ae417acd2cb7089ef7d6ea66d09d8f74e9
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
  server:

Update with largefiles

  $ hg up
  getting changed largefiles
  1 largefiles updated, 0 removed
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ showlog
  proxy:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=statlfile+sha%3Dcde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
   "GET /?cmd=getlfile HTTP/1.1" 200 - x-hgarg-1:sha=cde25b5e10ad99822ac2c62b8e01b4d8af3e01d5
  server:

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
  proxy:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3D524af1007f13d00d669f97853b771c2799d00964
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=branchmap HTTP/1.1" 200 -
   "GET /?cmd=branchmap HTTP/1.1" 200 -
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "POST /?cmd=unbundle HTTP/1.1" 200 - x-hgarg-1:heads=686173686564+c4d7a87b500fd624ce5956dc80a084b3fb0c5f4f
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
  server:
   "POST /?cmd=unbundle HTTP/1.1" 200 - x-hgarg-1:heads=686173686564+c4d7a87b500fd624ce5956dc80a084b3fb0c5f4f
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3Da2d542ae417acd2cb7089ef7d6ea66d09d8f74e9
   "GET /?cmd=getbundle HTTP/1.1" 200 - x-hgarg-1:common=a2d542ae417acd2cb7089ef7d6ea66d09d8f74e9&heads=524af1007f13d00d669f97853b771c2799d00964
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
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
  proxy:
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3D524af1007f13d00d669f97853b771c2799d00964
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
   "GET /?cmd=capabilities HTTP/1.1" 200 -
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3Db41fb2726e9e347f87905e11a4eb1a038a884c45
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=branchmap HTTP/1.1" 200 -
   "GET /?cmd=branchmap HTTP/1.1" 200 -
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=statlfile+sha%3D8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68
   "POST /?cmd=putlfile HTTP/1.1" 200 - x-hgarg-1:sha=8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68
   "POST /?cmd=unbundle HTTP/1.1" 200 - x-hgarg-1:heads=686173686564+347b0146adf30138db9a9136a8f854d3c3b1629d
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases
  server:
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=statlfile+sha%3D8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68
   "POST /?cmd=putlfile HTTP/1.1" 200 - x-hgarg-1:sha=8ffbefa25ca257d3f5221c6b3a5dc6a9e8fe9f68
   "POST /?cmd=unbundle HTTP/1.1" 200 - x-hgarg-1:heads=686173686564+347b0146adf30138db9a9136a8f854d3c3b1629d
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=bookmarks
   "GET /?cmd=batch HTTP/1.1" 200 - x-hgarg-1:cmds=lheads+%3Bknown+nodes%3D524af1007f13d00d669f97853b771c2799d00964
   "GET /?cmd=getbundle HTTP/1.1" 200 - x-hgarg-1:common=524af1007f13d00d669f97853b771c2799d00964&heads=b41fb2726e9e347f87905e11a4eb1a038a884c45
   "GET /?cmd=listkeys HTTP/1.1" 200 - x-hgarg-1:namespace=phases

Invalid URL

  $ hg id http://localhost:$HGPORT2/bad
  abort: HTTP Error 404: Not Found
  [255]
  $ showlog
  proxy:
   "GET /bad?cmd=capabilities HTTP/1.1" 404 -
  server:
   "GET /bad?cmd=capabilities HTTP/1.1" 404 -

  $ hg id http://localhost:$HGPORT2/something/..
  abort: HTTP Error 400: Bad Request
  [255]
  $ showlog
  proxy:
   "GET /something/..?cmd=capabilities HTTP/1.1" 400 -
  server:

  $ hg id http://localhost:$HGPORT2/..
  abort: HTTP Error 400: Bad Request
  [255]
  $ showlog
  proxy:
   "GET /..?cmd=capabilities HTTP/1.1" 400 -
  server:

check error log

  $ cd ..
