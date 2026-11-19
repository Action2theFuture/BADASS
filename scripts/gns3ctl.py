#!/usr/bin/env python3
"""
BADASS - drive the local GNS3 server from the command line (no GUI needed).

Uses the GNS3 v2 REST API of gns3server 2.2.x on 127.0.0.1:3080.
If no server is listening, one is started in the background (same server the
GUI would use, so GUI and CLI see the same projects and nodes).

  gns3ctl.py server                      ensure gns3server is running
  gns3ctl.py up     P3 [--fresh]         import P3/P3.gns3project if needed, open it
  gns3ctl.py start  P3 [node ...]        start all nodes (or only the given ones)
  gns3ctl.py stop   P3 [node ...]        stop all nodes (or only the given ones)
  gns3ctl.py status [P3]                 projects / node states
  gns3ctl.py down                        stop nodes and close every opened project
  gns3ctl.py export P3 [file]            write a portable project (no images)
"""
import base64
import configparser
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

HOST = os.environ.get("GNS3_HOST", "127.0.0.1")
PORT = int(os.environ.get("GNS3_PORT", "3080"))
BASE = f"http://{HOST}:{PORT}/v2"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOG = os.path.expanduser("~/gns3server.log")
# The local server started by the GNS3 GUI enables HTTP Basic auth (user "admin",
# random password) and stores it here. Our own server (started below) has no auth.
SERVER_CONF = os.path.expanduser("~/.config/GNS3/2.2/gns3_server.conf")


def auth_headers():
    """Basic auth header if the server config enables authentication."""
    cfg = configparser.ConfigParser()
    try:
        cfg.read(SERVER_CONF)
        if cfg.getboolean("Server", "auth", fallback=False):
            user = cfg.get("Server", "user", fallback="").strip()
            password = cfg.get("Server", "password", fallback="").strip()
            token = base64.b64encode(f"{user}:{password}".encode()).decode()
            return {"Authorization": f"Basic {token}"}
    except (configparser.Error, OSError):
        pass
    return {}


def die(msg):
    print(f"[-] {msg}", file=sys.stderr)
    sys.exit(1)


def api(method, path, body=None, raw=None, timeout=120):
    """Call the API; body is JSON, raw is bytes (import)."""
    data, headers = None, auth_headers()
    if raw is not None:
        data = raw
        headers["Content-Type"] = "application/octet-stream"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            payload = r.read()
    except urllib.error.HTTPError as e:
        die(f"{method} {path} -> HTTP {e.code}: {e.read().decode(errors='replace')[:300]}")
    if not payload:
        return None
    try:
        return json.loads(payload)
    except ValueError:
        return payload


def server_up():
    req = urllib.request.Request(BASE + "/version", headers=auth_headers())
    try:
        with urllib.request.urlopen(req, timeout=2) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:   # a server IS running (GNS3 GUI) but our credentials are wrong
            die(f"gns3server on {HOST}:{PORT} requires authentication; credentials in {SERVER_CONF} rejected")
        return None
    except (urllib.error.URLError, OSError, ValueError):
        return None


def ensure_server():
    v = server_up()
    if v:
        return v
    exe = shutil.which("gns3server") or os.path.expanduser("~/.local/bin/gns3server")
    if not os.path.exists(exe):
        die("gns3server not found (run setup_vm.sh)")
    print(f"[*] starting gns3server on {HOST}:{PORT} (log: {LOG})")
    with open(LOG, "ab") as log:
        # setsid: keep running after this ssh session ends
        subprocess.Popen([exe, "--local", "--host", HOST, "--port", str(PORT)],
                         stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                         start_new_session=True)
    for _ in range(60):
        time.sleep(1)
        v = server_up()
        if v:
            return v
    die(f"gns3server did not answer, see {LOG}")


def find_project(name):
    for p in api("GET", "/projects"):
        if p["name"] == name:
            return p
    return None


def remove_stale_containers(pid):
    """Containers GNS3 left behind (VM crash / reboot without closing the project).
    GNS3 names them GNS3.<node>.<project_id>; opening the project would fail with
    'Docker 409 Conflict: container name already in use'."""
    out = subprocess.run(["docker", "ps", "-aq", "--filter", f"name={pid}"],
                         capture_output=True, text=True)
    ids = out.stdout.split()
    if ids:
        subprocess.run(["docker", "rm", "-f", *ids], capture_output=True)
        print(f"[*] removed {len(ids)} stale container(s) of a previous session")


def project_file(name):
    part = name.split("-")[0]                      # P2-xxx -> P2 folder
    path = os.path.join(REPO, part, f"{name}.gns3project")
    if not os.path.isfile(path):
        die(f"portable project not found: {path}")
    return path


def up(name, fresh=False):
    ensure_server()
    p = find_project(name)
    if p and fresh:
        print(f"[*] deleting existing project {name}")
        api("DELETE", f"/projects/{p['project_id']}")
        p = None
    if not p:
        path = project_file(name)
        print(f"[*] importing {os.path.relpath(path, REPO)} as '{name}'")
        with open(path, "rb") as f:
            p = api("POST", f"/projects/{uuid.uuid4()}/import?name={name}", raw=f.read())
    pid = p["project_id"]
    if p.get("status") != "opened":
        remove_stale_containers(pid)
        api("POST", f"/projects/{pid}/open")
    # import sets auto_close=true: the project would close when no client is watching
    api("PUT", f"/projects/{pid}", body={"auto_close": False})
    print(f"[+] project {name} opened ({pid})")
    return pid


def nodes(pid):
    return api("GET", f"/projects/{pid}/nodes")


def select(pid, names):
    all_nodes = nodes(pid)
    if not names:
        return all_nodes
    by_name = {n["name"]: n for n in all_nodes}
    missing = [n for n in names if n not in by_name]
    if missing:
        die(f"unknown node(s): {', '.join(missing)}; have: {', '.join(sorted(by_name))}")
    return [by_name[n] for n in names]


def action(name, verb, names):
    pid = up(name)
    targets = select(pid, names)
    for n in targets:
        api("POST", f"/projects/{pid}/nodes/{n['node_id']}/{verb}")
        print(f"[+] {verb:5s} {n['name']}")


def status(name=None):
    if not server_up():
        print("[-] gns3server not running")
        return
    for p in api("GET", "/projects"):
        if name and p["name"] != name:
            continue
        print(f"{p['name']:12s} {p['status']}")
        if p["status"] == "opened":
            for n in sorted(nodes(p["project_id"]), key=lambda n: n["name"]):
                print(f"    {n['name']:18s} {n['node_type']:16s} {n['status']}")


def down():
    if not server_up():
        print("[*] gns3server not running, nothing to do")
        return
    for p in api("GET", "/projects"):
        if p["status"] == "opened":
            api("POST", f"/projects/{p['project_id']}/nodes/stop")
            api("POST", f"/projects/{p['project_id']}/close")
            print(f"[+] closed {p['name']}")


def export(name, dest=None):
    ensure_server()
    p = find_project(name) or die(f"project {name} not found")
    dest = dest or project_file(name)
    data = api("GET", f"/projects/{p['project_id']}/export?include_images=no", timeout=300)
    with open(dest, "wb") as f:
        f.write(data)
    print(f"[+] exported {name} -> {dest} ({len(data)} bytes)")


def main(argv):
    if not argv:
        print(__doc__)
        sys.exit(1)
    cmd, args = argv[0], argv[1:]
    if cmd == "server":
        v = ensure_server()
        print(f"[+] gns3server {v.get('version')} on {HOST}:{PORT}")
    elif cmd == "up" and args:
        up(args[0], fresh="--fresh" in args)
    elif cmd in ("start", "stop") and args:
        action(args[0], cmd, args[1:])
    elif cmd == "status":
        status(args[0] if args else None)
    elif cmd == "down":
        down()
    elif cmd == "export" and args:
        export(args[0], args[1] if len(args) > 1 else None)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
