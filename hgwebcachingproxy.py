# caching HTTP proxy for hgweb
#
# Copyright Unity Technologies, Mads Kiilerich <madski@unity3d.com>
# Copyright Matt Mackall <mpm@selenic.com> and others
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.

'''Caching HTTP proxy for hgweb hosting

This proxy can serve as an "accelerator" or "concentrator" that might reduce
the network traffic and improve the user experience where the bandwidth is
limited and the same data is fetched multiple times.

Enable the extension with::

  [extensions]
  hgwebcachingproxy = /path/to/hgwebcachingproxy.py

For light-weight usage or testing run the proxy similar to :hg:`serve`::

  hg proxy --port 1234 http://servername/ /var/cache/hgrepos

Instead of pointing Mercurial clients at::

  http://servername/repos/name

point them at the proxy:

  http://proxyname:1234/repos/name

The proxy will make sure its local cache of the repository is fully updated
when starting a new session. Sessions are defined by the repository name,
username and credentials, and they expire after 30 seconds
(``[hgwebcachingproxy] ttl``) without usage. All read-only requests within a
session will be served locally. Pushes will be forwarded straight to the main
server, and, after pushing, the proxy will do a pull to make sure the mirror is
up-to-date. Largefiles will be fetched and cached on demand.

Only repos that already exist in the local cache will be served. The cache must
thus manually be seeded with repositories that is to be served - either with a
new or existing clone or an empty repo which will then be populated on first
request.

The proxy will by default assume that the server uses HTTP basic authentication
(unless ``[hgwebcachingproxy] anonymous`` is true). If no credentials are
provided they will be requested using (using ``[hgwebcachingproxy] realm``) to
avoid slow extra round trips to the server. All credentials for access to a
repository will be forwarded to the server for authentication and
authorization. The server will not be aware of the actual requests that are
served from the local cache and its logs will thus not be fully accurate.

The URL of the server can also be configured as ``[hgwebcachingproxy]
serverurl``, and the path to the cached repositories can be configured in
``[hgwebcachingproxy] cachepath``.

For usage as WSGI application create a proxy.wsgi with configuration::

    import sys; sys.path.insert(0, '/path/to/hg/')
    from hgext.hgwebcachingproxy import wsgi
    application = wsgi(serverurl='https://.../', cachepath='/path/to/repos/')

In an apache mod_wsgi configuration this proxy.wsgi can be used like::

    WSGIPassAuthorization On
    WSGIScriptAlias / /path/to/proxy.wsgi
'''

import os.path
import urllib2, posixpath, time
from mercurial import cmdutil, util, commands, hg, error
from mercurial import ui as uimod
from mercurial.hgweb import protocol, common, request
from mercurial.i18n import _
from hgext.largefiles import lfutil, basestore

cmdtable = {}
command = cmdutil.command(cmdtable)
testedwith = '2.8'

commands.norepo += " proxy"

# username,passwd,path mapping to peer
peercache = dict()

class proxyserver(object):
    def __init__(self, ui, serverurl, cachepath, anonymous):
        self.ui = ui or uimod.ui()
        self.serverurl = (serverurl or
                          self.ui.config('hgwebcachingproxy', 'serverurl'))
        self.cachepath = (cachepath or
                          self.ui.config('hgwebcachingproxy', 'cachepath'))
        if anonymous is None:
            anonymous = self.ui.configbool('hgwebcachingproxy', 'anonymous')
        self.anonymous = anonymous

        if not self.serverurl:
            raise util.Abort(_('no server url'))
        u = util.url(self.serverurl)
        if u.scheme not in ['http', 'https']:
            raise util.Abort(_('invalid scheme in server url %s') % serverurl)

        if not self.cachepath or not os.path.isdir(self.cachepath):
            raise util.Abort(_('cache path %s is not a directory') %
                             self.cachepath)
        self.ttl = self.ui.configint('hgwebcachingproxy', 'ttl', 30)
        self.authheaders = [('WWW-Authenticate',
                             'Basic realm="%s"' %
                             self.ui.config('hgwebcachingproxy', 'realm',
                                            'Mercurial Proxy Authentication'))]

    def __call__(self, env, respond):
        req = request.wsgirequest(env, respond)
        return self.run_wsgi(req)

    def run_wsgi(self, req):
        proto = protocol.webproto(req, self.ui)

        u = util.url(self.serverurl)

        # Simple path validation - probably only sufficient on Linux
        path = req.env['PATH_INFO'].replace('\\', '/').strip('/')
        if ':' in path or path.startswith('.') or '/.' in path:
            self.ui.warn(_('bad request path %r\n') % path)
            req.respond(common.HTTP_BAD_REQUEST, protocol.HGTYPE)
            return []

        # Forward HTTP basic authorization headers through the layers
        authheader = req.env.get('HTTP_AUTHORIZATION')
        if authheader and authheader.lower().startswith('basic '):
            userpasswd = authheader[6:].decode('base64')
            if ':' in userpasswd:
                u.user, u.passwd = userpasswd.split(':', 1)

        # Bounce early on missing credentials
        if not (self.anonymous or u.user and u.passwd):
            er = common.ErrorResponse(common.HTTP_UNAUTHORIZED,
                                      'Authentication is mandatory',
                                      self.authheaders)
            req.respond(er, protocol.HGTYPE)
            return ['HTTP authentication required']

        # MIME and HTTP allows multiple headers by the same name - we only
        # use and care about one
        args = dict((k, v[0]) for k, v in proto._args().items())
        cmd = args.pop('cmd', None)
        self.ui.write("%s@%s  cmd: %s  args: %s\n" %
                      (u.user, path or '/', cmd, ' '.join('%s=%s' % (k, v)
                       for k, v in sorted(args.items()))))

        if not cmd:
            self.ui.warn(_('no command in request\n'))
            req.respond(common.HTTP_BAD_REQUEST, protocol.HGTYPE)
            return []

        u.path = posixpath.join(u.path or '', req.env['PATH_INFO']).strip('/')
        url = str(u)

        repopath = os.path.join(self.cachepath, path)
        try:
            repo = hg.repository(self.ui, path=repopath)
        except error.RepoError, e:
            self.ui.warn(_("error with path %r: %s\n") % (path, e))
            req.respond(common.HTTP_NOT_FOUND, protocol.HGTYPE)
            return ['repository %s not found in proxy' % path]
        path = path or '/'

        try:
            # Reuse auth if possible - checking remotely is expensive
            peer, ts = peercache.get((u.user, u.passwd, path), (None, None))
            if peer is not None and time.time() > ts + self.ttl:
                self.ui.note(_('%s@%s expired, age %s\n') %
                             (u.user, path, time.time() - ts))
                peer = None
                peercache[(u.user, u.passwd, path)] = (peer, ts)
            # peer is now None or valid

            if cmd == 'capabilities' and not peer:
                # new session on expired repo - do auth and pull again
                self.ui.note(_('%s@%s - pulling\n') % (u.user, path))
                t0 = time.time()
                peer = hg.peer(self.ui, {}, url)
                r = repo.pull(peer)
                self.ui.debug('pull got %r after %s\n' % (r, time.time() - t0))
                peercache[(u.user, u.passwd, path)] = (peer, time.time())
            elif ts is None: # never authenticated
                self.ui.note('%s@%s - authenticating\n' % (u.user, path))
                peer = hg.peer(self.ui, {}, url)
                self.ui.debug('%s@%s - authenticated\n' % (u.user, path))
                peercache[(u.user, u.passwd, path)] = (peer, time.time())
            # user is now auth'ed for this session

            # fetch largefiles whenever they are referenced
            # (creating fake/combined batch statlfile responses is too complex)
            shas = []
            if cmd in ['statlfile', 'getlfile']:
                shas.append(args['sha'])
            if cmd == 'batch':
                for x in args['cmds'].split(';'):
                    if x.startswith('statlfile sha='):
                        shas.append(x[14:])
            missingshas = [sha for sha in shas
                           if not lfutil.findfile(repo, sha)]
            if missingshas:
                self.ui.debug('%s@%s - missing %s\n' %
                              (u.user, path, ' '.join(missingshas)))
                if not peer:
                    peer = hg.peer(self.ui, {}, url)
                store = basestore._openstore(repo, peer, False)
                existsremotely = store.exists(missingshas)
                for sha, available in sorted(existsremotely.iteritems()):
                    if not available:
                        self.ui.note('%s@%s - %s not available remotely\n' %
                                     (u.user, path, sha))
                        continue
                    self.ui.note('%s@%s - fetching %s\n' % (u.user, path, sha))
                    gotit = store._gethash(sha, sha)
                    if not gotit:
                        self.ui.warn(_('failed to get %s for %s@%s remotely\n'
                                       ) % (sha, u.user, path))
                peercache[(u.user, u.passwd, path)] = (peer, time.time())

            # Forward write commands to the remote server
            if cmd in ['putlfile', 'unbundle', 'pushkey']:
                size = int(req.env.get('CONTENT_LENGTH', 0))
                self.ui.debug('reading bundle with size %s\n' % size)
                data = req.read(int(size))

                if not peer:
                    peer = hg.peer(self.ui, {}, url)
                self.ui.note(_('calling %s remotely\n') % cmd)
                r = peer._call(cmd, data=data, **args)
                if cmd == 'unbundle':
                    self.ui.debug('fetching changes back\n')
                    repo.pull(peer)
                peercache[(u.user, u.passwd, path)] = (peer, time.time())
                req.respond(common.HTTP_OK, protocol.HGTYPE)
                return [r]

            # Now serve it locally
            return protocol.call(repo, req, cmd)

        except urllib2.HTTPError, inst:
            self.ui.warn(_('HTTPError connecting to server: %s\n') % inst)
            req.respond(inst.code, protocol.HGTYPE)
            return ['HTTP error']
        except util.Abort, e: # hg.peer will abort when it gets 401
            if e.message not in ['http authorization required',
                                 'authorization failed']:
                raise
            self.ui.debug('server requires authentication\n')
            er = common.ErrorResponse(
                common.HTTP_UNAUTHORIZED
                if e.message == 'http authorization required'
                else common.HTTP_BAD_REQUEST,
                'Authentication is required',
                self.authheaders)
            req.respond(er, protocol.HGTYPE)
            return ['HTTP authentication required']


@command('^proxy',
    [('A', 'accesslog', '', _('name of access log file to write to'),
     _('FILE')),
    ('d', 'daemon', None, _('run server in background')),
    ('', 'daemon-pipefds', '', _('used internally by daemon mode'), _('NUM')),
    ('E', 'errorlog', '', _('name of error log file to write to'), _('FILE')),
    # use string type, then we can check if something was passed
    ('p', 'port', '', _('port to listen on (default: 8000)'), _('PORT')),
    ('a', 'address', '', _('address to listen on (default: all interfaces)'),
     _('ADDR')),
    ('', 'prefix', '', _('prefix path to serve from (default: server root)'),
     _('PREFIX')),
    ('', 'pid-file', '', _('name of file to write process ID to'), _('FILE')),
    ('6', 'ipv6', None, _('use IPv6 in addition to IPv4')),
    ('', 'certificate', '', _('SSL certificate file'), _('FILE')),
    ('', 'anonymous', None, _("authentication is not mandatory"))],
    _('[OPTIONS]... SERVERURL CACHEPATH'))
def proxy(ui, serverurl, cachepath, **opts):
    """start stand-alone caching hgweb proxy

    Start a local HTTP server that acts as a caching proxy for a remote
    server SERVERURL. Fetched data will be stored locally in the directory
    CACHEPATH and reused for future requests for the same data.

    By default, the server logs accesses to stdout and errors to
    stderr. Use the -A/--accesslog and -E/--errorlog options to log to
    files.

    To have the server choose a free port number to listen on, specify
    a port number of 0; in this case, the server will print the port
    number it uses.

    See :hg:`hg help hgwebcachingproxy` for more details.

    Returns 0 on success.
    """
    if opts.get('port'):
        opts['port'] = util.getport(opts.get('port'))

    optlist = ("address port prefix ipv6 accesslog errorlog certificate")
    for o in optlist.split():
        val = opts.get(o, '')
        if val not in (None, ''):
            ui.setconfig("web", o, val)

    app = proxyserver(ui, serverurl, cachepath, opts.get('anonymous'))
    service = commands.httpservice(ui, app, opts)
    cmdutil.service(opts, initfn=service.init, runfn=service.run)

def wsgi(ui=None, serverurl=None, cachepath=None, anonymous=None):
    return proxyserver(ui, serverurl, cachepath, anonymous)
