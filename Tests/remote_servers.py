#!/usr/bin/env python3
"""Optional end-to-end tests. Dependencies are test-only: paramiko, pyftpdlib.
Runs ephemeral loopback servers and the already-compiled RemoteServiceTests.
Never reads the user's SSH keys, Keychain, or server profiles.
"""
import json
import datetime
import ipaddress
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
import logging
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import paramiko
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler, TLS_FTPHandler
from pyftpdlib.servers import FTPServer

logging.disable(logging.CRITICAL)
PASSWORD = 'test-only "password" \\ value'

class Auth(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if username == 'demo' and password == PASSWORD else paramiko.AUTH_FAILED
    def get_allowed_auths(self, username): return 'password'
    def check_channel_request(self, kind, chanid): return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

class Files(paramiko.SFTPServerInterface):
    def __init__(self, server, root, **kwargs): super().__init__(server, **kwargs); self.root = Path(root).resolve()
    def path(self, path):
        candidate = (self.root / path.lstrip('/')).resolve()
        candidate.relative_to(self.root)
        return candidate
    def list_folder(self, path):
        try:
            result=[]
            for child in self.path(path).iterdir():
                attr=paramiko.SFTPAttributes.from_stat(child.lstat()); attr.filename=child.name; result.append(attr)
            return result
        except OSError as e: return paramiko.SFTPServer.convert_errno(e.errno)
    def stat(self, path):
        try: return paramiko.SFTPAttributes.from_stat(self.path(path).stat())
        except OSError as e: return paramiko.SFTPServer.convert_errno(e.errno)
    lstat=stat
    def open(self, path, flags, attr):
        try:
            descriptor=os.open(self.path(path), flags, 0o600)
            mode='r+b' if flags & os.O_RDWR else ('wb' if flags & os.O_WRONLY else 'rb')
            file=os.fdopen(descriptor, mode)
            handle=paramiko.SFTPHandle(flags)
            if flags & os.O_WRONLY or flags & os.O_RDWR: handle.writefile=file
            if not flags & os.O_WRONLY: handle.readfile=file
            return handle
        except OSError as e: return paramiko.SFTPServer.convert_errno(e.errno)
    def chattr(self, path, attr):
        try: paramiko.SFTPServer.set_file_attr(str(self.path(path)), attr); return paramiko.SFTP_OK
        except OSError as e: return paramiko.SFTPServer.convert_errno(e.errno)


def main():
    if len(sys.argv) != 3: raise SystemExit('Usage: remote_servers.py PATH_TO_REMOTE_TESTS PATH_TO_ASKPASS_HELPER')
    binary, helper = map(lambda p: str(Path(p).resolve()), sys.argv[1:])
    with tempfile.TemporaryDirectory(prefix='qingfiles-integration-') as temp:
        base=Path(temp); server_root=base/'server'; server_root.mkdir()
        (server_root/'server sample.txt').write_text('Server fixture only.\n')
        authorizer=DummyAuthorizer(); authorizer.add_user('demo', PASSWORD, str(server_root), perm='elradfmwMT')
        handler=type('FixtureFTPHandler',(FTPHandler,),{'authorizer':authorizer})
        ftp=FTPServer(('127.0.0.1',0), handler)
        ftp_port=ftp.socket.getsockname()[1]
        tls_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        subject=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'QingFiles disposable test CA')])
        now=datetime.datetime.now(datetime.timezone.utc)
        cert=(x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(tls_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(minutes=5)).not_valid_after(now+datetime.timedelta(days=1)).add_extension(x509.BasicConstraints(ca=True,path_length=None),critical=True).add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]),critical=False).sign(tls_key,hashes.SHA256()))
        certificate=base/'test-ca.pem'; certificate.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        combined=base/'test-server.pem'; combined.write_bytes(certificate.read_bytes()+tls_key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.TraditionalOpenSSL,serialization.NoEncryption()))
        tls_handler=type('FixtureTLSHandler',(TLS_FTPHandler,),{'authorizer':authorizer,'certfile':str(combined),'tls_control_required':True,'tls_data_required':True})
        ftps=FTPServer(('127.0.0.1',0),tls_handler)
        ftps_port=ftps.socket.getsockname()[1]
        def serve_ftp():
            try: ftp.serve_forever(timeout=0.2)
            except OSError: pass
        threading.Thread(target=serve_ftp,daemon=True).start()
        listener=socket.socket(); listener.bind(('127.0.0.1',0)); listener.listen(30)
        key=paramiko.RSAKey.generate(2048); transports=[]; stop=threading.Event()
        def handle(client):
            transport=paramiko.Transport(client); transports.append(transport)
            transport.add_server_key(key); transport.set_subsystem_handler('sftp',paramiko.SFTPServer,Files,root=str(server_root))
            try: transport.start_server(server=Auth())
            except Exception: transport.close()
        def accept():
            while not stop.is_set():
                try: client,_=listener.accept()
                except OSError: break
                threading.Thread(target=handle,args=(client,),daemon=True).start()
        threading.Thread(target=accept,daemon=True).start()
        config=base/'config.json'
        config.write_text(json.dumps({'workspace':str(base),'askpass':helper,'password':PASSWORD,'ftpPort':ftp_port,'ftpsPort':ftps_port,'sftpPort':listener.getsockname()[1]}))
        test_env=os.environ.copy(); test_env['CURL_CA_BUNDLE']=str(certificate)
        try: result=subprocess.run([binary,str(config)],timeout=150,env=test_env)
        finally:
            stop.set(); listener.close(); ftp.close_all()
            for transport in transports: transport.close()
        raise SystemExit(result.returncode)

if __name__ == '__main__': main()
