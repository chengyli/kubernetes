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

package etcd

import (
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/api/rest"
	"k8s.io/kubernetes/pkg/fields"
	"k8s.io/kubernetes/pkg/labels"
	"k8s.io/kubernetes/pkg/registry/cachesize"
	"k8s.io/kubernetes/pkg/registry/generic"
	"k8s.io/kubernetes/pkg/registry/generic/registry"
	"k8s.io/kubernetes/pkg/registry/localvolumeclaim"
	"k8s.io/kubernetes/pkg/runtime"
	"k8s.io/kubernetes/pkg/apis/extensions"
)

type REST struct {
	*registry.Store
}

// NewREST returns a RESTStorage object that will work against local volume claims.
func NewREST(opts generic.RESTOptions) (*REST, *StatusREST) {
	prefix := "/localvolumeclaims"

	newListFunc := func() runtime.Object { return &extensions.LocalVolumeClaimList{} }
	storageInterface := opts.Decorator(
		opts.Storage, cachesize.GetWatchCacheSizeByResource(cachesize.LocalVolumeClaims), &extensions.LocalVolumeClaim{}, prefix, localvolumeclaim.Strategy, newListFunc)

	store := &registry.Store{
		NewFunc:     func() runtime.Object { return &extensions.LocalVolumeClaim{} },
		NewListFunc: newListFunc,
		KeyRootFunc: func(ctx api.Context) string {
			return registry.NamespaceKeyRootFunc(ctx, prefix)
		},
		KeyFunc: func(ctx api.Context, name string) (string, error) {
			return registry.NamespaceKeyFunc(ctx, prefix, name)
		},
		ObjectNameFunc: func(obj runtime.Object) (string, error) {
			return obj.(*extensions.LocalVolumeClaim).Name, nil
		},
		PredicateFunc: func(label labels.Selector, field fields.Selector) generic.Matcher {
			return localvolumeclaim.MatchLocalVolumeClaim(label, field)
		},
		QualifiedResource:       api.Resource("localvolumeclaims"),
		DeleteCollectionWorkers: opts.DeleteCollectionWorkers,

		CreateStrategy:      localvolumeclaim.Strategy,
		UpdateStrategy:      localvolumeclaim.Strategy,
		DeleteStrategy:      localvolumeclaim.Strategy,
		ReturnDeletedObject: true,

		Storage: storageInterface,
	}

	statusStore := *store
	statusStore.UpdateStrategy = localvolumeclaim.StatusStrategy

	return &REST{store}, &StatusREST{store: &statusStore}
}

// StatusREST implements the REST endpoint for changing the status of a localvolumeclaim.
type StatusREST struct {
	store *registry.Store
}

func (r *StatusREST) New() runtime.Object {
	return &extensions.LocalVolumeClaim{}
}

// Get retrieves the object from the storage. It is required to support Patch.
func (r *StatusREST) Get(ctx api.Context, name string) (runtime.Object, error) {
	return r.store.Get(ctx, name)
}

// Update alters the status subset of an object.
func (r *StatusREST) Update(ctx api.Context, name string, objInfo rest.UpdatedObjectInfo) (runtime.Object, bool, error) {
	return r.store.Update(ctx, name, objInfo)
}
