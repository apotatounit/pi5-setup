#!/bin/bash
set +e

echo "=== all IPv4 interfaces ==="
ifconfig | awk '/^[a-z]/{iface=$1} /inet / && !/127\.0\.0\.1/{print iface, $0}' | head -20

echo
echo "=== route table (default + 10.42 + 192.168 + 172) ==="
netstat -rn -f inet | awk 'NR<=3 || /^default/ || /10\.42/ || /192\.168/ || /172\.20/'

echo
echo "=== hardware ports ==="
networksetup -listallhardwareports | awk 'BEGIN{RS=""} /Wi-Fi|Ethernet|iPhone|Thunder/{print}'

echo
echo "=== airportnetwork per en* ==="
for i in en0 en1 en2 en3 en4 en5 en6 en7; do
  out=$(networksetup -getairportnetwork "$i" 2>/dev/null)
  [[ -n "$out" && "$out" != *"not a Wi-Fi"* ]] && echo "$i: $out"
done

echo
for net in 192.168.100 172.20.10 10.42.0 192.168.0 192.168.1; do
  echo "-- ping sweep $net.x --"
  for i in 1 2 3 10 20 50 100 101 150 200; do
    ping -c 1 -W 300 "$net.$i" >/dev/null 2>&1 &
  done
  wait
  arp -an | grep -E "\($net\." | head -15
  echo
done

echo "=== Pi-vendor OUI in ARP ==="
arp -an | grep -Ei "b8:27:eb|dc:a6:32|e4:5f:01|2c:cf:67|d8:3a:dd|28:cd:c1|d8:3a:dd" || echo "(no Pi OUI anywhere)"

echo
echo "=== mDNS _ssh._tcp browse (3s) ==="
dns-sd -B _ssh._tcp local 2>&1 | head -10 &
DSPID=$!
sleep 3
kill "$DSPID" 2>/dev/null
wait 2>/dev/null

echo
echo "=== mDNS lab-pi5 / raspberrypi resolve ==="
for h in lab-pi5.local raspberrypi.local; do
  echo "-- $h --"
  dscacheutil -q host -a name "$h" 2>&1 | head -6
  ping -c 1 -W 1000 "$h" 2>&1 | head -2
done
echo "=== done ==="
