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

# Add files for PXE boot (legacy/non-EFI)
mkdir /srv/www/pxe
for f in ldlinux.c32 libcom32.c32 libutil.c32 reboot.c32 vesamenu.c32; do
    cp /usr/share/syslinux/$f  /srv/www/pxe
done

# Add files for PXE boot (EFI)
mkdir /srv/www/pxe-efi
for f in ldlinux.e64 libcom32.c32 libutil.c32 reboot.c32 vesamenu.c32; do
    cp /usr/share/syslinux/efi64/$f  /srv/www/pxe-efi
done

for f in boot.msg splash.png; do
cp /srv/www/iso/isolinux/$f /srv/www/pxe
cp /srv/www/iso/isolinux/$f /srv/www/pxe-efi
done

# Add updates.img with preparations for the HTTP based netboot installer
cp /updates.img /srv/www/iso/images/

# Adjust syslinux config for PXE booting
sed -e "s|vmlinuz|http://$ip_address/iso/images/pxeboot/vmlinuz|" \
-e "s|initrd.img|http://$ip_address/iso/images/pxeboot/initrd.img|" \
-e "s|hd:LABEL=128T:/|http://$ip_address/|" \
-e "s|hd:LABEL=128T |http://$ip_address/iso |" \
-e "s|hd:LABEL=128T_ISO|http://$ip_address/iso|" \
/srv/www/iso/isolinux/isolinux.cfg > /srv/www/pxe/isolinux.cfg
sed 's/\(ks-.*\)\.cfg /\1-uefi.cfg /g' /srv/www/pxe/isolinux.cfg > /srv/www/pxe-efi/isolinux.cfg

for config in ks-otp.cfg ks-interactive.cfg ks-otp-uefi.cfg ks-interactive-uefi.cfg; do
    config_src=/srv/www/iso/$config
    if [ -e $config_src ]; then
        sed -e "s|/mnt/install/repo/|http://$ip_address/iso/|" \
            -e "s|^cdrom|url --url http://$ip_address/iso/|" \
            $config_src > /srv/www/$config
    fi
done

# Start daemons - dnsmasq for DHCP/TFTP and gatling for HTTP
dnsmasq --bind-dynamic \
        --dhcp-range=$dhcp_start_address,$dhcp_end_address \
        --dhcp-option-force=209,isolinux.cfg \
        --dhcp-option-force=210,http://$ip_address/pxe/ \
        --dhcp-option-force=tag:efi,210,http://$ip_address/pxe-efi/ \
        --interface=$BLASTING_INTERFACE

gatling -SF -c /srv/www &

sleep infinity
