#!/usr/bin/env sh

echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 9.9.9.9" >> /etc/resolv.conf

# ===== TEMP NETWORK DIAGNOSTIC (remove after debugging the zap fetch hang) =====
# Goal: find out why "zap install" can reach DNS but the HTTPS GET to the
# tribblix mirror stalls ~21s and writes 0 bytes. We separate connect vs TLS
# vs transfer by capturing each curl exit code:
#   6=resolve  7=connect-failed  28=timeout  35=TLS-handshake  0=ok
URL="https://pkgs.tribblix.org/tribblix-m39//TRIBsocat.1.8.1.1.0.zap"
IP="18.134.134.170"
echo "===== NETDIAG begin ====="

echo "--- resolv.conf ---"
cat /etc/resolv.conf 2>&1

echo "--- ifconfig (mtu/inet) ---"
ifconfig -a 2>&1 | grep -iE "mtu|inet " 2>&1

echo "--- routes ---"
netstat -rn 2>&1 | grep -iE "default|18\.134" 2>&1

echo "--- resolve mirror ---"
getent hosts pkgs.tribblix.org 2>&1

echo "--- download tools present ---"
command -v curl wget openssl 2>&1

echo "--- curl try1: verbose, force IPv4, connect-timeout 10 ---"
curl -4 -v -o /tmp/z1 --connect-timeout 10 --max-time 45 "$URL" > /tmp/c1.log 2>&1
rc1=$?
tail -n 35 /tmp/c1.log 2>&1
echo "rc1=$rc1 size1=$(wc -c < /tmp/z1 2>/dev/null)"

echo "--- curl try2: same again (does a retry succeed?) ---"
curl -4 -sS -o /tmp/z2 --connect-timeout 10 --max-time 45 "$URL" > /tmp/c2.log 2>&1
rc2=$?
tail -n 6 /tmp/c2.log 2>&1
echo "rc2=$rc2 size2=$(wc -c < /tmp/z2 2>/dev/null)"

echo "--- curl try3: by raw IP, Host header (skip resolver) ---"
curl -4 -sS -o /dev/null -D - --resolve "pkgs.tribblix.org:443:$IP" \
  --connect-timeout 10 --max-time 45 "$URL" > /tmp/c3.log 2>&1
echo "rc3=$? ; headers:"
head -n 5 /tmp/c3.log 2>&1

echo "--- plain HTTP (port 80) to mirror by IP (TLS out of the picture) ---"
curl -4 -sS -o /dev/null -D - --connect-timeout 10 --max-time 20 "http://$IP/" > /tmp/c80.log 2>&1
echo "rc80=$? ; headers:"
head -n 5 /tmp/c80.log 2>&1

echo "--- control host cloudflare (is ALL outbound HTTPS affected?) ---"
curl -4 -sS -o /dev/null -w "cf: http=%{http_code} connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s\n" \
  --connect-timeout 10 --max-time 20 "https://1.1.1.1/" 2>&1

echo "--- wget fallback (in case zap uses wget, different stack) ---"
wget -O /tmp/zw --timeout=30 "$URL" > /tmp/w.log 2>&1
echo "wgetrc=$? sizew=$(wc -c < /tmp/zw 2>/dev/null)"
tail -n 8 /tmp/w.log 2>&1

echo "===== NETDIAG end ====="
# Always succeed so the hook does not abort the run before "zap install" --
# we want to observe the real failure in the same log.
exit 0
# ===== end TEMP NETWORK DIAGNOSTIC =====
