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

package unversioned

import (
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/apis/extensions"
	"k8s.io/kubernetes/pkg/watch"
)

// LocalVolumeNamespacer has methods to work with LocalVolume resources in a namespace
type LocalVolumeNamespacer interface {
	LocalVolumes() LocalVolumeInterface
}

// LocalVolumeInterface exposes methods to work on LocalVolume resources.
type LocalVolumeInterface interface {
	List(opts api.ListOptions) (*extensions.LocalVolumeList, error)
	Get(name string) (*extensions.LocalVolume, error)
	Create(localVolume *extensions.LocalVolume) (*extensions.LocalVolume, error)
	Update(localVolume *extensions.LocalVolume) (*extensions.LocalVolume, error)
	Delete(name string, options *api.DeleteOptions) error
	Watch(opts api.ListOptions) (watch.Interface, error)
}

// LocalVolumes implements LocalVolumeNamespacer interface
type LocalVolumes struct {
	r  *ExtensionsClient
}

// newLocalVolumes returns a LocalVolumes
func newLocalVolumes(c *ExtensionsClient) *LocalVolumes {
	return &LocalVolumes{c}
}

// List returns a list of localVolume that match the label and field selectors.
func (c *LocalVolumes) List(opts api.ListOptions) (result *extensions.LocalVolumeList, err error) {
	result = &extensions.LocalVolumeList{}
	err = c.r.Get().Resource("localvolumes").VersionedParams(&opts, api.ParameterCodec).Do().Into(result)
	return
}

// Get returns information about a particular localVolume.
func (c *LocalVolumes) Get(name string) (result *extensions.LocalVolume, err error) {
	result = &extensions.LocalVolume{}
	err = c.r.Get().Resource("localvolumes").Name(name).Do().Into(result)
	return
}

// Create creates a new localVolume.
func (c *LocalVolumes) Create(localVolume *extensions.LocalVolume) (result *extensions.LocalVolume, err error) {
	result = &extensions.LocalVolume{}
	err = c.r.Post().Resource("localvolumes").Body(localVolume).Do().Into(result)
	return
}

// Update updates an existing localVolume.
func (c *LocalVolumes) Update(localVolume *extensions.LocalVolume) (result *extensions.LocalVolume, err error) {
	result = &extensions.LocalVolume{}
	err = c.r.Put().Resource("localvolumes").Name(localVolume.Name).Body(localVolume).Do().Into(result)
	return
}

// Delete deletes a localVolume, returns error if one occurs.
func (c *LocalVolumes) Delete(name string, options *api.DeleteOptions) (err error) {
	return c.r.Delete().Resource("localvolumes").Name(name).Body(options).Do().Error()
}

// Watch returns a watch.Interface that watches the requested localVolume.
func (c *LocalVolumes) Watch(opts api.ListOptions) (watch.Interface, error) {
	return c.r.Get().
	Prefix("watch").
	Resource("localvolumes").
	VersionedParams(&opts, api.ParameterCodec).
	Watch()
}
