# Grafana Image For Kubernetes

## What's In It
* Stock Grafana.
* Logic to discover InfluxDB service URL and create a datasource for it.
* Create customer dashboards during startup.


## How To Build It

```
cd $GOPATH/src/k8s.io/kubernetes/cluster/addons/cluster-monitoring/influxdb/grafana-image
make all
```

[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/cluster/addons/cluster-monitoring/influxdb/grafana-image/README.md?pixel)]()


[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/cluster/addons/cluster-monitoring/grafana/grafana-image/README.md?pixel)]()
