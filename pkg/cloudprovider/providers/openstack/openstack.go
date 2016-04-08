/*
Copyright 2014 The Kubernetes Authors All rights reserved.

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

package openstack

import (
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/golang/glog"
	"github.com/rackspace/gophercloud"
	"github.com/rackspace/gophercloud/openstack"
	"github.com/rackspace/gophercloud/openstack/blockstorage/v1/volumes"
	"github.com/rackspace/gophercloud/openstack/compute/v2/extensions/volumeattach"
	"github.com/rackspace/gophercloud/openstack/compute/v2/flavors"
	"github.com/rackspace/gophercloud/openstack/compute/v2/servers"
	"github.com/rackspace/gophercloud/openstack/networking/v2/extensions/lbaas/members"
	"github.com/rackspace/gophercloud/openstack/networking/v2/extensions/lbaas/monitors"
	"github.com/rackspace/gophercloud/openstack/networking/v2/extensions/lbaas/pools"
	"github.com/rackspace/gophercloud/openstack/networking/v2/extensions/lbaas/vips"
	"github.com/rackspace/gophercloud/pagination"
	"github.com/scalingdata/gcfg"
	"k8s.io/kubernetes/Godeps/_workspace/src/github.com/rackspace/gophercloud/openstack/networking/v2/extensions/layer3/floatingips"

	"strconv"

	"k8s.io/kubernetes/Godeps/_workspace/src/github.com/rackspace/gophercloud/openstack/networking/v2/ports"
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/api/resource"
	"k8s.io/kubernetes/pkg/client/restclient"
	client "k8s.io/kubernetes/pkg/client/unversioned"
	"k8s.io/kubernetes/pkg/client/unversioned/auth"
	"k8s.io/kubernetes/pkg/cloudprovider"
	"k8s.io/kubernetes/pkg/fields"
	"k8s.io/kubernetes/pkg/labels"
	"k8s.io/kubernetes/pkg/types"
	"k8s.io/kubernetes/pkg/util/intstr"
)

const ProviderName = "openstack"

var ErrNotFound = errors.New("Failed to find object")
var ErrMultipleResults = errors.New("Multiple results where only one expected")
var ErrNoAddressFound = errors.New("No address found for host")
var ErrAttrNotFound = errors.New("Expected attribute not found")
var ErrServiceNotFound = errors.New("Service not found matching lbname")
var ErrLBTimedOut = errors.New("Timed out creating Load Balancer artifact")
var ErrLBPendigCreateStatus = errors.New("Load Balancer artifact in PENDING_CREATE status")
var ErrLBErrorStatus = errors.New("Load Balancer artifact in Error status")

const waitInterval = 5
const (
	MiB = 1024 * 1024
	GB  = 1000 * 1000 * 1000
)

const (
	LoadBalancerPendingStatus = "PENDING_CREATE"
	LoadBalancerActiveStatus  = "ACTIVE"
	LoadBalancerErrorStatus   = "ERROR"
)

// encoding.TextUnmarshaler interface for time.Duration
type MyDuration struct {
	time.Duration
}

func (d *MyDuration) UnmarshalText(text []byte) error {
	res, err := time.ParseDuration(string(text))
	if err != nil {
		return err
	}
	d.Duration = res
	return nil
}

type LoadBalancerOpts struct {
	SubnetId          string     `gcfg:"subnet-id"` // required
	LBMethod          string     `gfcg:"lb-method"`
	CreateMonitor     bool       `gcfg:"create-monitor"`
	MonitorDelay      MyDuration `gcfg:"monitor-delay"`
	MonitorTimeout    MyDuration `gcfg:"monitor-timeout"`
	MonitorMaxRetries uint       `gcfg:"monitor-max-retries"`
	FloatingIPNetId   string     `gcfg:"floating-network-id"`
	LeastUsedSubnetId string     `gcfg:"floatingip-subnet-net-id"`
}

// OpenStack is an implementation of cloud provider Interface for OpenStack.
type OpenStack struct {
	provider *gophercloud.ProviderClient
	region   string
	lbOpts   LoadBalancerOpts
	authOpts gophercloud.AuthOptions
}

type Config struct {
	Global struct {
		AuthUrl    string `gcfg:"auth-url"`
		Username   string
		UserId     string `gcfg:"user-id"`
		Password   string
		ApiKey     string `gcfg:"api-key"`
		TenantId   string `gcfg:"tenant-id"`
		TenantName string `gcfg:"tenant-name"`
		DomainId   string `gcfg:"domain-id"`
		DomainName string `gcfg:"domain-name"`
		Region     string
	}
	LoadBalancer LoadBalancerOpts
}

func init() {
	cloudprovider.RegisterCloudProvider(ProviderName, func(config io.Reader) (cloudprovider.Interface, error) {
		cfg, err := readConfig(config)
		if err != nil {
			return nil, err
		}
		return newOpenStack(cfg)
	})
}

func (cfg Config) toAuthOptions() gophercloud.AuthOptions {
	return gophercloud.AuthOptions{
		IdentityEndpoint: cfg.Global.AuthUrl,
		Username:         cfg.Global.Username,
		UserID:           cfg.Global.UserId,
		Password:         cfg.Global.Password,
		APIKey:           cfg.Global.ApiKey,
		TenantID:         cfg.Global.TenantId,
		TenantName:       cfg.Global.TenantName,

		// Persistent service, so we need to be able to renew tokens.
		AllowReauth: true,
	}
}

func readConfig(config io.Reader) (Config, error) {
	if config == nil {
		err := fmt.Errorf("no OpenStack cloud provider config file given")
		return Config{}, err
	}

	var cfg Config
	err := gcfg.ReadInto(&cfg, config)
	return cfg, err
}

func newOpenStack(cfg Config) (*OpenStack, error) {
	provider, err := openstack.AuthenticatedClient(cfg.toAuthOptions())
	if err != nil {
		glog.Errorf("%v", err)
		return nil, err
	}

	os := OpenStack{
		provider: provider,
		region:   cfg.Global.Region,
		lbOpts:   cfg.LoadBalancer,
		authOpts: cfg.toAuthOptions(),
	}
	return &os, nil
}

type Instances struct {
	compute            *gophercloud.ServiceClient
	flavor_to_resource map[string]*api.NodeResources // keyed by flavor id
}

// Instances returns an implementation of Instances for OpenStack.
func (os *OpenStack) Instances() (cloudprovider.Instances, bool) {
	glog.V(4).Info("openstack.Instances() called")

	compute, err := openstack.NewComputeV2(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})
	if err != nil {
		glog.Warningf("Failed to find compute endpoint: %v", err)
		return nil, false
	}

	pager := flavors.ListDetail(compute, nil)

	flavor_to_resource := make(map[string]*api.NodeResources)
	err = pager.EachPage(func(page pagination.Page) (bool, error) {
		flavorList, err := flavors.ExtractFlavors(page)
		if err != nil {
			return false, err
		}
		for _, flavor := range flavorList {
			rsrc := api.NodeResources{
				Capacity: api.ResourceList{
					api.ResourceCPU:            *resource.NewQuantity(int64(flavor.VCPUs), resource.DecimalSI),
					api.ResourceMemory:         *resource.NewQuantity(int64(flavor.RAM)*MiB, resource.BinarySI),
					"openstack.org/disk":       *resource.NewQuantity(int64(flavor.Disk)*GB, resource.DecimalSI),
					"openstack.org/rxTxFactor": *resource.NewMilliQuantity(int64(flavor.RxTxFactor)*1000, resource.DecimalSI),
					"openstack.org/swap":       *resource.NewQuantity(int64(flavor.Swap)*MiB, resource.BinarySI),
				},
			}
			flavor_to_resource[flavor.ID] = &rsrc
		}
		return true, nil
	})
	if err != nil {
		glog.Warningf("Failed to find compute flavors: %v", err)
		return nil, false
	}

	glog.V(4).Infof("Found %v compute flavors", len(flavor_to_resource))
	glog.V(4).Info("Claiming to support Instances")

	return &Instances{compute, flavor_to_resource}, true
}

func (i *Instances) List(name_filter string) ([]string, error) {
	glog.V(4).Infof("openstack List(%v) called", name_filter)

	opts := servers.ListOpts{
		Name:   name_filter,
		Status: "ACTIVE",
	}
	pager := servers.List(i.compute, opts)

	ret := make([]string, 0)
	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		sList, err := servers.ExtractServers(page)
		if err != nil {
			return false, err
		}
		for _, server := range sList {
			if server.Metadata["fqdn"] != nil {
				ret = append(ret, server.Metadata["fqdn"].(string))
			}
		}
		return true, nil
	})
	if err != nil {
		glog.Errorf("List Instances failed: %v", err)
		return nil, err
	}

	glog.V(4).Infof("Found %v instances matching %v: %v",
		len(ret), name_filter, ret)

	return ret, nil
}

func getServerByName(client *gophercloud.ServiceClient, name string) (*servers.Server, error) {
	opts := servers.ListOpts{
		Name:   fmt.Sprintf("^%s$", regexp.QuoteMeta(name)),
		Status: "ACTIVE",
	}
	pager := servers.List(client, opts)

	serverList := make([]servers.Server, 0, 1)

	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		s, err := servers.ExtractServers(page)
		if err != nil {
			return false, err
		}
		serverList = append(serverList, s...)
		if len(serverList) > 1 {
			return false, ErrMultipleResults
		}
		return true, nil
	})
	if err != nil {
		return getServerByFQDN(client, name)
	}

	if len(serverList) == 0 {
		return getServerByFQDN(client, name)
	} else if len(serverList) > 1 {
		return nil, ErrMultipleResults
	}

	return &serverList[0], nil
}

func getServerByFQDN(client *gophercloud.ServiceClient, fqdn string) (*servers.Server, error) {
	opts := servers.ListOpts{
		Name:   ".",
		Status: "ACTIVE",
	}
	glog.V(4).Infof("Searching servers by fqdn: %q\n", fqdn)
	pager := servers.List(client, opts)

	serverList := make([]servers.Server, 0, 1)

	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		s, err := servers.ExtractServers(page)
		if err != nil {
			glog.Errorf("Failed to find server by fqdn: %v", err)
			return false, err
		}
		for _, srv := range s {
			if srv.Metadata["fqdn"] == fqdn {
				serverList = append(serverList, srv)
				glog.V(4).Infof("Found server: %s for fqdn: %s\n", srv.ID, fqdn)
			}
		}
		if len(serverList) == 0 {
			glog.Warningf("No servers found for fqdn: %s\n", fqdn)
			return false, ErrNotFound
		}
		return true, nil
	})
	if err != nil {
		return nil, err
	}

	if len(serverList) == 0 {
		return nil, ErrNotFound
	} else if len(serverList) > 1 {
		glog.V(4).Infof("Found servers: %v\n", serverList)
		return nil, ErrMultipleResults
	}

	return &serverList[0], nil
}

func findAddrs(netblob interface{}) []string {
	// Run-time types for the win :(
	ret := []string{}
	list, ok := netblob.([]interface{})
	if !ok {
		return ret
	}
	for _, item := range list {
		props, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		tmp, ok := props["addr"]
		if !ok {
			continue
		}
		addr, ok := tmp.(string)
		if !ok {
			continue
		}
		ret = append(ret, addr)
	}
	return ret
}

func getAddressByName(api *gophercloud.ServiceClient, name string) (string, error) {
	srv, err := getServerByName(api, name)
	if err != nil {
		return "", err
	}

	var s string
	if s == "" {
		if tmp := findAddrs(srv.Addresses["private"]); len(tmp) >= 1 {
			s = tmp[0]
		}
	}
	if s == "" {
		if tmp := findAddrs(srv.Addresses["public"]); len(tmp) >= 1 {
			s = tmp[0]
		}
	}
	if s == "" {
		s = srv.AccessIPv4
	}
	if s == "" {
		s = srv.AccessIPv6
	}
	if s == "" {
		return "", ErrNoAddressFound
	}
	return s, nil
}

// This function waits till the lb pool/member/vip  reaches desiredState or times out
func timedWait(c *gophercloud.ServiceClient, id string, lbObjectType string, desiredStatus string) error {
	const LBTimeout = 300
	var totalTime = 0
	var statusString string
	for {

		switch lbObjectType {

		case "pool":
			pool, err := pools.Get(c, id).Extract()
			if err != nil {
				continue
			}
			statusString = pool.Status

		case "member":
			member, err := members.Get(c, id).Extract()
			if err != nil {
				continue
			}
			statusString = member.Status
		case "vip":
			vip, err := vips.Get(c, id).Extract()
			if err != nil {
				continue
			}
			statusString = vip.Status
		}
		if statusString == desiredStatus {
			glog.V(4).Infof("timedWait: %s %s with id:%s\n", lbObjectType, desiredStatus, id)
			return nil
		} else if statusString == LoadBalancerErrorStatus {
			glog.V(4).Infof("%s:%s is in ERROR state\n", lbObjectType, id)
			return ErrLBErrorStatus
		}
		if totalTime >= LBTimeout {
			glog.V(4).Infof("timedWait: timed out waiting for %s:%s to become %s\n", lbObjectType, id, desiredStatus)
			return ErrLBTimedOut
		}
		glog.V(4).Infof("timedWait: Waiting for %s:%s to become %s\n", lbObjectType, id, desiredStatus)
		time.Sleep(time.Second * waitInterval)
		totalTime += waitInterval
	}
}

/*
This function will wait for all the artifacts to become active or timeout
*/
func timedWaitForAll(c *gophercloud.ServiceClient, id string, desiredStatus string) error {

	maxRetries := 18
	count := 0
	retry := false
	for {
		if count >= maxRetries {
			return ErrLBTimedOut
		}
		memList, err := listMembers(c, members.ListOpts{PoolID: id})
		if err != nil {
			// Error retrieving Members!
			return err
		}
		maxRetries = len(memList)
		// Check for Active members
		for _, member := range memList {
			glog.V(4).Infof("timedWaitForAll: Check member:%s, poolid:%s, State:%s", member.ID, id, member.Status)
			if member.Status != LoadBalancerActiveStatus {
				// Member Not Active Yet! Check for errors, else retry
				if member.Status == LoadBalancerErrorStatus {
					return ErrLBErrorStatus
				}
				retry = true
			}
		}
		if !retry {
			break
		}
		glog.V(4).Infof("timedWaitForAll: Waiting for all the members of poolid:%s", id)
		time.Sleep(time.Second * waitInterval)
		count++
		retry = false
	}
	// All the members are active!
	glog.V(4).Infof("timedWaitForAll: All the memner of pool:%s are in %s status", id, desiredStatus)
	return nil
}

// Implementation of Instances.CurrentNodeName
func (i *Instances) CurrentNodeName(hostname string) (string, error) {
	return hostname, nil
}

func (i *Instances) AddSSHKeyToAllInstances(user string, keyData []byte) error {
	return errors.New("unimplemented")
}

func (i *Instances) NodeAddresses(name string) ([]api.NodeAddress, error) {
	glog.V(4).Infof("NodeAddresses(%v) called", name)

	srv, err := getServerByName(i.compute, name)
	if err != nil {
		return nil, err
	}

	addrs := []api.NodeAddress{}
	var privateNetworkPattern = regexp.MustCompile(`^kubernetes.*tess-network$`)
	for networkName, networkInfo := range srv.Addresses {
		if privateNetworkPattern.MatchString(networkName) {
			for _, addr := range findAddrs(networkInfo) {
				addrs = append(addrs, api.NodeAddress{
					Type:    api.NodeInternalIP,
					Address: addr,
				})
			}
		} else {
			for _, addr := range findAddrs(networkInfo) {
				addrs = append(addrs, api.NodeAddress{
					Type:    api.NodeExternalIP,
					Address: addr,
				})
			}
		}
	}

	// AccessIPs are usually duplicates of "public" addresses.
	api.AddToNodeAddresses(&addrs,
		api.NodeAddress{
			Type:    api.NodeExternalIP,
			Address: srv.AccessIPv6,
		},
		api.NodeAddress{
			Type:    api.NodeExternalIP,
			Address: srv.AccessIPv4,
		},
	)

	glog.V(4).Infof("NodeAddresses(%v) => %v", name, addrs)
	return addrs, nil
}

// ExternalID returns the cloud provider ID of the specified instance (deprecated).
func (i *Instances) ExternalID(name string) (string, error) {
	srv, err := getServerByName(i.compute, name)
	if err != nil {
		return "", err
	}
	return srv.ID, nil
}

// InstanceID returns the cloud provider ID of the specified instance.
func (i *Instances) InstanceID(name string) (string, error) {
	srv, err := getServerByName(i.compute, name)
	if err != nil {
		return "", err
	}
	// In the future it is possible to also return an endpoint as:
	// <endpoint>/<instanceid>
	return "/" + srv.ID, nil
}

func (i *Instances) GetNodeResources(name string) (*api.NodeResources, error) {
	glog.V(4).Infof("GetNodeResources(%v) called", name)

	srv, err := getServerByName(i.compute, name)
	if err != nil {
		//        srv, err = getServerByFQDN(i.compute, name)
		if err != nil {
			return nil, err
		}
	}

	s, ok := srv.Flavor["id"]
	if !ok {
		return nil, ErrAttrNotFound
	}
	flavId, ok := s.(string)
	if !ok {
		return nil, ErrAttrNotFound
	}
	rsrc, ok := i.flavor_to_resource[flavId]
	if !ok {
		return nil, ErrNotFound
	}

	glog.V(4).Infof("GetNodeResources(%v) => %v", name, rsrc)

	return rsrc, nil
}

func (os *OpenStack) Clusters() (cloudprovider.Clusters, bool) {
	return nil, false
}

// ProviderName returns the cloud provider ID.
func (os *OpenStack) ProviderName() string {
	return ProviderName
}

// ScrubDNS filters DNS settings for pods.
func (os *OpenStack) ScrubDNS(nameservers, searches []string) (nsOut, srchOut []string) {
	return nameservers, searches
}

type LoadBalancer struct {
	network    *gophercloud.ServiceClient
	compute    *gophercloud.ServiceClient
	opts       LoadBalancerOpts
	osAuthOpts gophercloud.AuthOptions
}

func (os *OpenStack) LoadBalancer() (cloudprovider.LoadBalancer, bool) {
	glog.V(4).Info("openstack.TCPLoadBalancer() called")

	// TODO: Search for and support Rackspace loadbalancer API, and others.
	network, err := openstack.NewNetworkV2(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})
	if err != nil {
		glog.Warningf("Failed to find neutron endpoint: %v", err)
		return nil, false
	}

	compute, err := openstack.NewComputeV2(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})
	if err != nil {
		glog.Warningf("Failed to find compute endpoint: %v", err)
		return nil, false
	}

	glog.V(1).Info("Claiming to support LoadBalancer")

	return &LoadBalancer{network, compute, os.lbOpts, os.authOpts}, true
}

func isNotFound(err error) bool {
	e, ok := err.(*gophercloud.UnexpectedResponseCodeError)
	return ok && e.Actual == http.StatusNotFound
}

func getPoolByName(client *gophercloud.ServiceClient, name string, tenantid string) ([]pools.Pool, error) {
	opts := pools.ListOpts{
		TenantID: tenantid,
	}
	pager := pools.List(client, opts)

	var fullPoolList []pools.Pool
	var poolList []pools.Pool

	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		p, err := pools.ExtractPools(page)
		if err != nil {
			return false, err
		}
		fullPoolList = append(fullPoolList, p...)
		if len(poolList) > 1 {
			return false, ErrMultipleResults
		}
		return true, nil
	})
	if err != nil {
		if isNotFound(err) {
			return nil, ErrNotFound
		}
		glog.Errorf("Failed to get pool by name: %v", err)
		return nil, err
	}

	if len(fullPoolList) == 0 {
		return nil, ErrNotFound
	}

	for _, pool := range fullPoolList {
		if strings.Contains(pool.Name, name) {
			poolList = append(poolList, pool)
		}
	}

	return poolList, nil
}

//Returns a list of vips that match the name regex;
//multiple vips are created with the same ip when more than one port exists
func getVipByName(client *gophercloud.ServiceClient, name string, tenantid string) ([]vips.VirtualIP, error) {
	opts := vips.ListOpts{
		TenantID: tenantid,
	}
	pager := vips.List(client, opts)

	var fullVipList []vips.VirtualIP
	var vipList []vips.VirtualIP

	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		v, err := vips.ExtractVIPs(page)
		if err != nil {
			return false, err
		}
		fullVipList = append(fullVipList, v...)
		if len(vipList) > 1 {
			return false, ErrMultipleResults
		}
		return true, nil
	})
	if err != nil {
		if isNotFound(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	for _, vip := range fullVipList {
		if strings.Contains(vip.Name, name) {
			vipList = append(vipList, vip)
		}
	}

	if len(vipList) == 0 {
		glog.V(4).Infof("No vips found with name: %s", name)
		return nil, ErrNotFound
	}

	return vipList, nil
}

func (lb *LoadBalancer) GetLoadBalancer(name, region string) (*api.LoadBalancerStatus, bool, error) {
	vips, err := getVipByName(lb.network, name, lb.osAuthOpts.TenantID)
	if err == ErrNotFound {
		return nil, false, nil
	}
	if len(vips) == 0 {
		glog.V(4).Infof("No vip found for service: %s", name)
		return nil, false, err
	}

	status := &api.LoadBalancerStatus{}
	// Address is same for all the vips returned
	status.Ingress = []api.LoadBalancerIngress{{IP: vips[0].Address}}

	return status, true, err
}

// TODO: This code currently ignores 'region' and always creates a
// loadbalancer in only the current OpenStack region.  We should take
// a list of regions (from config) and query/create loadbalancers in
// each region.
func (lb *LoadBalancer) EnsureLoadBalancer(name, region string, loadBalancerIP net.IP, ports []*api.ServicePort, hosts []string, serviceName types.NamespacedName, affinityType api.ServiceAffinity, annotations map[string]string) (*api.LoadBalancerStatus, error) {
	glog.V(4).Infof("EnsureTCPLoadBalancer(%v, %v, %v, %v, %v, %v)", name, region, loadBalancerIP, ports, hosts, affinityType)
	var persistence *vips.SessionPersistence
	switch affinityType {
	case api.ServiceAffinityNone:
		persistence = nil
	case api.ServiceAffinityClientIP:
		persistence = &vips.SessionPersistence{Type: "SOURCE_IP"}
	default:
		return nil, fmt.Errorf("unsupported load balancer affinityType: %v", affinityType)
	}

	//	glog.V(2).Info("Checking if openstack load balancer already exists: %s", name)
	//	_, exists, err := lb.GetTCPLoadBalancer(name, region)
	//	if err != nil {
	//		return nil, fmt.Errorf("error checking if openstack load balancer already exists: %v", err)
	//	}
	//
	//	// TODO: Implement a more efficient update strategy for common changes than delete & create
	//	// In particular, if we implement hosts update, we can get rid of UpdateHosts
	//	if exists {
	//		err := lb.EnsureTCPLoadBalancerDeleted(name, region)
	//		if err != nil {
	//			return nil, fmt.Errorf("error deleting existing openstack load balancer: %v", err)
	//		}
	//	}

	podsList, service, err := getServicePodListbyLBName(name)
	if err != nil {
		return nil, err
	}
	var poolMembers []string
	fipPodMap := make(map[string]*api.Pod)
	// This is to hold floatingip to pod uid mapping
	for _, pod := range podsList {
		fip, err := lb.createFloatingIPsforPods(pod.Spec.NodeName, pod.Status.PodIP)
		if err != nil {
			return nil, err
		}
		poolMembers = append(poolMembers, fip)
		fipPodMap[fip] = &pod
	}
	// messageChan retrieves success/error from go routines
	messageChan := make(chan map[string]string, len(ports))
	// vipAddressChan is used to communicate the vip address between go routines
	vipAddressChan := make(chan string, 1)
	vipAddress := ""

	for i := 0; i < len(ports); i++ {
		vipsList, err := getVipByName(lb.network, fmt.Sprintf("%s-%d", name, ports[i].Port), lb.osAuthOpts.TenantID)
		if err != nil && err != ErrNotFound {
			glog.V(4).Infof("EnsureTCPLoadBalancer: failed to retrive vip for port %d with error:%s", ports[i].Port, err.Error())
			return nil, err
		}
		if len(vipsList) > 0 {
			vipAddress = vipsList[0].Address
		}
	}
	vipAddressChan <- vipAddress // Initialize the vipAddressChannel

	for i := 0; i < len(ports); i++ {
		glog.V(4).Infof("CreateTCPLoadBalancer: Start createPort routine for port: %d", ports[i].Port)
		go lb.createPort(name, poolMembers, fipPodMap, ports[i], service.Name, loadBalancerIP, persistence, messageChan, vipAddressChan)
	}
	failed := false
	// Wait for all the go routines to return either Success or Error message
	for i := 0; i < len(ports); i++ {
		returnedMap := <-messageChan
		glog.V(4).Infof("CreateTCPLoadBalancer: createPort routine returned %v", returnedMap)
		if returnedMap["Error"] != "" {
			err = errors.New(returnedMap["Error"])
			failed = true
		}
		vipAddress = returnedMap["Success"]
	}
	if failed {
		glog.V(2).Infof("CreateTCPLoadBalancer: All the ports not successful yet. Will retry")
		return nil, err
	}
	// If we are here all the ports create succeeded
	status := &api.LoadBalancerStatus{}
	status.Ingress = []api.LoadBalancerIngress{{IP: vipAddress}}
	return status, nil
}

func updateChannel(messageChannel chan map[string]string, key string, errMsg string) {

	messageMap := make(map[string]string)
	messageMap[key] = errMsg
	messageChannel <- messageMap
	return
}

func (lb *LoadBalancer) createPort(name string, poolMembers []string, fipPodMap map[string]*api.Pod, port *api.ServicePort, serviceName string, loadBalancerIP net.IP, persistence *vips.SessionPersistence, messageChannel chan map[string]string, vipAddressChan chan string) {

	var address string
	var vip *vips.VirtualIP
	var mon *monitors.Monitor

	pool, err := lb.createPool(name, port.Port)
	if err != nil {
		updateChannel(messageChannel, "Error", err.Error())
		return
	}
	glog.V(2).Infof("createPort: %s: Created or found pool: %s for port: %d\n", serviceName, pool.ID, port.Port)

	for _, podfip := range poolMembers {
		poolm, err := lb.createMember(pool.ID, port, podfip, fipPodMap[podfip])
		if err != nil {
			glog.V(2).Infof("createPort: Failed to create pool member for service: %s, %v", name, err)
			updateChannel(messageChannel, "Error", err.Error())
			return
		}
		glog.V(2).Infof("createPort: %s: Added member: %s to pool %s for port: %d", serviceName, poolm.ID, pool.ID, port.Port)
	}

	if lb.opts.CreateMonitor {
		mon, err = monitors.Create(lb.network, monitors.CreateOpts{
			Type:       monitors.TypeTCP,
			Delay:      int(lb.opts.MonitorDelay.Duration.Seconds()),
			Timeout:    int(lb.opts.MonitorTimeout.Duration.Seconds()),
			MaxRetries: int(lb.opts.MonitorMaxRetries),
		}).Extract()
		if err != nil {
			updateChannel(messageChannel, "Error", err.Error())
			return
		}
		// Once we support monitors for tess, timedWait here for monitor to become ACTIVE
		_, err = pools.AssociateMonitor(lb.network, pool.ID, mon.ID).Extract()
		if err != nil {
			updateChannel(messageChannel, "Error", err.Error())
			return
		}
	}
	if loadBalancerIP != nil && !loadBalancerIP.IsUnspecified() {
		address = loadBalancerIP.String()
	} else {
		glog.V(4).Infof("createPort: Waiting for VIP Address to be initialized")
		address = <-vipAddressChan
	}

	vip, err = lb.createVip(name, port.Port, pool.ID, address, persistence, serviceName)
	if err != nil {
		glog.V(2).Infof("createPort: Failed to create vip for service: %s, %v", name, err)
		vipAddressChan <- address
		updateChannel(messageChannel, "Error", err.Error())
		return
	}
	vipAddressChan <- vip.Address

	// Wait for all the PoolMembers to become active or timeout
	err = timedWaitForAll(lb.network, pool.ID, LoadBalancerActiveStatus)
	if err != nil {
		glog.V(4).Infof("Pool member timedwait Error: %s for pool:%s", err.Error(), pool.ID)
		updateChannel(messageChannel, "Error", err.Error())
		return
	}
	// Wait for vip to become active or timeout
	err = timedWait(lb.network, vip.ID, "vip", LoadBalancerActiveStatus)
	if err != nil {
		glog.V(4).Infof("Vip creation timedwait Error: %s for name %s\n", pool.ID, name)
		updateChannel(messageChannel, "Error", err.Error())
		return
	} else {
		glog.V(4).Infof("Created Vip: %s for name %s", pool.ID, name)
		address = vip.Address
		glog.V(2).Infof("CreateTCPLoadBalancer: %s: Successfully created vip: %s with ip: %s for port: %d", serviceName, vip.ID, vip.Address, port.Port)
		updateChannel(messageChannel, "Success", address)
		return
	}
}

func listMembers(c *gophercloud.ServiceClient, opts members.ListOpts) (membersList []members.Member, err error) {
	pager := members.List(c, opts)

	err = pager.EachPage(func(page pagination.Page) (bool, error) {
		memberList, err := members.ExtractMembers(page)
		if err != nil {
			fmt.Print(err)
			return false, err
		}
		membersList = memberList
		return true, nil
	})
	return membersList, err
}

// The function gets vip if it already exists, else it creates it
func (lb *LoadBalancer) createVip(name string, port int, poolid string, address string, persistence *vips.SessionPersistence, serviceName string) (*vips.VirtualIP, error) {

	vipsList, err := getVipByName(lb.network, fmt.Sprintf("%s-%d", name, port), lb.osAuthOpts.TenantID)
	if err != nil && err != ErrNotFound {
		return nil, err
	} else if len(vipsList) == 1 {
		vip := &vipsList[0]
		if vip != nil {
			switch vip.Status {

			case LoadBalancerActiveStatus:
				glog.V(2).Infof("Found vip %s for name %s with address %s", vip.ID, name, address)
				return vip, nil
			case LoadBalancerPendingStatus:
				glog.V(2).Infof("Found vip %s for name %s with address %s is in PENDING_CREATE status, skip", vip.ID, name, address)
				return nil, ErrLBPendigCreateStatus
			case LoadBalancerErrorStatus:
				glog.V(2).Infof("Found vip %s for name %s with address %s is in ERROR status", vip.ID, name, address)
				return nil, ErrLBErrorStatus
			}
		}
	} else if len(vipsList) > 1 {
		//This should never ever happen cause neutron won't allow us to create 2 vips with the same name
		return nil, fmt.Errorf("More than one vip found for name: %s", fmt.Sprintf("%s-%d", name, port))
	}

	//else create a new one
	createOpts := vips.CreateOpts{
		Name:         fmt.Sprintf("%s-%d", name, port),
		Description:  fmt.Sprintf("Kubernetes external service %s", name),
		Protocol:     "TCP",
		ProtocolPort: port,
		PoolID:       poolid,
		Persistence:  persistence,
		SubnetID:     lb.opts.SubnetId,
	}
	if len(address) > 0 {
		glog.V(4).Infof("%s: Using externalip or previously created ip: %s to create vip", serviceName, address)
		createOpts.Address = address
	}
	glog.V(4).Infof("%s: Vip creation opts: %+v and address is: %s", serviceName, createOpts, address)
	vip, err := vips.Create(lb.network, createOpts).Extract()
	if err != nil {
		return nil, err
	}
	return vip, nil
}

// The function gets member if it already exists, else it creates it
func (lb *LoadBalancer) createMember(poolid string, port *api.ServicePort, fip string, pod *api.Pod) (*members.Member, error) {
	var member *members.Member
	pager := members.List(lb.network, members.ListOpts{Address: fip, PoolID: poolid})
	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		memList, err := members.ExtractMembers(page)
		if err != nil {
			return false, err
		}
		if len(memList) > 1 {
			// todo may be clean up -- spothanis
			return false, fmt.Errorf("More than 1 member found for: %s", fip)
		} else if len(memList) == 1 {
			member = &memList[0]
		}
		// no error; member not found
		return false, nil
	})

	if err != nil {
		return nil, err
	} else if member != nil {
		switch member.Status {

		case LoadBalancerActiveStatus:
			glog.V(2).Infof("Found member %s for address %s", member.ID, fip)
			return member, nil
		case LoadBalancerPendingStatus:
			glog.V(2).Infof("Found member %s for address %s is in PENDING_CREATE status, skip", member.ID, fip)
			return nil, ErrLBPendigCreateStatus
		case LoadBalancerErrorStatus:
			glog.V(2).Infof("Found member %s for address %s is in ERROR status", member.ID, fip)
			return nil, ErrLBErrorStatus
		}
	}

	poolMemberTargetPort, err := getContainerPort(port, pod)
	if err != nil {
		return nil, fmt.Errorf("Failed get target port for pod with fip: %s and id: %s", fip, pod.UID)
	}
	createOpts := members.CreateOpts{
		PoolID:       poolid,
		ProtocolPort: poolMemberTargetPort,
		Address:      fip,
	}
	member, err = members.Create(lb.network, createOpts).Extract()
	if err != nil {
		return nil, err
	}
	return member, nil
}

type test struct {
	s gophercloud.ServiceClient
}

// The function gets member if it already exists, else it creates it
func (lb *LoadBalancer) createPool(name string, port int) (*pools.Pool, error) {

	lbmethod := lb.opts.LBMethod
	if lbmethod == "" {
		lbmethod = pools.LBMethodRoundRobin
	}
	poolList, err := getPoolByName(lb.network, name, lb.osAuthOpts.TenantID)

	if err != nil && err != ErrNotFound {
		return nil, err
	}

	if poolList != nil {
		for _, p := range poolList {
			if strings.Contains(p.Name, strconv.Itoa(port)) {
				switch p.Status {

				case LoadBalancerActiveStatus:
					glog.V(2).Infof("Found pool: %s for service %s, skipping creation", p.ID, name)
					return &p, nil
				case LoadBalancerPendingStatus:
					glog.V(2).Infof("Found pool: %s for service %s is in PENDING_CREATE, skip", p.ID, name)
					return nil, ErrLBPendigCreateStatus
				case LoadBalancerErrorStatus:
					glog.V(2).Infof("Found pool: %s for service %s is in ERROR status", p.ID, name)
					return nil, ErrLBErrorStatus
				}
			}
		}
	}

	pool, err := pools.Create(lb.network, pools.CreateOpts{
		Name:     fmt.Sprintf("%s-%d", name, port),
		Protocol: pools.ProtocolTCP,
		SubnetID: lb.opts.SubnetId,
		LBMethod: lbmethod,
	}).Extract()
	if err != nil {
		return nil, err
	}
	// Wait for the pool to become active or timeout
	err = timedWait(lb.network, pool.ID, "pool", LoadBalancerActiveStatus)
	if err != nil {
		glog.V(4).Infof("Pool creation Error: %s for name %s", pool.ID, name)
		return nil, err
	} else {
		glog.V(4).Infof("Created pool: %s for name %s", pool.ID, name)
		return pool, nil
	}
}

func (lb *LoadBalancer) getVMPortIDbyFQDN(fqdn string) (string, error) {
	srv, err := getServerByFQDN(lb.compute, fqdn)
	if err != nil {
		return "", err
	}
	pager := ports.List(lb.network, ports.ListOpts{
		DeviceID: srv.ID,
	})
	var portID string
	err = pager.EachPage(func(page pagination.Page) (bool, error) {
		ports, err := ports.ExtractPorts(page)
		if err != nil {
			return false, err
		}
		if len(ports) == 0 {
			return false, errors.New(fmt.Sprint("Failed to get port id for: %s", fqdn))
		}
		if len(ports) == 1 {
			portID = ports[0].ID
			return true, nil
		}
		if len(ports) == 2 {
			if len(ports[0].FixedIPs) > 1 {
				portID = ports[0].ID
			} else {
				portID = ports[1].ID
			}
		} else {
			return false, errors.New("More than 2 ports found on the VM, hence not able to figure out the port")
		}
		return true, nil
	})

	if portID == "" {
		return "", errors.New("Second port not found in getVMIDbyFQDN")
	}

	return portID, nil

}

func (lb *LoadBalancer) findFloatingIP(portid string, podip string) (string, error) {
	var ip = net.ParseIP(strings.TrimSpace(podip))
	if ip == nil {
		return "", fmt.Errorf("%s is not a valid pod ip", podip)
	}
	lopts := floatingips.ListOpts{
		PortID:            portid,
		FloatingNetworkID: lb.opts.FloatingIPNetId,
		FixedIP:           podip,
	}
	var fip string
	err := floatingips.List(lb.network, lopts).EachPage(func(page pagination.Page) (bool, error) {
		fips, err := floatingips.ExtractFloatingIPs(page)
		if err != nil {
			return false, err
		}
		if len(fips) == 1 {
			fip = fips[0].FloatingIP
			return true, nil
		} else if len(fips) == 0 {
			glog.V(4).Infof("No floatingip found for fixed ip: %s", podip)
			return true, nil
		} else {
			fip = fips[0].FloatingIP
			glog.Warningf("More than one 1 floatingip found %v for fixed ip: %s, using the 1st one %s and deleting the rest", fips, podip, fip)
			//attempt to clean up rest
			for i := 1; i < len(fips); i++ {
				lb.deleteFloatingIP(fips[i].FloatingIP)
			}
			return true, nil
		}
	})

	if err != nil {
		return "", err
	}
	return fip, nil
}

func (lb *LoadBalancer) createFloatingIPsforPods(host string, podip string) (string, error) {
	portid, err := lb.getVMPortIDbyFQDN(host)
	if err != nil {
		return "", err
	}

	floatingip, err := lb.findFloatingIP(portid, podip)

	if err != nil {
		return "", err
	} else if len(floatingip) > 0 {
		glog.V(2).Infof("Floating ip %s exists for fixed ip %s", floatingip, podip)
		return floatingip, nil
	}
	opts := floatingips.CreateOpts{
		FloatingNetworkID: lb.opts.FloatingIPNetId,
		PortID:            portid,
		FixedIP:           podip,
	}
	fip, err := floatingips.Create(lb.network, opts).Extract()
	if err != nil {
		return "", err
	}
	glog.V(2).Infof("Created floating ip: %s for port: %s and fixed-ip: %s", fip.FloatingIP, portid, podip)
	return fip.FloatingIP, nil
}

func getServicePodListbyLBName(name string) ([]api.Pod, *api.Service, error) {

	kclient, err := getKubeClient()
	if err != nil {
		return nil, nil, err
	}

	namespace, servicename, err := getServiceNamefromlbname(name, kclient)
	if err != nil {
		return nil, nil, err
	}

	service, err := kclient.Services(namespace).Get(servicename)
	if err != nil {
		return nil, nil, err
	}
	podSelector := labels.Set(service.Spec.Selector).AsSelector()
	podsList, err := kclient.Pods(namespace).List(api.ListOptions{
		LabelSelector: podSelector,
		FieldSelector: fields.Everything(),
	})
	if err != nil {
		return nil, nil, err
	}

	return podsList.Items, service, nil
}

func getPoolMembersByPodsList(podsList []api.Pod, lb *LoadBalancer) (map[string]bool, map[string]*api.Pod, error) {

	poolmembers := make(map[string]bool)
	fipPodMap := make(map[string]*api.Pod)
	for _, pod := range podsList {
		fip, err := lb.createFloatingIPsforPods(pod.Spec.NodeName, pod.Status.PodIP)
		if err != nil {
			glog.V(2).Infof("UpdateLoadBalancer: PodName:%v, IP:%s, Failed creating/finding floating IP with err:%v", pod.Spec.NodeName, pod.Status.PodIP, err)
			return nil, nil, err
		}
		glog.V(2).Infof("UpdateLoadBalancer: Created/found floating ip: %s for pod: %s", fip, pod.Status.PodIP)
		poolmembers[fip] = true
		fipPodMap[fip] = &pod
	}
	return poolmembers, fipPodMap, nil
}

func copyPoolMembersForVip(poolMembers map[string]bool, fipPodMap map[string]*api.Pod, poolMembersForVip map[string]bool, fipPodMapForVip map[string]*api.Pod) {

	for key, value := range poolMembers {
		poolMembersForVip[key] = value
	}
	for key, value := range fipPodMap {
		fipPodMapForVip[key] = value
	}
}

func (lb *LoadBalancer) UpdateLoadBalancer(name, region string, hosts []string) error {
	glog.V(2).Infof("UpdateLoadBalancer(%v, %v, %v)", name, region, hosts)

	vipList, err := getVipByName(lb.network, name, lb.osAuthOpts.TenantID)
	if err != nil {
		return err
	}
	glog.V(4).Infof("UpdateLoadBalancer: totals %d vips:\n", len(vipList))
	podsList, service, err := getServicePodListbyLBName(name)
	if err != nil {
		return err
	}
	glog.V(4).Infof("UpdateLoadBalancer: % pods for service:%v\n", len(podsList), service.Name)
	poolMembers, fipPodMap, err := getPoolMembersByPodsList(podsList, lb)
	if err != nil {
		return err
	}

	poolMembersForVip := make(map[string]bool)
	fipPodMapForVip := make(map[string]*api.Pod)

	portServicePortMap := make(map[int]*api.ServicePort)

	for portIndex, port := range service.Spec.Ports {

		portServicePortMap[port.Port] = &(service.Spec.Ports[portIndex])
	}

	for _, vip := range vipList {
		// for each vip, we need a temporary copy of the poolmembers and fipPodMap to work on
		copyPoolMembersForVip(poolMembers, fipPodMap, poolMembersForVip, fipPodMapForVip)

		// Iterate over members that _do_ exist
		pager := members.List(lb.network, members.ListOpts{PoolID: vip.PoolID})
		err = pager.EachPage(func(page pagination.Page) (bool, error) {
			memList, err := members.ExtractMembers(page)
			if err != nil {
				return false, err
			}
			for _, member := range memList {
				if _, found := poolMembersForVip[member.Address]; found {
					// Member already exists
					delete(poolMembersForVip, member.Address)
					glog.V(2).Infof("UpdateLoadBalancer: %s still has member: %s nothing to do", name, poolMembersForVip)
				} else {
					// Member needs to be deleted TODO: PENDING_DELETE check?
					err = members.Delete(lb.network, member.ID).ExtractErr()
					if err != nil {
						return false, err
					}
					err = lb.deleteFloatingIP(member.Address)
					if err != nil {
						return false, err
					}
					glog.V(2).Infof("UpdateLoadBalancer: %s: Deleted obsolete pool member: %s and floatingip: %s for vip %s", service.Name, member.ID, member.Address, vip.Address)
				}
			}
			return true, nil
		})
		if err != nil {
			return err
		}
		// Anything left in poolMembersForVip is a new member that needs to be added
		for addr := range poolMembersForVip {
			_, err := lb.createMember(vip.PoolID, portServicePortMap[vip.ProtocolPort], addr, fipPodMapForVip[addr])
			if err != nil {
				return err
			}
			glog.V(2).Infof("UpdateLoadBalancer: %s: Added member %s to pool %s for vip %s", service.Name, addr, vip.PoolID, vip.Address)
		}
	}
	return nil
}

func (lb *LoadBalancer) EnsureLoadBalancerDeleted(name, region string) error {
	glog.V(4).Infof("EnsureLoadBalancerDeleted(%v, %v)", name, region)

	vipsList, err := getVipByName(lb.network, name, lb.osAuthOpts.TenantID)
	if err != nil && err != ErrNotFound {
		return err
	}

	// We have to delete the VIP before the pool can be deleted,
	// so no point continuing if this fails.
	if len(vipsList) > 0 {
		for _, vip := range vipsList {
			// If vip is in PENDING_DELETE, skip
			if vip.Status == "PENDING_DELETE" {
				glog.V(4).Infof("The vip %s is already in PENDING_DELETE state, skipping it\n", vip.ID)
				continue
			}
			err := vips.Delete(lb.network, vip.ID).ExtractErr()
			if err != nil && !isNotFound(err) {
				return err
			}
			glog.V(4).Infof("EnsureTCPLoadBalancerDeleted: Deleted vip %s", vip.Address)
		}
		glog.V(2).Infof("EnsureTCPLoadBalancerDeleted: Deleted vips %v", vipsList)
	} else {
		glog.V(2).Infof("EnsureTCPLoadBalancerDeleted: No vips found for service:  %s", name)
	}
	var poolList []pools.Pool
	if len(vipsList) > 0 {
		for _, vip := range vipsList {
			pool, err := pools.Get(lb.network, vip.PoolID).Extract()
			if err != nil && !isNotFound(err) {
				return err
			}
			poolList = append(poolList, *pool)
		}

	} else {
		// The VIP is gone, but it is conceivable that a Pool
		// still exists that we failed to delete on some
		// previous occasion.  Make a best effort attempt to
		// cleanup any pools with the same name as the VIP.
		poolList, err = getPoolByName(lb.network, name, lb.osAuthOpts.TenantID)
		if err != nil && err != ErrNotFound {
			return err
		}
	}

	if len(poolList) > 0 {
		for _, pool := range poolList {
			// We want to explicitly delete the pool member so that we can clean up the floating ips associated
			err := lb.deletePoolMembers(pool.ID)
			for _, monId := range pool.MonitorIDs {
				//Once we support monitors for tess, Add a check here for PENDING_DELETE status
				_, err = pools.DisassociateMonitor(lb.network, pool.ID, monId).Extract()
				if err != nil {
					return err
				}

				err = monitors.Delete(lb.network, monId).ExtractErr()
				if err != nil && !isNotFound(err) {
					return err
				}
				glog.V(4).Infof("EnsureTCPLoadBalancerDeleted: Deleted Monitor %s for pool %s", monId, pool.ID)
			}
			// If pool is in PENDING_DELETE, skip
			if pool.Status == "PENDING_DELETE" {
				glog.V(4).Infof("The pool %s is already in PENDING_DELETE state, skipping it\n", pool.ID)
				continue
			}
			err = pools.Delete(lb.network, pool.ID).ExtractErr()
			if err != nil && !isNotFound(err) {
				return err
			}
			glog.V(4).Infof("EnsureTCPLoadBalancerDeleted: Deleted Pool ID: %s, Name: %s", pool.ID, pool.Name)
		}
		glog.V(2).Infof("EnsureTCPLoadBalancerDeleted: Deleted Pools %v", poolList)
	} else {
		glog.V(2).Infof("EnsureTCPLoadBalancerDeleted: No pools found for service:  %s", name)
	}

	return nil
}

func (lb *LoadBalancer) deletePoolMembers(poolid string) error {
	pager := members.List(lb.network, members.ListOpts{PoolID: poolid})
	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		memList, err := members.ExtractMembers(page)
		if err != nil {
			return false, err
		}
		for _, member := range memList {
			err = lb.deleteFloatingIP(member.Address)
			if err != nil {
				return false, err
			}
			glog.V(2).Infof("Successfully deleted floating ip: %s of the pool member: %s\n", member.Address, member.ID)
			glog.V(4).Infof("Member:%s deletion is taken care by pools.Delete, skipping it\n", member.ID)
		}
		return true, nil
	})
	return err
}

func (lb *LoadBalancer) deleteFloatingIP(floatingip string) error {
	pager := floatingips.List(lb.network, floatingips.ListOpts{FloatingIP: floatingip})
	err := pager.EachPage(func(page pagination.Page) (bool, error) {
		fips, err := floatingips.ExtractFloatingIPs(page)
		if err != nil {
			return false, err
		}
		if len(fips) == 0 {
			glog.V(4).Infof("Floating ip: %s does not exist..ignoring", floatingip)
			return true, nil
		} else if len(fips) > 1 {
			glog.Errorf("More than one 1 floating ip found for: %s", floatingip)
			return false, errors.New(fmt.Sprintf("More than one 1 floating ip found for: %s\n", floatingip))
		} else {
			res := floatingips.Delete(lb.network, fips[0].ID)
			if res.Err != nil {
				glog.Errorf("Failed to delete floating ip: %s Err: %v", floatingip, res.ErrResult)
				return false, res.Err
			}
		}
		return true, nil
	})
	return err
}

func (os *OpenStack) Zones() (cloudprovider.Zones, bool) {
	glog.V(1).Info("Claiming to support Zones")

	return os, true
}

func (os *OpenStack) GetZone() (cloudprovider.Zone, error) {
	glog.V(1).Infof("Current zone is %v", os.region)

	return cloudprovider.Zone{Region: os.region}, nil
}

func (os *OpenStack) Routes() (cloudprovider.Routes, bool) {
	return nil, false
}

// Attaches given cinder volume to the compute running kubelet
func (os *OpenStack) AttachDisk(diskName string, detachable bool, computeUUID string) (string, error) {
	disk, err := os.getVolume(diskName)
	if err != nil {
		return "", err
	}
	cClient, err := openstack.NewComputeV2(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})
	if err != nil || cClient == nil {
		glog.Errorf("Unable to initialize nova client for region: %s", os.region)
		return "", err
	}

	if len(disk.Attachments) > 0 && disk.Attachments[0]["server_id"] != nil {
		if computeUUID == disk.Attachments[0]["server_id"] {
			glog.Infof("Disk: %q is already attached to compute: %q\n", diskName, computeUUID)
			return disk.ID, nil
		} else {
			if detachable {
				glog.V(2).Infof("Disk %s is detachable.. attempting to detach from %s", disk.ID, disk.Attachments[0]["server_id"])
				if id, ok := disk.Attachments[0]["server_id"].(string); ok {
					err := os.DetachDisk(disk.ID, id)
					if err != nil {
						return "", err
					}
					glog.V(2).Infof("Disk %s detach successful from compute: %s continuing to attach with a different compute: %s", disk.ID, disk.Attachments[0]["server_id"], computeUUID)
				} else {
					glog.Errorf("Failed to find compute to which disk: %s is connected", disk.ID)
				}
			} else {
				errMsg := fmt.Sprintf("Disk %s is attached to a different compute: %s, should be detached before proceeding", diskName, disk.Attachments[0]["server_id"])
				glog.Errorf(errMsg)
				return "", errors.New(errMsg)
			}
		}
	}
	// add read only flag here if possible spothanis
	_, err = volumeattach.Create(cClient, computeUUID, &volumeattach.CreateOpts{
		VolumeID: disk.ID,
	}).Extract()
	if err != nil {
		glog.Infof("Failed to attach %s volume to %s compute", diskName, computeUUID)
		return "", err
	}
	glog.Infof("Successfully attached %s volume to %s compute", diskName, computeUUID)
	return disk.ID, nil
}

// Detaches given cinder volume from the compute running kubelet
func (os *OpenStack) DetachDisk(partialDiskId string, computeUUID string) error {
	disk, err := os.getVolume(partialDiskId)
	if err != nil {
		return err
	}

	cClient, err := openstack.NewComputeV2(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})
	if err != nil || cClient == nil {
		glog.Errorf("Unable to initialize nova client for region: %s", os.region)
		return err
	}

	if len(disk.Attachments) > 0 && disk.Attachments[0]["server_id"] != nil && computeUUID == disk.Attachments[0]["server_id"] {
		// This is a blocking call and effects kubelet's performance directly.
		// We should consider kicking it out into a separate routine, if it is bad.
		err = volumeattach.Delete(cClient, computeUUID, disk.ID).ExtractErr()
		if err != nil {
			glog.Errorf("Failed to delete volume %s from compute %s attached %v\n", disk.ID, computeUUID, err)
			return err
		}
		glog.V(2).Infof("Successfully detached volume: %s from compute: %s", disk.ID, computeUUID)
	} else {
		errMsg := fmt.Sprintf("Disk: %s has no attachments or is not attached to compute: %s\n", disk.Name, computeUUID)
		glog.Errorf(errMsg)
		return errors.New(errMsg)
	}
	return nil
}

// Takes a partial/full disk id or diskname
func (os *OpenStack) getVolume(diskName string) (volumes.Volume, error) {
	sClient, err := openstack.NewBlockStorageV1(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})

	var volume volumes.Volume
	if err != nil || sClient == nil {
		glog.Errorf("Unable to initialize cinder client for region: %s", os.region)
		return volume, err
	}

	err = volumes.List(sClient, nil).EachPage(func(page pagination.Page) (bool, error) {
		vols, err := volumes.ExtractVolumes(page)
		if err != nil {
			glog.Errorf("Failed to extract volumes: %v", err)
			return false, err
		} else {
			for _, v := range vols {
				glog.V(4).Infof("%s %s %v", v.ID, v.Name, v.Attachments)
				if v.Name == diskName || strings.Contains(v.ID, diskName) {
					volume = v
					return true, nil
				}
			}
		}
		// if it reached here then no disk with the given name was found.
		errmsg := fmt.Sprintf("Unable to find disk: %s in region %s", diskName, os.region)
		return false, errors.New(errmsg)
	})
	if err != nil {
		glog.Errorf("Error occured getting volume: %s", diskName)
		return volume, err
	}
	return volume, err
}

//This func returns namespace, and service name
func getServiceNamefromlbname(lbname string, kclient client.Interface) (string, string, error) {

	slist, err := kclient.Services(api.NamespaceAll).List(api.ListOptions{LabelSelector: labels.Everything()})
	if err != nil {
		return "", "", err
	}

	for _, srv := range slist.Items {
		expectedLBName := cloudprovider.GetLoadBalancerName(&srv)
		if strings.EqualFold(lbname, expectedLBName) {
			return srv.Namespace, srv.Name, nil
		}
	}
	return "", "", fmt.Errorf("%s: %s", ErrServiceNotFound, lbname)
}

func getKubeClient() (client.Interface, error) {
	authInfo, err := auth.LoadFromFile("/etc/sysconfig/.kubernetes_auth")
	if err != nil {
		glog.Warningf("Could not load kubernetes auth path: %v. Continuing with defaults.", err)
	}
	if authInfo == nil {
		// authInfo didn't load correctly - continue with defaults.
		authInfo = &auth.Info{}
	}

	clientConfig, err := authInfo.MergeWithConfig(restclient.Config{})
	if err != nil {
		return nil, err
	}
	glog.V(4).Infof("client config: %v, host is %s", clientConfig, clientConfig.Host)
	c, err := client.New(&clientConfig)
	if err != nil {
		return nil, err
	}
	return c, nil
}

// Get the right container port;
// It could be the one directly in the service spec or a name port defined in pod
func getContainerPort(svcPort *api.ServicePort, pod *api.Pod) (int, error) {
	portName := svcPort.TargetPort
	switch portName.Type {
	case intstr.String:
		if len(portName.StrVal) == 0 {
			return findDefaultPort(pod, svcPort.Port, svcPort.Protocol), nil
		}
		name := portName.StrVal
		for _, container := range pod.Spec.Containers {
			for _, port := range container.Ports {
				if port.Name == name && port.Protocol == svcPort.Protocol {
					return port.ContainerPort, nil
				}
			}
		}
	case intstr.Int:
		if portName.IntVal == 0 {
			return findDefaultPort(pod, svcPort.Port, svcPort.Protocol), nil
		}
		return int(portName.IntVal), nil
	}
	return 0, fmt.Errorf("no suitable port for manifest: %s", pod.UID)
}

func findDefaultPort(pod *api.Pod, servicePort int, proto api.Protocol) int {
	for _, container := range pod.Spec.Containers {
		for _, port := range container.Ports {
			if port.Protocol == proto {
				return port.ContainerPort
			}
		}
	}
	return servicePort
}

// InstanceType returns the type of the specified instance.
func (i *Instances) InstanceType(name string) (string, error) {
	return "", nil
}

// Create a volume of given size (in GiB)
func (os *OpenStack) CreateVolume(name string, size int, tags *map[string]string) (volumeName string, err error) {

	sClient, err := openstack.NewBlockStorageV1(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})

	if err != nil || sClient == nil {
		glog.Errorf("Unable to initialize cinder client for region: %s", os.region)
		return "", err
	}

	opts := volumes.CreateOpts{
		Name: name,
		Size: size,
	}
	if tags != nil {
		opts.Metadata = *tags
	}
	vol, err := volumes.Create(sClient, opts).Extract()
	if err != nil {
		glog.Errorf("Failed to create a %d GB volume: %v", size, err)
		return "", err
	}
	glog.Infof("Created volume %v", vol.ID)
	return vol.ID, err
}

func (os *OpenStack) DeleteVolume(volumeName string) error {
	sClient, err := openstack.NewBlockStorageV1(os.provider, gophercloud.EndpointOpts{
		Region: os.region,
	})

	if err != nil || sClient == nil {
		glog.Errorf("Unable to initialize cinder client for region: %s", os.region)
		return err
	}
	err = volumes.Delete(sClient, volumeName).ExtractErr()
	if err != nil {
		glog.Errorf("Cannot delete volume %s: %v", volumeName, err)
	}
	return err
}
