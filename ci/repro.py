#!/usr/bin/env python3
"""Reproduce the GNU screen 5.0.2 crash: %+Lw in hardstatus, two attached
displays both showing window 1, then window 1's shell exits.

Usage: repro.py <screen binary> [runs]
Runs in a private SCREENDIR, so it never touches real sessions.
Exit 0 = the session survived every run, 1 = it crashed at least once.
"""
import os, pty, select, subprocess, sys, tempfile, time

SCREEN = os.path.abspath(sys.argv[1])
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 1

RC = """startup_message off
shell /bin/sh
hardstatus alwayslastline
hardstatus string '%-Lw%{= 0;3} %n %t %{-}%+Lw'
"""


def client(env, name):
    """Attach a client (screen -x) on its own pty; return (pid, master fd)."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(SCREEN, [SCREEN, "-x", name, "-p", "1"], env)
    return pid, fd


def drain(fds, secs):
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select(fds, [], [], 0.05)
        for fd in r:
            try:
                os.read(fd, 65536)
            except OSError:
                fds = [f for f in fds if f != fd]


def running(pid):
    """The process exists and is not a zombie. A crashed screen master is re-parented to
    PID 1; when PID 1 never reaps (`tail -f /dev/null` in a CI container), /proc/<pid>
    stays, as a zombie, so its mere existence does not mean the session survived."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            state = f.read().rsplit(")", 1)[1].split()[0]
    except OSError:
        return False
    return state not in ("Z", "X")


def session_pid(env, name):
    out = subprocess.run([SCREEN, "-ls"], env=env, capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if f".{name}" in line and "Dead" not in line:
            return int(line.split(".")[0])
    return None


def one_run(i, base):
    sockdir = os.path.join(base, f"sock{i}")
    # A Unix socket path holds at most 107 bytes (sun_path is 108 with its NUL); screen
    # names the socket <pid>.<name>, with a pid of up to 7 digits. Longer, and the server
    # cannot start (since upstream 15a1481 it panics "Socket path too long.").
    longest = len(os.fsencode(sockdir)) + len(f"/1234567.repro{i}")
    if longest > 107:
        sys.exit(f"work dir too deep for a screen socket ({longest} > 107 bytes): {sockdir}")
    os.mkdir(sockdir, 0o700)
    rc = os.path.join(base, "screenrc")
    env = dict(os.environ, SCREENDIR=sockdir, TERM="xterm-256color", HOME=base)
    name = f"repro{i}"
    subprocess.run([SCREEN, "-c", rc, "-dmS", name], env=env, check=True, cwd=base)
    time.sleep(0.3)
    subprocess.run([SCREEN, "-S", name, "-X", "screen"], env=env, check=True)
    time.sleep(0.3)
    master = session_pid(env, name)
    a = client(env, name)
    drain([a[1]], 0.8)
    if os.environ.get("REPRO_CLIENTS") == "1":
        b = None  # control: a single display
    else:
        b = client(env, name)
    fds = [c[1] for c in (a, b) if c]
    drain(fds, 0.8)
    # The shell in window 1 exits, as when someone types exit in that pane.
    subprocess.run([SCREEN, "-S", name, "-p", "1", "-X", "stuff", "exit\n"], env=env)
    drain(fds, 1.5)
    alive = master is not None and running(master)
    if alive:
        q = subprocess.run([SCREEN, "-S", name, "-Q", "windows"], env=env,
                           capture_output=True, text=True, timeout=5)
        print(f"run {i}: windows after exit: {q.stdout.strip()!r}")
        subprocess.run([SCREEN, "-S", name, "-X", "screen"], env=env)
        time.sleep(0.3)
        q = subprocess.run([SCREEN, "-S", name, "-Q", "windows"], env=env,
                           capture_output=True, text=True, timeout=5)
        print(f"run {i}: windows after a new one: {q.stdout.strip()!r}")
        subprocess.run([SCREEN, "-S", name, "-X", "quit"], env=env)
    for pid, fd in [c for c in (a, b) if c]:
        drain([fd], 0.2)
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        os.close(fd)
    return master, alive


def main():
    base = tempfile.mkdtemp(prefix="screen-repro-", dir=os.environ.get("REPRO_DIR"))
    with open(os.path.join(base, "screenrc"), "w") as f:
        f.write(RC)
    crashes = 0
    for i in range(RUNS):
        master, alive = one_run(i, base)
        print(f"run {i}: session pid {master}: {'survived' if alive else 'CRASHED'}")
        crashes += not alive
    print(f"{SCREEN}: {crashes}/{RUNS} crashed (work dir {base})")
    sys.exit(1 if crashes else 0)


main()
