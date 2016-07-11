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

package local_disk

import (
	"bufio"
	"fmt"
	"os"
	"io"
	"os/exec"
	"regexp"
	"crypto/rand"
//	"strconv"

	"github.com/docker/docker/pkg/mount"
	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/apis/extensions"
//	"k8s.io/kubernetes/pkg/api/resource"
	"k8s.io/kubernetes/pkg/types"
	"k8s.io/kubernetes/pkg/util"
	"k8s.io/kubernetes/pkg/volume"
	"strings"
	"strconv"
)

const LocalDiskConfig = "/etc/sysconfig/localdisk"

const MountPoint = "/var/vol-pool/disks/%s"

// This is the primary entrypoint for volume plugins.
// The volumeConfig arg provides the ability to configure volume behavior.  It is implemented as a pointer to allow nils.
// The localDiskPlugin is used to store the volumeConfig and give it, when needed, to the func that creates LocalDisk Recyclers.
// Tests that exercise recycling should not use this func but instead use ProbeRecyclablePlugins() to override default behavior.
func ProbeVolumePlugins(volumeConfig volume.VolumeConfig) []volume.VolumePlugin {
	return []volume.VolumePlugin{
		&localDiskPlugin{
			host:               nil,
			newRecyclerFunc:    newRecycler,
			newDeleterFunc:     newDeleter,
			newProvisionerFunc: newProvisioner,
			config:             volumeConfig,
		},
	}
}

func ProbeRecyclableVolumePlugins(recyclerFunc func(pvName string, spec *volume.Spec, host volume.VolumeHost, volumeConfig volume.VolumeConfig) (volume.Recycler, error), volumeConfig volume.VolumeConfig) []volume.VolumePlugin {
	return []volume.VolumePlugin{
		&localDiskPlugin{
			host:               nil,
			newRecyclerFunc:    recyclerFunc,
			newProvisionerFunc: newProvisioner,
			config:             volumeConfig,
		},
	}
}

type localDiskPlugin struct {
	host volume.VolumeHost
	// decouple creating Recyclers/Deleters/Provisioners by deferring to a function.  Allows for easier testing.
	newRecyclerFunc    func(pvName string, spec *volume.Spec, host volume.VolumeHost, volumeConfig volume.VolumeConfig) (volume.Recycler, error)
	newDeleterFunc     func(spec *volume.Spec, host volume.VolumeHost) (volume.Deleter, error)
	newProvisionerFunc func(options volume.VolumeOptions, host volume.VolumeHost) (volume.Provisioner, error)
	config             volume.VolumeConfig
}

var _ volume.VolumePlugin = &localDiskPlugin{}
var _ volume.PersistentVolumePlugin = &localDiskPlugin{}
var _ volume.RecyclableVolumePlugin = &localDiskPlugin{}
var _ volume.DeletableVolumePlugin = &localDiskPlugin{}
var _ volume.ProvisionableVolumePlugin = &localDiskPlugin{}

const (
	localDiskPluginName = "kubernetes.io/local-disk"
	DiskVolume = "disks"
	LvmVolume = "lvm"
	ApiVersion = "extensions/v1beta1"
)

func parseConfigFile() map[string][]string {
	disks := map[string][]string{}
	file, err := os.Open(LocalDiskConfig)
	if err != nil {
		if os.IsNotExist(err) {
			glog.Errorf("Local disk config file does not exist: %s", LocalDiskConfig)
			return disks
		}
		glog.Errorf("Open file error: %v", err)
		return disks
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	voltype := ""
	for scanner.Scan() {
		line := scanner.Text()
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			voltype = strings.Trim(line, "[] ")
			if voltype != DiskVolume && voltype != LvmVolume {
				glog.Warningf("Invalid disk type: %s, can only be [disks] or [lvm]")
				voltype = ""
			}
			continue
		}
		if voltype == "" {
			continue
		}
		disks[voltype] = append(disks[voltype], line)
	}
	return disks
}

// newUUID generates a random UUID according to RFC 4122
func newUUID() (string, error) {
	uuid := make([]byte, 16)
	n, err := io.ReadFull(rand.Reader, uuid)
	if n != len(uuid) || err != nil {
		return "", err
	}
	// variant bits; see section 4.1.1
	uuid[8] = uuid[8]&^0xc0 | 0x80
	// version 4 (pseudo-random); see section 4.1.3
	uuid[6] = uuid[6]&^0xf0 | 0x40
	return fmt.Sprintf("%x-%x-%x-%x-%x", uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:]), nil
}

func registerBlockDisk(blk string, lv *extensions.LocalVolume) {
	blk = strings.TrimRight(blk, "/")
	mounts, _ := mount.GetMounts()
	for _, mnt := range mounts {
		if mnt.Source == blk {
			glog.Warningf("The device has been mounted: %s. Skip it!", blk)
			return
		}
	}

	cmd := exec.Command("/sbin/mkfs.ext4", blk)
	glog.Infof("Start to format %s", blk)
	output, err := cmd.CombinedOutput()
	if err != nil {
		glog.Warningf("Cannot format %s with error %v; output: %q", blk, err, string(output))
		return
	}

	cmd = exec.Command("blkid", blk)
	output, err = cmd.CombinedOutput()
	if err != nil {
		glog.Warningf("Cannot get block device uuid: %s, error: %v; output: %q", blk, err, string(output))
		return
	}
	uuid := string(output)
	pos := strings.Index(uuid, "UUID=")
	if pos == -1 {
		glog.Warningf("The block device has not UUID found: %s", blk)
		return
	}
	uuid = uuid[pos+len("UUID=\""):len(uuid)-1]
	pos = strings.Index(uuid, "\"")
	uuid = uuid[0:pos]

	mntPoint := fmt.Sprintf(MountPoint, uuid)

	os.MkdirAll(mntPoint, 0755)

	cmd = exec.Command("mount", blk, mntPoint)
	glog.Infof("Mount %s to %s", blk, mntPoint)
	output, err = cmd.CombinedOutput()
	if err != nil {
		glog.Warningf("Cannot mount %s to %s with error %v; output: %q", blk, mntPoint, err, string(output))
		return
	}

	size := ""
	cmd = exec.Command("df", "-B", "MB")
	output, _ = cmd.CombinedOutput()
	for _, df := range strings.Split(string(output), "\n") {
		words := strings.Fields(df)
		if len(words) != 6 {
			glog.Warningf("The output of df -H is invalid: %s", df)
			continue
		}
		if words[5] == mntPoint {
			size = words[1]
			break
		}
	}
	size = strings.TrimRight(size, "MB")
	mb, _ := strconv.Atoi(size)

	lv.Name = "lv-" + uuid
	lv.Spec.Type = "disk"
	lv.Spec.Path = mntPoint
	lv.Spec.VolumeSize = int64(mb)
	lv.Status.AvailSize = int64(mb)
}

func registerLvm(lvm string, lv *extensions.LocalVolume) {
	lvm = strings.TrimRight(lvm, "/")
	cmd := exec.Command("/usr/sbin/vgs", "--noheadings", "--nosuffix", "--units", "M", "-o", "vg_size", lvm)
	output, err := cmd.CombinedOutput()
	if err != nil {
		glog.Warningf("Cannot read vg %s size with error %v; output: %q", lvm, err, string(output))
		return
	}
	size := string(output)
	size = strings.TrimSpace(size)
	pos := strings.Index(size, ".")
	if pos != -1 {
		size = size[0:pos]
	}
	mb, _ := strconv.Atoi(size)

	uuid, _ := newUUID()
	lv.Name = "lv-" + uuid
	lv.Spec.Type = "lvm"
	lv.Spec.Path = lvm
	lv.Spec.VolumeSize = int64(mb)
	lv.Status.AvailSize = int64(mb)
}

func (plugin *localDiskPlugin) initLocalDisk() {
	if plugin.host == nil {
		return
	}

	host := plugin.host
	nodeName := host.GetHostName()
	node, err := host.GetKubeClient().Core().Nodes().Get(nodeName)
	if err != nil {
		glog.Errorf("error getting node %q: %v", nodeName, err)
		return
	}
	if node == nil {
		glog.Errorf("no node instance returned for %q", nodeName)
		return
	}

	disks := parseConfigFile()
	for disk_type, volumes := range disks {
	for _, volume := range volumes {
		lv := extensions.LocalVolume{}
		lv.Kind = "LocalVolume"
		lv.APIVersion = ApiVersion
		lv.Spec.NodeName = host.GetHostName()
		switch disk_type {
		case DiskVolume:
			registerBlockDisk(volume, &lv)
		case LvmVolume:
			registerLvm(volume, &lv)
		}
		if lv.Name == "" {
			glog.Warningf("Error found for type: %s; volume: %s", disk_type, volume)
			continue
		}
		ret, err := host.GetKubeClient().Extensions().LocalVolumes().Create(&lv)
		if err != nil {
			glog.Warningf("update LV failed:\n%+v\n%+v", ret, err)
		}
	}
	}
}

func (plugin *localDiskPlugin) Init(host volume.VolumeHost) error {
	plugin.host = host
	//
	//nodeName := host.GetNodeName()
	//node, err := host.GetKubeClient().Core().Nodes().Get(nodeName)
	//if err != nil {
	//	return fmt.Errorf("error getting node %q: %v", nodeName, err)
	//}
	//if node == nil {
	//	return fmt.Errorf("no node instance returned for %q", nodeName)
	//}
	//
	//node.Status.LDCapacity = api.LocalDiskList{
	//	"/vol-pool/localdisk1": resource.MustParse("500G"),
	//	"/vol-pool/localdisk2": resource.MustParse("500G"),
	//	"/vol-pool/localdisk3": resource.MustParse("500G"),
	//	"/vol-pool/localdisk4": resource.MustParse("500G"),
	//}
	//
	//node.Status.LDAllocatable = api.LocalDiskList{
	//	"/vol-pool/localdisk1": resource.MustParse("500G"),
	//	"/vol-pool/localdisk2": resource.MustParse("500G"),
	//	"/vol-pool/localdisk3": resource.MustParse("500G"),
	//	"/vol-pool/localdisk4": resource.MustParse("500G"),
	//}
	//
	//
	//host.GetKubeClient().Core().Nodes().UpdateStatus(node)

	go plugin.initLocalDisk()

	return nil
}

func (plugin *localDiskPlugin) GetPluginName() string {
	return localDiskPluginName
}

func (plugin *localDiskPlugin) GetVolumeName(spec *volume.Spec) (string, error) {
	volumeSource, _, err := getVolumeSource(spec)
	if err != nil {
		return "", err
	}

	return volumeSource.Path, nil
}

func (plugin *localDiskPlugin) CanSupport(spec *volume.Spec) bool {
	return (spec.PersistentVolume != nil && spec.PersistentVolume.Spec.LocalDisk != nil) ||
		(spec.Volume != nil && spec.Volume.LocalDisk != nil)
}

func (plugin *localDiskPlugin) RequiresRemount() bool {
	return false
}

func (plugin *localDiskPlugin) GetAccessModes() []api.PersistentVolumeAccessMode {
	return []api.PersistentVolumeAccessMode{
		api.ReadWriteOnce,
	}
}

func (plugin *localDiskPlugin) NewMounter(spec *volume.Spec, pod *api.Pod, _ volume.VolumeOptions) (volume.Mounter, error) {
	localDiskVolumeSource, readOnly, err := getVolumeSource(spec)
	if err != nil {
		return nil, err
	}
	return &localDiskMounter{
		localDisk: &localDisk{path: localDiskVolumeSource.Path},
		readOnly:  readOnly,
	}, nil
}

func (plugin *localDiskPlugin) NewUnmounter(volName string, podUID types.UID) (volume.Unmounter, error) {
	return &localDiskUnmounter{&localDisk{
		path: "",
	}}, nil
}

func (plugin *localDiskPlugin) NewRecycler(pvName string, spec *volume.Spec) (volume.Recycler, error) {
	return plugin.newRecyclerFunc(pvName, spec, plugin.host, plugin.config)
}

func (plugin *localDiskPlugin) NewDeleter(spec *volume.Spec) (volume.Deleter, error) {
	return plugin.newDeleterFunc(spec, plugin.host)
}

func (plugin *localDiskPlugin) NewProvisioner(options volume.VolumeOptions) (volume.Provisioner, error) {
	if len(options.AccessModes) == 0 {
		options.AccessModes = plugin.GetAccessModes()
	}
	return plugin.newProvisionerFunc(options, plugin.host)
}

func newRecycler(pvName string, spec *volume.Spec, host volume.VolumeHost, config volume.VolumeConfig) (volume.Recycler, error) {
	if spec.PersistentVolume == nil || spec.PersistentVolume.Spec.LocalDisk == nil {
		return nil, fmt.Errorf("spec.PersistentVolumeSource.LocalDisk is nil")
	}
	path := spec.PersistentVolume.Spec.LocalDisk.Path
	return &localDiskRecycler{
		name:    spec.Name(),
		path:    path,
		host:    host,
		config:  config,
		timeout: volume.CalculateTimeoutForVolume(config.RecyclerMinimumTimeout, config.RecyclerTimeoutIncrement, spec.PersistentVolume),
		pvName:  pvName,
	}, nil
}

func newDeleter(spec *volume.Spec, host volume.VolumeHost) (volume.Deleter, error) {
	if spec.PersistentVolume != nil && spec.PersistentVolume.Spec.LocalDisk == nil {
		return nil, fmt.Errorf("spec.PersistentVolumeSource.LocalDisk is nil")
	}
	path := spec.PersistentVolume.Spec.LocalDisk.Path
	return &localDiskDeleter{name: spec.Name(), path: path, host: host}, nil
}

func newProvisioner(options volume.VolumeOptions, host volume.VolumeHost) (volume.Provisioner, error) {
	return &localDiskProvisioner{options: options, host: host}, nil
}

// LocalDisk volumes represent a bare host file or directory mount.
// The direct at the specified path will be directly exposed to the container.
type localDisk struct {
	path string
	volume.MetricsNil
}

func (hp *localDisk) GetPath() string {
	return hp.path
}

type localDiskMounter struct {
	*localDisk
	readOnly bool
}

var _ volume.Mounter = &localDiskMounter{}

func (b *localDiskMounter) GetAttributes() volume.Attributes {
	return volume.Attributes{
		ReadOnly:        b.readOnly,
		Managed:         false,
		SupportsSELinux: false,
	}
}

// SetUp does nothing.
func (b *localDiskMounter) SetUp(fsGroup *int64) error {
	return nil
}

// SetUpAt does not make sense for host paths - probably programmer error.
func (b *localDiskMounter) SetUpAt(dir string, fsGroup *int64) error {
	return fmt.Errorf("SetUpAt() does not make sense for host paths")
}

func (b *localDiskMounter) GetPath() string {
	return b.path
}

type localDiskUnmounter struct {
	*localDisk
}

var _ volume.Unmounter = &localDiskUnmounter{}

// TearDown does nothing.
func (c *localDiskUnmounter) TearDown() error {
	return nil
}

// TearDownAt does not make sense for host paths - probably programmer error.
func (c *localDiskUnmounter) TearDownAt(dir string) error {
	return fmt.Errorf("TearDownAt() does not make sense for host paths")
}

// localDiskRecycler implements a Recycler for the LocalDisk plugin
// This implementation is meant for testing only and only works in a single node cluster
type localDiskRecycler struct {
	name    string
	path    string
	host    volume.VolumeHost
	config  volume.VolumeConfig
	timeout int64
	volume.MetricsNil
	pvName string
}

func (r *localDiskRecycler) GetPath() string {
	return r.path
}

// Recycle recycles/scrubs clean a LocalDisk volume.
// Recycle blocks until the pod has completed or any error occurs.
// LocalDisk recycling only works in single node clusters and is meant for testing purposes only.
func (r *localDiskRecycler) Recycle() error {
	pod := r.config.RecyclerPodTemplate
	// overrides
	pod.Spec.ActiveDeadlineSeconds = &r.timeout
	pod.Spec.Volumes[0].VolumeSource = api.VolumeSource{
		LocalDisk: &api.LocalDiskVolumeSource{
			Path: r.path,
		},
	}
	return volume.RecycleVolumeByWatchingPodUntilCompletion(r.pvName, pod, r.host.GetKubeClient())
}

// localDiskProvisioner implements a Provisioner for the LocalDisk plugin
// This implementation is meant for testing only and only works in a single node cluster.
type localDiskProvisioner struct {
	host    volume.VolumeHost
	options volume.VolumeOptions
}

// Create for localDisk simply creates a local /tmp/localdisk_pv/%s directory as a new PersistentVolume.
// This Provisioner is meant for development and testing only and WILL NOT WORK in a multi-node cluster.
func (r *localDiskProvisioner) Provision() (*api.PersistentVolume, error) {
	fullpath := fmt.Sprintf("/tmp/localdisk_pv/%s", util.NewUUID())

	pv := &api.PersistentVolume{
		ObjectMeta: api.ObjectMeta{
			Name: r.options.PVName,
			Annotations: map[string]string{
				"kubernetes.io/createdby": "localdisk-dynamic-provisioner",
			},
		},
		Spec: api.PersistentVolumeSpec{
			PersistentVolumeReclaimPolicy: r.options.PersistentVolumeReclaimPolicy,
			AccessModes:                   r.options.AccessModes,
			Capacity: api.ResourceList{
				api.ResourceName(api.ResourceStorage): r.options.Capacity,
			},
			PersistentVolumeSource: api.PersistentVolumeSource{
				LocalDisk: &api.LocalDiskVolumeSource{
					Path: fullpath,
				},
			},
		},
	}

	return pv, os.MkdirAll(pv.Spec.LocalDisk.Path, 0750)
}

// localDiskDeleter deletes a localDisk PV from the cluster.
// This deleter only works on a single host cluster and is for testing purposes only.
type localDiskDeleter struct {
	name string
	path string
	host volume.VolumeHost
	volume.MetricsNil
}

func (r *localDiskDeleter) GetPath() string {
	return r.path
}

// Delete for localDisk removes the local directory so long as it is beneath /tmp/*.
// THIS IS FOR TESTING AND LOCAL DEVELOPMENT ONLY!  This message should scare you away from using
// this deleter for anything other than development and testing.
func (r *localDiskDeleter) Delete() error {
	regexp := regexp.MustCompile("/tmp/.+")
	if !regexp.MatchString(r.GetPath()) {
		return fmt.Errorf("local_disk deleter only supports /tmp/.+ but received provided %s", r.GetPath())
	}
	return os.RemoveAll(r.GetPath())
}

func getVolumeSource(
	spec *volume.Spec) (*api.LocalDiskVolumeSource, bool, error) {
	if spec.Volume != nil && spec.Volume.LocalDisk != nil {
		return spec.Volume.LocalDisk, spec.ReadOnly, nil
	} else if spec.PersistentVolume != nil &&
		spec.PersistentVolume.Spec.LocalDisk != nil {
		return spec.PersistentVolume.Spec.LocalDisk, spec.ReadOnly, nil
	}

	return nil, false, fmt.Errorf("Spec does not reference an LocalDisk volume type")
}
