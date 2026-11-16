# Router image for BADASS
# Official FRR image: Alpine-based, ships zebra/bgpd/ospfd/isisd, iproute2, bash
FROM quay.io/frrouting/frr:10.7.0

# Enable the daemons required by the subject (zebra is always started)
RUN sed -i \
      -e 's/^bgpd=no/bgpd=yes/' \
      -e 's/^ospfd=no/ospfd=yes/' \
      -e 's/^isisd=no/isisd=yes/' \
      /etc/frr/daemons

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

COPY --chown=frr:frr frr.conf vtysh.conf /etc/frr/
CMD ["/usr/local/bin/start.sh"]
