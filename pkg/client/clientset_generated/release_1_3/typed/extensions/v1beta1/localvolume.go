/*
Copyright 2016 The Kubernetes Authors All rights reserved.

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

package v1beta1

import (
	api "k8s.io/kubernetes/pkg/api"
	v1beta1 "k8s.io/kubernetes/pkg/apis/extensions/v1beta1"
	watch "k8s.io/kubernetes/pkg/watch"
)

// LocalVolumesGetter has a method to return a LocalVolumeInterface.
// A group's client should implement this interface.
type LocalVolumesGetter interface {
	LocalVolumes() LocalVolumeInterface
}

// LocalVolumeInterface has methods to work with LocalVolume resources.
type LocalVolumeInterface interface {
	Create(*v1beta1.LocalVolume) (*v1beta1.LocalVolume, error)
	Update(*v1beta1.LocalVolume) (*v1beta1.LocalVolume, error)
	UpdateStatus(*v1beta1.LocalVolume) (*v1beta1.LocalVolume, error)
	Delete(name string, options *api.DeleteOptions) error
	DeleteCollection(options *api.DeleteOptions, listOptions api.ListOptions) error
	Get(name string) (*v1beta1.LocalVolume, error)
	List(opts api.ListOptions) (*v1beta1.LocalVolumeList, error)
	Watch(opts api.ListOptions) (watch.Interface, error)
	LocalVolumeExpansion
}

// localVolumes implements LocalVolumeInterface
type localVolumes struct {
	client *ExtensionsClient
}

// newLocalVolumes returns a LocalVolumes
func newLocalVolumes(c *ExtensionsClient) *localVolumes {
	return &localVolumes{
		client: c,
	}
}

// Create takes the representation of a localVolume and creates it.  Returns the server's representation of the localVolume, and an error, if there is any.
func (c *localVolumes) Create(localVolume *v1beta1.LocalVolume) (result *v1beta1.LocalVolume, err error) {
	result = &v1beta1.LocalVolume{}
	err = c.client.Post().
		Resource("localvolumes").
		Body(localVolume).
		Do().
		Into(result)
	return
}

// Update takes the representation of a localVolume and updates it. Returns the server's representation of the localVolume, and an error, if there is any.
func (c *localVolumes) Update(localVolume *v1beta1.LocalVolume) (result *v1beta1.LocalVolume, err error) {
	result = &v1beta1.LocalVolume{}
	err = c.client.Put().
		Resource("localvolumes").
		Name(localVolume.Name).
		Body(localVolume).
		Do().
		Into(result)
	return
}

func (c *localVolumes) UpdateStatus(localVolume *v1beta1.LocalVolume) (result *v1beta1.LocalVolume, err error) {
	result = &v1beta1.LocalVolume{}
	err = c.client.Put().
		Resource("localvolumes").
		Name(localVolume.Name).
		SubResource("status").
		Body(localVolume).
		Do().
		Into(result)
	return
}

// Delete takes name of the localVolume and deletes it. Returns an error if one occurs.
func (c *localVolumes) Delete(name string, options *api.DeleteOptions) error {
	return c.client.Delete().
		Resource("localvolumes").
		Name(name).
		Body(options).
		Do().
		Error()
}

// DeleteCollection deletes a collection of objects.
func (c *localVolumes) DeleteCollection(options *api.DeleteOptions, listOptions api.ListOptions) error {
	return c.client.Delete().
		Resource("localvolumes").
		VersionedParams(&listOptions, api.ParameterCodec).
		Body(options).
		Do().
		Error()
}

// Get takes name of the localVolume, and returns the corresponding localVolume object, and an error if there is any.
func (c *localVolumes) Get(name string) (result *v1beta1.LocalVolume, err error) {
	result = &v1beta1.LocalVolume{}
	err = c.client.Get().
		Resource("localvolumes").
		Name(name).
		Do().
		Into(result)
	return
}

// List takes label and field selectors, and returns the list of LocalVolumes that match those selectors.
func (c *localVolumes) List(opts api.ListOptions) (result *v1beta1.LocalVolumeList, err error) {
	result = &v1beta1.LocalVolumeList{}
	err = c.client.Get().
		Resource("localvolumes").
		VersionedParams(&opts, api.ParameterCodec).
		Do().
		Into(result)
	return
}

// Watch returns a watch.Interface that watches the requested localVolumes.
func (c *localVolumes) Watch(opts api.ListOptions) (watch.Interface, error) {
	return c.client.Get().
		Prefix("watch").
		Resource("localvolumes").
		VersionedParams(&opts, api.ParameterCodec).
		Watch()
}
