{% if grains['os_family'] == 'RedHat' %}
/etc/dhcp/dhclient-enter-hooks:
  file.managed:
    - source: salt://c3/dhclient-enter-hooks
    - user: root
    - group: root
    - mode: 755
{% endif %}
