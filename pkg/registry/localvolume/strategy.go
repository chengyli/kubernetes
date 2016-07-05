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

package localvolume

import (
	"fmt"
	"reflect"

	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/apis/extensions"
	"k8s.io/kubernetes/pkg/apis/extensions/validation"
	"k8s.io/kubernetes/pkg/fields"
	"k8s.io/kubernetes/pkg/labels"
	"k8s.io/kubernetes/pkg/registry/generic"
	"k8s.io/kubernetes/pkg/runtime"
	"k8s.io/kubernetes/pkg/util/validation/field"
)

// localVolumeStrategy implements verification logic for LocalVolumes.
type localVolumeStrategy struct {
	runtime.ObjectTyper
	api.NameGenerator
}

// Strategy is the default logic that applies when creating and updating LocalVolume objects.
var Strategy = localVolumeStrategy{api.Scheme, api.SimpleNameGenerator}

func (localVolumeStrategy) NamespaceScoped() bool {
	return false
}

// PrepareForCreate clears the status of an LocalVolume before creation.
func (localVolumeStrategy) PrepareForCreate(obj runtime.Object) {
	//localVolume := obj.(*extensions.LocalVolume)
	//localVolume.Generation = 1
}

// PrepareForUpdate clears fields that are not allowed to be set by end users on update.
func (localVolumeStrategy) PrepareForUpdate(obj, old runtime.Object) {
	return
	newLocalVolume := obj.(*extensions.LocalVolume)
	oldLocalVolume := old.(*extensions.LocalVolume)

	// Any changes to the spec increment the generation number, any changes to the
	// status should reflect the generation number of the corresponding object.
	// See api.ObjectMeta description for more information on Generation.
	if !reflect.DeepEqual(oldLocalVolume.Spec, newLocalVolume.Spec) {
		newLocalVolume.Generation = oldLocalVolume.Generation + 1
	}
}

// Validate validates a new LocalVolume.
func (localVolumeStrategy) Validate(ctx api.Context, obj runtime.Object) field.ErrorList {
	localVolume := obj.(*extensions.LocalVolume)
	return validation.ValidateLocalVolume(localVolume)
}

// Canonicalize normalizes the object after validation.
func (localVolumeStrategy) Canonicalize(obj runtime.Object) {
}

// AllowCreateOnUpdate is false for LocalVolume; this means you may not create one with a PUT request.
func (localVolumeStrategy) AllowCreateOnUpdate() bool {
	return true
}

// ValidateUpdate is the default update validation for an end user.
func (localVolumeStrategy) ValidateUpdate(ctx api.Context, obj, old runtime.Object) field.ErrorList {
	validationErrorList := validation.ValidateLocalVolume(obj.(*extensions.LocalVolume))
	updateErrorList := validation.ValidateLocalVolumeUpdate(obj.(*extensions.LocalVolume), old.(*extensions.LocalVolume))
	return append(validationErrorList, updateErrorList...)
}

// AllowUnconditionalUpdate is the default update policy for LocalVolume objects.
func (localVolumeStrategy) AllowUnconditionalUpdate() bool {
	return true
}

// LocalVolumeToSelectableFields returns a field set that represents the object.
func LocalVolumeToSelectableFields(localVolume *extensions.LocalVolume) fields.Set {
	return generic.ObjectMetaFieldsSet(localVolume.ObjectMeta, true)
}

// MatchLocalVolume is the filter used by the generic etcd backend to watch events
// from etcd to clients of the apiserver only interested in specific labels/fields.
func MatchLocalVolume(label labels.Selector, field fields.Selector) generic.Matcher {
	return &generic.SelectionPredicate{
		Label: label,
		Field: field,
		GetAttrs: func(obj runtime.Object) (labels.Set, fields.Set, error) {
			localVolume, ok := obj.(*extensions.LocalVolume)
			if !ok {
				return nil, nil, fmt.Errorf("given object is not a LocalVolume.")
			}
			return labels.Set(localVolume.ObjectMeta.Labels), LocalVolumeToSelectableFields(localVolume), nil
		},
	}
}
