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
	"github.com/vishvananda/netlink"
	"github.com/vishvananda/netns"
	"net"
	"os/exec"
	"strings"
	"time"
)

func (server *TessNetServer) SetupPod(namespace string, name string, podInfraContainerId string) (string, error) {
	//todo, protect the entire process by a mutex assuming access only from this file, but we have to expect (?)
	//system level changes and probably deal around it

	//find the ip docker gave the container and use that while configuring a new ovs device
	container, err := server.DockerClient.InspectContainer(podInfraContainerId)
	if err != nil {
		return "", err
	}

	ip := net.ParseIP(container.NetworkSettings.IPAddress).To4()

	// get the container namespace
	dockerns, err := netns.GetFromPid(container.State.Pid)

	if err != nil {
		glog.V(2).Infof("Error getting pod namespace: %s, for pod: %s/%s", err, namespace, name)
		return "", err
	}
	defer dockerns.Close()

	defaultNs, err := netns.Get()
	if err != nil {
		glog.V(2).Infof("Error getting the default namespace: %s for pod %s/%s", err.Error(), namespace, name)
		return "", nil
	}
	glog.V(4).Infof("Container namespace: %d, default namespace is %d for pod %s/%s", dockerns, defaultNs, namespace, name)

	interfaceId := podInfraContainerId
	if len(podInfraContainerId) > 12 {
		interfaceId = podInfraContainerId[:12]
	}
	glog.V(2).Infof("Configuring interface: %s for pod: %s/%s", interfaceId, namespace, name)

	// if the container has eth0, we will remove it so that we can create an OVS based one.
	if err = removeDevice("eth0", dockerns, defaultNs); err != nil {
		return "", nil
	}
	numTries := 0
	var events []string
	for {
		if numTries == 3 {
			glog.V(4).Infof("Tessnet: Failed to create ovs port after 3 retries; skipping: %v", events)
			break
		}
		err = netns.Set(defaultNs)
		if err != nil {
			glog.V(4).Infof("Tessnet: Failed to change to default namespace: %s for pod %s/%s", err.Error(), namespace, name)
			events = append(events, fmt.Sprintf("Failed to change to default namespace: %s", err.Error()))
			continue
		}
		time.Sleep(time.Second * 1)
		ipNet := net.IPNet{ip, server.bridgeIPNet.Mask}
		gw, err := GetDeviceIpNet(server.Config.Network.Bridge)
		if err != nil {
			glog.V(4).Infof("Tessnet: Unable to get device %s ip for pod %s/%s Err: %s", server.Config.Network.Bridge, namespace, name, err.Error())
			events = append(events, fmt.Sprintf("Unable to get device %s ip. Err: %s", server.Config.Network.Bridge, err.Error()))
			continue
		}
		glog.V(4).Info("Tessnet: Using gateway %s for configuring pod %s/%s", string(gw.IP), namespace, name)
		message, err := server.ovsDockerAddPort(podInfraContainerId, ipNet, gw.IP)
		if err != nil {
			glog.V(4).Infof("Tessnet: Unable to add port to ovs %s for pod: %s/%s", err.Error(), namespace, name)
			events = append(events, fmt.Sprintf("Unable to add port to ovs %s", err.Error()))
			continue
		} else {
			return message, nil
		}
		numTries++
	}

	return "", fmt.Errorf("Failed to add ovs port after 3 retries. %v", events)
}

func (server *TessNetServer) TearDownPod(namespace string, name string, podInfraContainerID string) (string, error) {
	return server.ovsDockerDelPort(podInfraContainerID)
}

func removeDevice(device string, containerNs netns.NsHandle, defaultNs netns.NsHandle) error {
	defer netns.Set(defaultNs)

	netns.Set(containerNs)
	dev, _ := netlink.LinkByName(device)
	if dev != nil {
		if err := netlink.LinkDel(dev); err != nil {
			return fmt.Errorf("error removing device %s from container. Error was %s ", device, err)
		}
		glog.V(3).Infof("removed stock eth0 from container")
	}
	return nil
}

func (server *TessNetServer) ovsDockerAddPort(containerId string, ipNet net.IPNet, gateway net.IP) (string, error) {

	cmd := exec.Command(server.Config.Network.OvsDocker, "add-port", server.Config.Network.Bridge,
		server.Config.Network.Device, containerId, ipNet.String(), gateway.String())

	bytes, err := cmd.CombinedOutput()
	if err != nil {
		return "", errors.New(fmt.Sprintf("add-port error: message=%s : error=%s", string(bytes), err.Error()))
	}

	message := string(bytes[:])
	if bytes != nil && strings.Contains(message, "Failed") {
		return "", errors.New(message)
	}

	return ipNet.IP.To4().String(), nil
}

func (server *TessNetServer) ovsDockerDelPort(containerId string) (string, error) {

	cmd := exec.Command(server.Config.Network.OvsDocker, "del-port", server.Config.Network.Bridge,
		server.Config.Network.Device, containerId)

	bytes, err := cmd.CombinedOutput()
	if err != nil {
		return "", errors.New(fmt.Sprintf("error: message=%s : error=%s", string(bytes), err.Error()))
	}

	message := string(bytes[:])
	if bytes != nil && strings.Contains(message, "Failed") {
		return "", errors.New(message)
	}

	return message, nil
}

func (server *TessNetServer) execPipework(containerId string, ipNet net.IPNet) (string, error) {

	ipString := fmt.Sprintf("%s@%s", ipNet, server.Config.Network.Gateway)
	glog.V(2).Infof("ip string %s \n", ipString)

	cmd := exec.Command(server.Config.Network.Pipework, server.Config.Network.Bridge,
		"-i", server.Config.Network.Device, containerId, ipString)
	bytes, err := cmd.CombinedOutput()

	if err != nil {
		return "", errors.New(fmt.Sprintf("error: message=%s : error=%s", string(bytes), err.Error()))
	}

	message := string(bytes[:])

	if bytes != nil && strings.Contains(message, "error") {
		return "", errors.New(message)
	}
	return ipNet.IP.To4().String(), nil
}
