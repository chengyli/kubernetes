/etc/hosts:
  file.managed:
    - source: salt://hosts/hosts
    - template: jinja
    - user: root
    - group: root
    - mode: 644
{% if 'salt-master' in grains.roles %}
    - require:
      - sls: bootstrap-gen-pillars
{% endif %}