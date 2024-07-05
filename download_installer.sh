#!/bin/sh
# Download SSR IBU installer to netboot live system in preparation to install

# Retrieve URL based on "inst.stage2" cmdline
url=$(sed 's|.* inst.stage2=\([^ ]\+\) .*|\1|' /proc/cmdline)
image=$(curl -s $url/ | sed -n '/ibu/s/.*href="\([^"]\+\)".*/\1/p')

cd /run/install/repo/
echo -n "Downloading SSR image: $url/$image..." > /dev/tty
curl -s -JLO $url/$image && echo " ok"
curl -s -JLO $url/install.sh
curl -s -JLO $url/unpacker.sh
chmod +x *.sh
