/*
Copyright 2015 The Kubernetes Authors All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package tessnet

import (
	"errors"
	"fmt"
	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/kubelet/network"
	kubeletTypes "k8s.io/kubernetes/pkg/kubelet/types"
	"net"
	"time"
)

const MaxRetries = 5
const RetryDelayFactor = 2 * time.Second

type networkPlugin struct {
	host     network.Host
	name     string
	tess     *TessNetServer
	listener chan bool
}

func ProbeNetworkPlugins() []network.NetworkPlugin {
	return []network.NetworkPlugin{&networkPlugin{name: "tessnet"}}
}

func (plugin *networkPlugin) Init(host network.Host) (err error) {
	glog.V(2).Infof("Initializing tessnet plugin")
	err = plugin.initializeTess(host)
	if err != nil {
		glog.V(2).Infof("Tessnet initialization failed")
		return err
	}
	glog.V(2).Infof("Tessnet ready")
	return
}

func (plugin *networkPlugin) Name() string {
	return plugin.name
}

func (plugin *networkPlugin) SetUpPod(namespace string, name string, id kubeletTypes.DockerID) error {
	glog.V(2).Infof("SetUpPod for %s/%s: %s", namespace, name, id)

	container, err := plugin.tess.DockerClient.InspectContainer(string(id))
	if err != nil {
		glog.Errorf("During setup of pod: %s, failed to inspect container: %s", name, id)
		return err
	} else {
		if "host" == container.HostConfig.NetworkMode {
			glog.V(2).Infof("Pod: %s with container: %s is running in host network mode.")
			return nil
		}
	}
	_, err = plugin.tess.SetupPod(namespace, name, string(id))
	if err != nil {
		glog.Errorf("Device plugging failed for %s/%s: %s  with error %s", namespace, name, id, err)
		return err
	}

	infraContainerip, err := plugin.getInfraContainersIP(string(id))
	if err != nil {
		glog.Errorf("Error getting infra containers ip: %s for %s/%s", err.Error(), namespace, name)
		return err
	}
	glog.V(2).Infof("Infra container ip for %s/%s:  %s", namespace, name, infraContainerip)
	return nil
}

func (plugin *networkPlugin) TearDownPod(namespace string, name string, id kubeletTypes.DockerID) error {
	container, err := plugin.tess.DockerClient.InspectContainer(string(id))
	if err != nil {
		glog.Errorf("During teardown of pod: %s, failed to inspect container: %s", name, id)
		return err
	} else {
		if "host" == container.HostConfig.NetworkMode {
			glog.V(2).Infof("Pod: %s with container: %s is running in host network mode. Nothing to clean up in ")
			return nil
		}
	}
	_, err = plugin.tess.TearDownPod(namespace, name, string(id))
	return err
}

// TODO verify veth pair is properly set up. One end in the container with ip
// The other on the ovs bridge
// http://ewen.mcneill.gen.nz/blog/entry/2014-10-12-finding-docker-containers-connection-to-openvswitch/
func (plugin *networkPlugin) Status(namespace string, name string, podInfraContainerID kubeletTypes.DockerID) (*network.PodNetworkStatus, error) {
	container, err := plugin.tess.DockerClient.InspectContainer(string(podInfraContainerID))
	if err != nil {
		glog.Errorf("Status check of pod: %s, failed to inspect container: %s", name, podInfraContainerID)
		return nil, err
	}

	if "host" == container.HostConfig.NetworkMode {
		ip, err := GetDeviceIpNet(plugin.tess.Config.Network.Bridge)
		if err != nil {
			glog.Errorf("Failed to get device ip for: %s; error is: %s", plugin.tess.Config.Network.Bridge, err.Error())
			return nil, err
		}
		if net.ParseIP(ip.IP.String()).To4() == nil {
			return nil, fmt.Errorf("Failed to get ip from device: %s while updating status for %s/%s", plugin.tess.Config.Network.Bridge, namespace, name)
		}
		glog.V(4).Infof("Pod: %s/%s is running in host network mode, ip: %s", namespace, name, ip.IP.String())
		return &network.PodNetworkStatus{IP: net.ParseIP(ip.IP.String()).To4()}, nil
	}

	ipStr, err := plugin.getInfraContainersIP(string(podInfraContainerID))
	if err != nil {
		return nil, err
	}
	ip := net.ParseIP(ipStr).To4()
	if ip == nil {
		return nil, fmt.Errorf("Failed to get ip from container: %s:%s\n", namespace, name)
	}
	glog.V(4).Infof("Reporting status of %s/%s with ip %s", namespace, name, ipStr)
	return &network.PodNetworkStatus{IP: ip}, nil
}

func (plugin *networkPlugin) getInfraContainersIP(id string) (string, error) {
	container, err := plugin.tess.DockerClient.InspectContainer(id)
	if err != nil {
		return "", err
	}

	ip := net.ParseIP(container.NetworkSettings.IPAddress).To4()
	if ip == nil {
		return "", errors.New(fmt.Sprint("Failed to get ip from infra container: %s\n", id))
	}
	return ip.String(), nil
}

func (plugin *networkPlugin) initializeTess(host network.Host) error {
	// Get config from kubelet args?
	config, err := InitConfig("/etc/sysconfig/tess", false)
	if err != nil {
		return err
	}

	bridgeIpNet, err := GetDeviceIpNet(config.Network.Bridge)
	if err != nil {
		return err
	}

	tessServer, err := NewTessNeServer(config, bridgeIpNet)
	if err != nil {
		return err
	}

	plugin.host = host
	plugin.tess = tessServer
	return nil
}
