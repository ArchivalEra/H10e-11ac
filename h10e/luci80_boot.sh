#!/bin/sh
[ -f /userconfig/NO_LUCI ] && exit 0
# H10E-11AC LuCI:80 一键恢复（重启后执行一次即可）
# 持久文件：/usr/data/iw-luci-final.tar.gz /usr/data/iw-delta-226.tar.gz /userconfig/httpd.shadow
# 用法：sh /userconfig/luci80_boot.sh
set -u
BASE=/usr/data/iw-luci-final.tar.gz
DELTA=/usr/data/iw-delta-226.tar.gz
SHADOW=/userconfig/httpd.shadow
D=/tmp/delta226

echo "[1/7] restore /var/iw base"
mkdir -p /var/iw /opt/cu /tmp
rm -rf /var/iw
mkdir -p /var/iw
tar -xzf "$BASE" -C /var/iw

echo "[2/7] apply 2.26 delta"
rm -rf "$D"
mkdir -p "$D"
tar -xzf "$DELTA" -C "$D"
for extra in ucode-sync luci-mod-admin luci-base-menu; do
  if [ -f "$D/$extra.tar.gz" ]; then
    tar -xzf "$D/$extra.tar.gz" -C /var/iw
    tar -xzf "$D/$extra.tar.gz" -C /
  elif [ -f "/usr/data/$extra.tar.gz" ]; then
    tar -xzf "/usr/data/$extra.tar.gz" -C /var/iw
    tar -xzf "/usr/data/$extra.tar.gz" -C /
  fi
done
cp -f "$D/ucode" /var/iw/bin/ucode
chmod +x /var/iw/bin/ucode
cp -f "$D/libubox.so" /var/iw/lib/libubox.so
cp -f "$D/libubus.so" /var/iw/lib/libubus.so
cp -f "$D/libuci.so" /var/iw/lib/libuci.so
cp -f "$D/libjson-c.so.5" /var/iw/lib/libjson-c.so.5
cp -f "$D/libucode.so" /var/iw/lib/libucode.so
cp -f "$D/libucode.so" /var/iw/lib/libucode.so.0
cp -f "$D/rpcd" /var/iw/sbin/rpcd
chmod +x /var/iw/sbin/rpcd
cp -f "$D/file.so" /usr/lib/rpcd/file.so
cp -f "$D/rpcd_ucode.so" /usr/lib/rpcd/ucode.so
cp -f "$D/rpcsys.so" /usr/lib/rpcd/rpcsys.so
cp -f "$D/luci-rpcd.so" /usr/lib/rpcd/luci.so
chmod +x /usr/lib/rpcd/*.so
cp -f "$D/libnl-3.so.200.26.0" /var/iw/lib/libnl-3.so.200.26.0
ln -sf libnl-3.so.200.26.0 /var/iw/lib/libnl-3.so.200
ln -sf libnl-3.so.200.26.0 /var/iw/lib/libnl-3.so
cp -f "$D/h10e-ubus" /var/iw/sbin/h10e-ubus
chmod +x /var/iw/sbin/h10e-ubus
mkdir -p /usr/lib/ucode /var/iw/usr/lib/ucode /var/iw/lib/ucode
cp -f "$D/html.so" /usr/lib/ucode/html.so
cp -f "$D/html.so" /var/iw/usr/lib/ucode/html.so
cp -f "$D/html.so" /var/iw/lib/ucode/html.so
chmod +x /usr/lib/ucode/html.so
# complete ucode stdlib in /usr/lib/ucode (rpcd luci object needs ubus/fs/version)
cp -f /var/iw/usr/lib/ucode/*.so /usr/lib/ucode/ 2>/dev/null
cp -f /var/iw/lib/ucode/*.so /usr/lib/ucode/ 2>/dev/null
chmod +x /usr/lib/ucode/*.so 2>/dev/null
mkdir -p /usr/lib/ucode/luci /var/iw/usr/lib/ucode/luci
cp -f "$D/luci_core.so" /usr/lib/ucode/luci/core.so
cp -f "$D/luci_core.so" /var/iw/usr/lib/ucode/luci/core.so
chmod +x /usr/lib/ucode/luci/core.so
tar -xzf "$D/material-zhcn.tar.gz" -C /var/iw
tar -xzf "$D/material-zhcn.tar.gz" -C /
if [ -f /usr/data/luci-mod-admin.tar.gz ]; then
  tar -xzf /usr/data/luci-mod-admin.tar.gz -C /var/iw
  tar -xzf /usr/data/luci-mod-admin.tar.gz -C /
mkdir -p /var/iw/usr/share/ucode/luci/template/themes
cp -r /usr/share/ucode/luci/template/themes/material /var/iw/usr/share/ucode/luci/template/themes/ 2>/dev/null
cp -r /usr/share/ucode/luci/template/admin_status /var/iw/usr/share/ucode/luci/template/ 2>/dev/null
mkdir -p /var/iw/www/luci-static/resources/icons
cp -f /var/iw/www/luci-static/material/icons/spinner.svg /var/iw/www/luci-static/resources/icons/loading.gif 2>/dev/null
fi
mkdir -p /var/iw/usr/share/ucode/luci/template/themes
cp -r /usr/share/ucode/luci/template/themes/material /var/iw/usr/share/ucode/luci/template/themes/ 2>/dev/null
tar -xzf "$D/zhcn-lmo.tar.gz" -C /
mkdir -p /usr/share/luci/i18n
cp -f /usr/lib/lua/luci/i18n/base.zh-cn.lmo /usr/share/luci/i18n/ 2>/dev/null
# de-poison: iw libcrypt/libnss shadow system libs and break NSS/crypt
# resolution (GLIBC mismatch) -> move them aside so /lib versions win
mkdir -p /var/iw/lib/bak
mv -f /var/iw/lib/libcrypt.so /var/iw/lib/libcrypt.so.1 /var/iw/lib/libcrypt.so.1.1.0 /var/iw/lib/libnss_files.so.2 /var/iw/lib/bak/ 2>/dev/null

echo "[3/7] luci config material+zh_cn"
mkdir -p /etc/config
cat > /etc/config/luci <<'EOF'
config core 'main'
	option urlbase '/cgi-bin/luci'
	option mediaurlbase '/luci-static/material'
	option resourcebase '/luci-static/resources'
	option lang 'zh_cn'
config sauth 'sauth'
	option sessionpath '/tmp/luci-sessions'
	option sessiontime '3600'
EOF
cat > /etc/config/system <<'EOF'
config system
	option hostname 'H10E-11AC'
	option timezone 'CST-8'
	option zonename 'Asia/Shanghai'
EOF
# display-only configs for LuCI (vendor BSP owns the real network)
cat > /etc/config/network <<'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config interface 'lan'
	option device 'br0'
	option proto 'static'
	option ipaddr '192.168.1.1'
	option netmask '255.255.255.0'
	option ip6assign '60'

config interface 'wan'
	option device 'pon'
	option proto 'dhcp'
	option ip6assign '60'

config interface 'wan6'
	option device 'pon'
	option proto 'dhcpv6'
	option ip6assign '60'
	option reqaddress 'try'
	option reqprefix 'auto'
EOF
cat > /etc/config/wireless <<'EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option path 'platform/mt7603'
	option band '2g'
	option channel '6'
	option txpower '20'
	option country 'CN'
	option disabled '0'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'platform/mt7603'
	option band '5g'
	option channel '64'
	option txpower '20'
	option country 'CN'
	option disabled '0'

config wifi-iface 'wifinet0'
	option device 'radio0'
	option ifname 'wlan0'
	option ssid 'CMCC-reda'
	option mode 'ap'
	option network 'lan'
	option encryption 'psk2'

config wifi-iface 'wifinet1'
	option device 'radio0'
	option ifname 'wlan3'
	option ssid 'CMCC-E-CBDA-5G'
	option mode 'ap'
	option network 'lan'
	option encryption 'psk2'
	option disabled '1'

config wifi-iface 'wifinet2'
	option device 'radio1'
	option ifname 'wlan4'
	option ssid 'CMCC-reda-5G'
	option mode 'ap'
	option network 'lan'
	option encryption 'psk2'

config wifi-iface 'wifinet3'
	option device 'radio1'
	option ifname 'wlan7'
	option ssid 'CMCC-E-CBDA-5G'
	option mode 'ap'
	option network 'lan'
	option encryption 'psk2'
	option disabled '1'
EOF
# user-modified wireless (with real keys) wins over display baseline
if [ -f /userconfig/wireless.conf ]; then
	cp -f /userconfig/wireless.conf /etc/config/wireless
fi
cat > /etc/config/dhcp <<'EOF'
config dnsmasq
	option domainneeded '1'
	option localise_queries '1'
	option rebind_protection '1'
	option local '/lan/'
	option domain 'lan'
	option expandhosts '1'
	option authoritative '1'
	option readethers '1'
	option leasefile '/tmp/dhcp.leases'
	option localservice '1'

config dhcp 'lan'
	option interface 'lan'
	option start '100'
	option limit '150'
	option leasetime '12h'

config odhcpd 'odhcpd'
	option maindhcp '0'
	option leasefile '/tmp/hosts/odhcpd'
	option leasetrigger '/usr/sbin/odhcpd-update'
EOF
cat > /etc/config/firewall <<'EOF'
config defaults
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option synflood_protect '1'

config zone
	option name 'lan'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'
	list network 'lan'
EOF
cat > /etc/config/rpcd <<'EOF'
config rpcd
	option socket /var/run/ubus.sock
	option timeout 30
config login
	option username 'root'
	option password '$6$h10e11ac$JNjX.wYEDJ0BlGEb/AKR3Iz4sP/5qAgxflplHYoJ0kQvwaqjXPlJkdgo0rvIk0/eZNS6HTPdtIcNa5MtKs.fi/'
	list read '*'
	list write '*'
EOF
# NOTE: LuCI password is h10e-luci-2026 (hash above); system root password untouched
printf '#!/bin/sh\nexport LD_LIBRARY_PATH=/var/iw/lib\nexec /var/iw/bin/ucode "$@"\n' > /usr/bin/ucode
chmod +x /usr/bin/ucode
ln -sf /sbin/dnsmasq /usr/sbin/dnsmasq 2>/dev/null
mkdir -p /usr/share/rpcd/acl.d
cat > /usr/share/rpcd/acl.d/unauthenticated.json <<'EOF'
{
	"unauthenticated": {
		"description": "Access controls for unauthenticated requests",
		"read": {
			"ubus": {
				"session": [
					"access",
					"login"
				]
			}
		}
	}
 }
EOF
cp -f "$D/acld/"*.json /usr/share/rpcd/acl.d/ 2>/dev/null
# generated LuCI version module (rpcd luci object imports luci.version)
printf 'export const branch = "master";\nexport const revision = "git-25.231.55265-cbdafdb";\n' > /usr/share/ucode/luci/version.uc

echo "[4/7] httpd shadow persist"
mkdir -p /opt/cu
if [ ! -f "$SHADOW" ]; then
  printf '#!/bin/sh\nexit 0\n' > "$SHADOW"
  chmod +x "$SHADOW"
fi
cp -f /sbin/httpd /opt/cu/httpd.real 2>/dev/null
cp -f "$SHADOW" /opt/cu/httpd.shadow
chmod +x /opt/cu/httpd.shadow
mount --bind /opt/cu/httpd.shadow /sbin/httpd 2>/dev/null
killall httpd 2>/dev/null

echo "[5/7] start ubus/rpcd/lighttpd"
killall ubusd 2>/dev/null
sleep 1
rm -rf /var/run/ubus
mkdir -p /var/run/ubus
LD_LIBRARY_PATH=/var/iw/lib /var/iw/bin/ubusd -s /var/run/ubus/ubus.sock >/dev/null 2>&1 &
sleep 1
ln -sf /var/run/ubus/ubus.sock /var/run/ubus.sock
killall rpcd 2>/dev/null
sleep 1
REQUIRE_SEARCH_PATH=/usr/share/ucode:/usr/lib/ucode LD_LIBRARY_PATH=/var/iw/lib /var/iw/sbin/rpcd >/dev/null 2>&1 &
sleep 1
killall h10e-ubus 2>/dev/null
killall system-ubus 2>/dev/null
cp -f "$D/hu-supervise.sh" /var/iw/sbin/hu-supervise.sh 2>/dev/null
chmod +x /var/iw/sbin/hu-supervise.sh
/var/iw/sbin/hu-supervise.sh >/dev/null 2>&1 &
sleep 1
# replay saved wireless live settings into driver (idempotent)
LD_LIBRARY_PATH=/var/iw/lib /var/iw/bin/ubus call service event '{"type":"config.change","data":{"package":"wireless"}}' >/dev/null 2>&1
sleep 1
killall lighttpd 2>/dev/null
sleep 1
sed -i 's/8081/80/' /var/iw/etc/lighttpd.conf 2>/dev/null
sed -i 's#server.document-root = "/www"#server.document-root = "/var/iw/www"#' /var/iw/etc/lighttpd.conf 2>/dev/null
/var/iw/bin/lighttpd -m /var/iw/lib/lighttpd -f /var/iw/etc/lighttpd.conf >/dev/null 2>&1 &
sleep 2

echo "[6/7] verify"
LD_LIBRARY_PATH=/var/iw/lib /var/iw/bin/ubus list 2>&1 | head -n 20
curl -I http://127.0.0.1/ 2>&1 | head -n 10
curl -I http://127.0.0.1/cgi-bin/luci 2>&1 | head -n 10
netstat -tlnp 2>&1 | head -n 15
echo "[7/7] done - open http://192.168.1.1/cgi-bin/luci (Material + zh_cn)"
