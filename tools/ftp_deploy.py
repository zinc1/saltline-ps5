#!/usr/bin/env python3
"""Recursively upload a folder to the PS5 FTP server (anonymous, port 2121)."""
import ftplib, os, sys

host = os.environ.get('PS5_HOST')
if not host:
    raise SystemExit('set PS5_HOST to the console address')
port = int(os.environ.get('PS5_PORT', '2121'))
local = sys.argv[1]
remote = sys.argv[2]
ftp = ftplib.FTP()
ftp.connect(host, port, timeout=30)
ftp.login()

def ensure(path):
    parts = [p for p in path.split('/') if p]
    cur = ''
    for p in parts:
        cur += '/' + p
        try:
            ftp.mkd(cur)
        except ftplib.error_perm as e:
            if not str(e).startswith('550'):
                raise

ensure(remote)
for base, dirs, files in os.walk(local):
    rel = os.path.relpath(base, local)
    rdir = remote if rel == '.' else remote + '/' + rel.replace(os.sep, '/')
    ensure(rdir)
    for d in dirs:
        ensure(rdir + '/' + d)
    for f in sorted(files):
        path = os.path.join(base, f)
        with open(path, 'rb') as fh:
            ftp.storbinary('STOR ' + rdir + '/' + f, fh, blocksize=256 * 1024)
        print('uploaded', rdir + '/' + f, os.path.getsize(path))
ftp.quit()
print('done')
