# Remote connections

Open **Connect** in the toolbar, or **Connections → Remote Workspace** (`⌘⇧K`). The main window remains a local file manager; the connection window explicitly separates local paths from server paths.

## Choose a protocol

| Protocol | Typical port | Authentication and transport |
|---|---|---|
| SFTP | 22 | Files over SSH; password, key file, or available SSH agent. |
| FTPS | 21 | Explicit TLS upgrade for FTP; certificate verification is enabled. |
| FTP | 21 | Legacy unencrypted FTP. Credentials and file contents travel without encryption. |

Use a hostname or IP address in Host, without a URL scheme or `user@` prefix. Enter Username separately. Remote folders use absolute server paths such as `/home/user` or `/`. IPv6 is supported in the host field without enclosing brackets. SSH config aliases, jump hosts, forwarding, and implicit FTPS on port 990 are not configured by this version.

## Connect with SSH/SFTP

1. Enter Host, Port, Username, and the initial remote folder.
2. Enter a password or key passphrase if needed. For key authentication, optionally enter a key file such as `~/.ssh/id_ed25519`. An available SSH agent can also authenticate.
3. For a new server, click **Verify SSH Host…**. Compare the SHA-256 fingerprints with a trusted value from the server administrator. Click **Trust Host** only after comparing them. Scanning a key does not authenticate its owner.
4. Click **Connect**. An unknown or changed host key is rejected; there is no automatic trust-on-first-use bypass.
5. Server/authentication fields are locked while connected; disconnect before editing them.
6. Double-click remote folders to navigate. Use the remote path field, Up, Refresh, and Hidden items controls as needed.

Trusted keys are maintained separately in `~/Library/Application Support/QingFiles/known_hosts`. QingFiles does not edit `~/.ssh/known_hosts` or `~/.ssh/config`. SSH clients use strict checking, no agent forwarding, and no configured port forwards.

## Upload and download

- Select regular files in the local pane, check the remote path, then click **Upload →**.
- Select regular files in the remote list, check the local folder, then click **← Download**.
- The status shows the current file and file count. Transfers run off the main thread. **Cancel Transfer** stops the current process and prevents subsequent files from starting.
- Batches stop at the first failure and report how many files finished. Completed files are not rolled back.
- Known existing destination names are skipped with an error. Downloads use a unique staging file and a local move that refuses an existing destination.
- Uploads check the server listing before writing. FTP/SFTP do not provide an application-wide transaction here: a concurrent server writer can race the preflight check. Do not treat upload collision checks as an atomic no-overwrite guarantee across clients.
- An interrupted or failed upload can leave a partial remote file under the destination name. Refresh and inspect it before retrying. QingFiles does not automatically delete remote data.
- Recursive folder transfer, remote delete/rename, resumed transfer, server-to-server transfer, and byte-percentage progress are not implemented.

FTP/FTPS directory browsing requires MLSD. SFTP uses OpenSSH's long listing; nonstandard listing formats or newline-containing names are rejected. Symbolic links are shown but not followed for transfers. Filenames with spaces and bracket/star characters are covered by integration checks; unusual filesystem encodings and arbitrary leading/trailing whitespace remain compatibility limits.

## Save a connection

Give the connection a name and click **Save Connection**. Non-secret fields are stored in the app's macOS preferences. To remember a password, check **Save password in Keychain** before saving; the secret is stored as a generic password in the `QingFiles Remote` Keychain service, keyed by connection ID. Unchecking the option and saving removes the saved password for that profile.

Otherwise the password stays in the active window/session. Disconnecting or closing the connection window clears its current password and backend. Saved profiles and saved Keychain passwords remain available for later use. Profiles are not synced to GitHub.

For SFTP password authentication, a bundled SSH_ASKPASS helper receives the active secret through the child-process environment. It is never included in command-line arguments, connection JSON, logs, or terminal scripts. Like other process-memory secrets, it can be inspected by software with sufficient same-user/debugging privileges. The helper only answers password/passphrase prompts and never approves a host key.

## SSH terminal

Choose an SFTP profile and click **SSH Terminal**. QingFiles creates a private `.command` file containing quoted SSH connection arguments and opens it with macOS Terminal. Terminal provides the interactive shell and its own password/passphrase prompt. Saved QingFiles passwords are not copied to the terminal script.

The same strict host-key file, port, username, and optional key file apply. This is a Terminal session launcher, not an embedded terminal emulator. Connection scripts are kept under `~/Library/Application Support/QingFiles/Terminal Sessions` and contain no passwords; remove old scripts there if desired.

## Implementation and validation

The application uses the macOS-provided `/usr/bin/curl`, `/usr/bin/sftp`, `/usr/bin/ssh`, `ssh-keyscan`, and `ssh-keygen`; no Homebrew package or Python runtime is needed by the app. TLS verification is never disabled. SSH batch authentication options precede batch mode so password authentication remains available.

`./test.sh` includes remote path/parser/command checks. Optional end-to-end tests use disposable loopback servers and test-only Python dependencies:

```sh
python3 -m venv .build/remote-test-env
.build/remote-test-env/bin/pip install -r Tests/requirements.txt
./test.sh
./build.sh
.build/remote-test-env/bin/python Tests/remote_servers.py .build/remote-service-tests dist/QingFiles.app/Contents/MacOS/QingFilesAskpass
```

These tests generate a temporary SSH host key, a temporary TLS CA, and fixture files. They validate authenticated FTP/FTPS/SFTP listings, uploads/downloads, byte equality, wrong passwords, collisions, and SSH trust rejection. They do not contact a real account or server. No test credentials or private keys are retained after cleanup. The temporary TLS trust is passed only to the test client; system certificate trust is not changed.
