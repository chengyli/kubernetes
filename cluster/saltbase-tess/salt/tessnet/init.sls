/usr/bin/tessnet:
  file.managed:
    - source: https://os-r-object.vip.phx.ebayc3.com/v1/KEY_4f10def6f34c4fa2b4720f80855edc64/kubernetes-staging/tessnet
    - source_hash: md5=85b88fc7445ee96e4b5d665816cd66f8
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755