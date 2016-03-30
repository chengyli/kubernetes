# Set the IP Conntrack max values
#https://wiki.khnet.info/index.php/Conntrack_tuning
# https://serverfault.com/questions/724739/nf-conntrack-table-full-dropping-packet-even-though-nf-conntrack-count-is-mu
net.netfilter.nf_conntrack_max:
 sysctl.present:
   - value: 500000

net.netfilter.nf_conntrack_tcp_timeout_established:
 sysctl.present:
   - value: 7800

# /sys/module/nf_conntrack/parameters
