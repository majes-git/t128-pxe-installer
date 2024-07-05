FROM alpine:3

# Add testing repo
RUN echo '@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories

# Install additional packages
RUN apk --no-cache add dnsmasq gatling@testing squashfs-tools syslinux tini

# Link required syslinux (PXE) files to TFTP space
RUN mkdir -p /srv/tftp/pxelinux.cfg /srv/www && ln -s \
/usr/share/syslinux/lpxelinux.0 \
/usr/share/syslinux/ldlinux.c32 \
/usr/share/syslinux/libcom32.c32 \
/usr/share/syslinux/libutil.c32 \
/usr/share/syslinux/reboot.c32 \
/usr/share/syslinux/vesamenu.c32 \
/srv/tftp

# Create an updates.img image to prepare the SSR installer files
RUN mkdir -p /tmp/updates_img/etc/systemd/system/anaconda.service.d
COPY download_installer.sh /tmp/updates_img
RUN echo -e '[Service]\nExecStartPre=/download_installer.sh' \
    > /tmp/updates_img/etc/systemd/system/anaconda.service.d/override.conf && \
    chmod +x /tmp/updates_img/download_installer.sh && \
    mksquashfs /tmp/updates_img /updates.img
RUN rm -rf /tmp/updates_img

# Add static files to docker image
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY entrypoint.sh /

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
