#!/usr/bin/env python3
# ============================================================
#  SECTIA 16 - rcon.py - client RCON GoldSrc (HLDS / CS 1.6)
#  Folosit de bootstrap.sh / doctor.sh pentru verificari.
#
#  Usage: rcon.py <ip> <port> <parola_rcon> [comanda ...]
# ============================================================
import re
import socket
import sys
import time


def main():
    if len(sys.argv) < 4:
        print("utilizare: rcon.py <ip> <port> <parola_rcon> [comanda ...]",
              file=sys.stderr)
        return 2

    host = sys.argv[1]
    port = int(sys.argv[2])
    pw = sys.argv[3]
    cmd = " ".join(sys.argv[4:]) or "status"

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3.0)
    try:
        s.connect((host, port))
    except OSError as e:
        print("EROARE conectare: %s" % e, file=sys.stderr)
        return 1

    def xmit(data):
        s.sendall(b"\xff\xff\xff\xff" + data.encode("utf-8", "replace") + b"\n")

    def drain(timeout):
        out = b""
        s.settimeout(timeout)
        while True:
            try:
                out += s.recv(65536)
            except socket.timeout:
                break
            except OSError:
                break
        return out.decode("utf-8", "replace")

    # 1) challenge — raspunsul GoldSrc: "challenge rcon <numar>\n\x00"
    #    (atenție la NUL-ul final: split() nu il tratează ca whitespace)
    xmit("challenge rcon")
    r = drain(3.0)
    m = re.search(r"challenge\s+rcon\s+(\d+)", r)
    if not m:
        print("EROARE: niciun challenge RCON (serverul e pornit pe portul %d?)"
              % port, file=sys.stderr)
        return 1
    challenge = m.group(1)

    # 2) comanda — format GoldSrc: rcon <challenge> <parola> <comanda>
    #    (FARA ghilimele in jurul parolei — alea sunt protocol Source)
    time.sleep(0.1)
    xmit("rcon %s %s %s" % (challenge, pw, cmd))
    out = drain(2.5)
    lines = [l.rstrip() for l in out.replace("\xff", "").splitlines()
             if l.strip()]
    print("\n".join(lines) if lines else "(fara raspuns)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
