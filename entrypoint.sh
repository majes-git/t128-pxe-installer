#!/bin/sh

# Sanity checks
if [ -z $BLASTING_INTERFACE ]; then
    echo "No BLASTING_INTERFACE was specified. Exiting."
    exit 1
fi

# Get local IP address of $BLASTING_INTERFACE
ip_address=$(ip addr ls dev $BLASTING_INTERFACE | grep -m 1 inet | sed 's/.*inet \([^ ]\+\).*/\1/')
if [ -z $ip_address ]; then
    echo "Could not find IP address of interface $BLASTING_INTERFACE. Exiting."
    exit 1
fi
prefix_length=$(echo $ip_address | sed 's|.*/||')
if [ $prefix_length -gt 24 ]; then
    echo "This tool does not support interfaces with a prefix length larger than 24. Exiting."
    exit 1
fi

# Calculate DHCP range
ip_address=$(echo $ip_address | sed 's|/.*||')
network_prefix=$(echo $ip_address | sed 's|\(.*\..*\..*\)\..*|\1|')
dhcp_start_address="${network_prefix}.101"
dhcp_end_address="${network_prefix}.200"

# Mount first ISO image
mount -t tmpfs tmpfs /srv/www
cd /srv/www
mkdir -p iso overlay/ro overlay/rw overlay/work
if [ -n "$ISO_IMAGE" ]; then
    iso_image=/iso/$ISO_IMAGE
    if [ ! -e $iso_image ]; then
        echo "Could not find ISO image: $iso_image. Exiting."
        exit 1
    fi
else
    iso_image=$(find /iso -name '*.iso' -maxdepth 1 -print -quit)
    if [ -z $iso_image ]; then
        echo "Could not find any ISO image in /iso. Exiting."
        exit 1
    fi
fi
echo "Mounting ISO image: $iso_image"
cd overlay
mount -o loop $iso_image ro
mount -t overlay overlay -olowerdir=ro,upperdir=rw,workdir=work ../iso

# Add updates.img with preparations for the HTTP based netboot installer
cp /updates.img /srv/www/iso/images/

# Adjust syslinux config for PXE booting
sed -e "s|vmlinuz|http://$ip_address/iso/images/pxeboot/vmlinuz|" \
-e "s|initrd.img|http://$ip_address/iso/images/pxeboot/initrd.img|" \
-e "s|hd:LABEL=128T:/|http://$ip_address/|" \
-e "s|hd:LABEL=128T |http://$ip_address/iso |" \
-e "s|hd:LABEL=128T_ISO|http://$ip_address/iso|" \
/srv/www/iso/isolinux/isolinux.cfg > /srv/tftp/pxelinux.cfg/default

otp_config=ks-otp.cfg
otp_config_src=/srv/www/iso/$otp_config
if [ -e $otp_config_src ]; then
    sed -e "s|/mnt/install/repo/|http://$ip_address/iso/|" \
    -e "s|^cdrom|url --url http://$ip_address/iso/|" \
    $otp_config_src > /srv/www/$otp_config
fi

# Start daemons - dnsmasq for DHCP/TFTP and gatling for HTTP
dnsmasq --bind-dynamic --interface=$BLASTING_INTERFACE --dhcp-range=$dhcp_start_address,$dhcp_end_address
gatling -SF -c /srv/www &

sleep infinity
