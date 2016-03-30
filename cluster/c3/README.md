1. source rc file before you go
1.1 switch AZ image and endpoint infor in c3/config-default.sh
2. export KUBERNETES_PROVIDER=c3
3. cluster/kube-up.sh

Tips
--
- `export DEBUG_NO_BOOTSTRAP=true` to avoid automatically run bootstrap script after VM provisioned

Image Edit History
--
- Add /var/lib/cloud/scripts/per-boot/metaconfig.py
From https://github.corp.ebay.com/qiuyu/metaconfig/tree/4fedora
- Disable selinux
`sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config`


[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/cluster/c3/README.md?pixel)]()
