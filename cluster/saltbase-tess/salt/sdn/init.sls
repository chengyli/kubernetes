{% if grains.network_mode is defined and grains.network_mode == 'openvswitch' %}

openvswitch:
  pkg:
    - installed
  service.running:
    - enable: True

/usr/local/bin/ovs-docker:
    file.managed:
    - source: salt://sdn/ovs-docker
    - user: root
    - group: root
    - mode: 755

# eBay changes
{% if grains['cloud'] is defined and grains['cloud'] == 'c3' %}

{% if grains['ovs_tunnel_mode'] is defined and grains['ovs_tunnel_mode'] == 'ovs-flat' %}

{% if grains['ip4_interfaces']['obr0'] is not defined %}

obr0.create:
    cmd.run:
     - name: ovs-vsctl --may-exist add-br  obr0
{% endif %}

# We want to add the device connected to the kube network to the ovs bridge, set the name here.
{%- set bridgeable_device = grains['bridgeable_device'] %}

# If obr0 device_name does not have an ip set one, basically from the 'bridgeable_device'.
# Ideally from cloud config, but to start with we can start after the ip is set on the device

# Create network config files, for obr0
{% if grains['ip4_interfaces']['obr0'] is not defined or not grains['ip4_interfaces']['obr0'] %}

{%- set ip_address =  salt['network.interfaces']().get(bridgeable_device).inet[0].address %}
{%- set netmask =  salt['network.interfaces']().get(bridgeable_device).inet[0].netmask %}
{%- set gateway =  grains.obr0_gateway%}
{% if grains.os_distribution is defined and grains.os_distribution == 'atomic' %}
    {%- set hwaddr = salt['network.interfaces']().get(bridgeable_device).hwaddr %}
{% else %}
    {%- set hwaddr = grains.hwaddr_interfaces.eth0 %}
{% endif %}
{%- set cbr_ip = grains.cbr_ip %}
{%- set cbr_cidr = grains.cbr_cidr %}

/etc/sysconfig/network-scripts/ifcfg-obr0:
    file.managed:
     - source: salt://sdn/ifcfg-obr0.tmpl
     - template: jinja
     - context:
         ip_address: {{ ip_address }}
         netmask: {{ netmask }}

#todo(prefix should be gotten from pillar)

# set up cbr0 bridge device for docker
/etc/sysconfig/network-scripts/ifcfg-cbr0:
    file.managed:
     - source: salt://sdn/ifcfg-cbr0.tmpl
     - template: jinja
     - context:
         ip_address: {{ cbr_ip }}
         netmask: {{ netmask }}

/etc/sysconfig/network-scripts/ifcfg-{{ bridgeable_device }}:
    file.managed:
     - source: salt://sdn/ifcfg-bridgeable.tmpl
     - user: root
     - group: root
     - mode: 644
     - template: jinja
     - context:
         device_name: {{ bridgeable_device }}
         hwaddr: {{ hwaddr }}

restart.network:
    module.run:
     - name: service.restart
     - m_name: network

# todo(fix the network ifcfg correctly so that we dont need to do this)
ovs_hack_ip_attach:
    cmd.run:
        - name: ip a a {{ ip_address }}/24 dev obr0 ; ip l s obr0 up ;

# The path we are taking for now is to have Docker use the regular linux bridge and the tessnet plugin moving it over to
# the ovs bridge. This intoduced a routing issue since we have two ips on two different devies on a single box. Fixing it
# by some routing rules
/tmp/setup_routes.sh:
    file.managed:
     - source: salt://sdn/routes.sh.tmpl
     - user: root
     - group: root
     - mode: 755
     - template: jinja
     - context:
         gateway: {{ gateway }}
         ovs_br_ip_cidr: {{ cbr_cidr }}
         docker_br_ip_cidr: {{ cbr_cidr }}
         ovs_br: obr0
         docker_br: cbr0
         ovs_br_ip: {{ ip_address }}
         docker_br_ip: {{ cbr_ip }}

/etc/sysconfig/network-scripts/route-obr0:
    file.managed:
     - source: salt://sdn/route-obr0
     - user: root
     - group: root
     - mode: 755
     - template: jinja
     - context:
         gateway: {{ gateway }}
         ovs_br_ip: {{ ip_address }}
         ovs_br: obr0
         ovs_br_ip_cidr: {{ cbr_cidr }}

/etc/sysconfig/network-scripts/rule-obr0:
    file.managed:
     - source: salt://sdn/rule-obr0
     - user: root
     - group: root
     - mode: 755
     - template: jinja
     - context:
         ovs_br_ip_cidr: {{ cbr_cidr }}
         docker_br_ip: {{ cbr_ip }}

start.network-rules:
    module.run:
     - name: service.restart
     - m_name: network

{% endif %} # create network config files

{% endif %} # bridged mode

{% endif %} # eBay changes

{% endif %} # openvswitch mode
