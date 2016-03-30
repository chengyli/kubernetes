{% if grains['oscodename'] in [ 'vivid', 'jessie' ] %}
is_systemd: True
systemd_system_path: /lib/systemd/system
{% elif grains['os_family'] == 'RedHat' %}
is_systemd: True
{% if grains.os_distribution is defined and grains.os_distribution == 'atomic' %}
systemd_system_path: /etc/systemd/system
{% else %}
systemd_system_path: /usr/lib/systemd/system
{% endif %}
{% else %}
is_systemd: False
{% endif %}
