// vSphere Tags (CIS REST Tagging API, 6.5+) and Custom Attributes
// (a plain vim25 ManagedEntity property) — RVTools documents both as
// columns on nearly every tab; vLens never collected either until now.
// They're architecturally unrelated to each other despite being grouped
// in one file: Custom Attributes ride the existing SOAP PropertyCollector
// session for free, Tags need a second, separate REST session.
package main

import (
	"context"
	"fmt"
	"net/url"

	"github.com/vmware/govmomi/object"
	"github.com/vmware/govmomi/vapi/rest"
	"github.com/vmware/govmomi/vapi/tags"
	"github.com/vmware/govmomi/vim25"
	"github.com/vmware/govmomi/vim25/mo"
	"github.com/vmware/govmomi/vim25/types"
)

// newTagsManager opens a SEPARATE CIS REST session on top of the SAME
// already-pinned SOAP client. Reusing vimClient here (never constructing
// a fresh vim25.Client for this) is what makes the REST session inherit
// the pinned DialTLSContext transport from newPinnedClient — a fresh
// client would silently bypass certificate pinning. Same credentials as
// the SOAP login, no new information needed from the caller.
func newTagsManager(ctx context.Context, vimClient *vim25.Client, user *url.Userinfo) (*tags.Manager, error) {
	rc := rest.NewClient(vimClient)
	if err := rc.Login(ctx, user); err != nil {
		return nil, err
	}
	return tags.NewManager(rc), nil
}

// collectTagNames fetches every tag attached to any of refs in ONE
// batched call (GetAttachedTagsOnObjects — not one request per object),
// keyed by each object's moref Value so mapVMInfo/mapHostInfo/etc. can
// look themselves up by ID the same way folderNames/clusterNames already
// do elsewhere in this package.
func collectTagNames(ctx context.Context, tm *tags.Manager, refs []mo.Reference) (map[string][]string, error) {
	attached, err := tm.GetAttachedTagsOnObjects(ctx, refs)
	if err != nil {
		return nil, err
	}
	result := make(map[string][]string, len(attached))
	for _, a := range attached {
		if len(a.Tags) == 0 {
			continue
		}
		names := make([]string, 0, len(a.Tags))
		for _, t := range a.Tags {
			names = append(names, t.Name)
		}
		result[a.ObjectID.Reference().Value] = names
	}
	return result, nil
}

// customFieldNames resolves every custom attribute's numeric field key to
// its display name, once per collectAll call — CustomValue itself only
// ever carries the key, never a human-readable name. Tolerant of failure
// the same way collectLicenses is: some accounts can't see field
// definitions, and that shouldn't fail the whole collection.
func customFieldNames(ctx context.Context, client *vim25.Client) map[int32]string {
	names := make(map[int32]string)
	cfm, err := object.GetCustomFieldsManager(client)
	if err != nil {
		return names
	}
	defs, err := cfm.Field(ctx)
	if err != nil {
		return names
	}
	for _, d := range defs {
		names[d.Key] = d.Name
	}
	return names
}

// resolveCustomAttributes turns a ManagedEntity's raw CustomValue into
// "Key: Value" strings — mirrors LicenseInfo's Labels/Features []string +
// comma-join pattern on the Swift side rather than inventing a key-value
// model type.
func resolveCustomAttributes(raw []types.BaseCustomFieldValue, fieldNames map[int32]string) []string {
	result := make([]string, 0, len(raw))
	for _, v := range raw {
		sv, ok := v.(*types.CustomFieldStringValue)
		if !ok || sv.Value == "" {
			continue
		}
		name, ok := fieldNames[sv.Key]
		if !ok {
			continue
		}
		result = append(result, fmt.Sprintf("%s: %s", name, sv.Value))
	}
	return result
}
