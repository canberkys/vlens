// Dev-only scratch tool: creates a real tag category + tag via the CIS
// REST Tagging API and attaches it to the first VM, host, cluster, and
// datastore vcsim's default model produces — purely to give
// vlens-helper's Tags collector (helper/tags.go) something real to find.
// vcsim needs helper/vcsim/main.go's vapi/simulator blank import running
// for this to work at all. Mirrors mkvapp's pattern.
package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"

	"github.com/vmware/govmomi"
	"github.com/vmware/govmomi/find"
	"github.com/vmware/govmomi/object"
	"github.com/vmware/govmomi/vapi/rest"
	"github.com/vmware/govmomi/vapi/tags"
	"github.com/vmware/govmomi/vim25/mo"
	"github.com/vmware/govmomi/vim25/soap"
)

func main() {
	ctx := context.Background()
	u, err := soap.ParseURL(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	u.User = url.UserPassword("user", "pass")

	c, err := govmomi.NewClient(ctx, u, true)
	if err != nil {
		log.Fatal(err)
	}

	rc := rest.NewClient(c.Client)
	if err := rc.Login(ctx, u.User); err != nil {
		log.Fatal("REST login: ", err)
	}
	tm := tags.NewManager(rc)

	catID, err := tm.CreateCategory(ctx, &tags.Category{
		Name:            "vlens-test-category",
		Cardinality:     "MULTIPLE",
		AssociableTypes: []string{"VirtualMachine", "HostSystem", "ClusterComputeResource", "Datastore"},
	})
	if err != nil {
		log.Fatal("CreateCategory: ", err)
	}

	tagID, err := tm.CreateTag(ctx, &tags.Tag{Name: "vlens-test-tag", CategoryID: catID})
	if err != nil {
		log.Fatal("CreateTag: ", err)
	}

	f := find.NewFinder(c.Client, true)
	dc, err := f.DefaultDatacenter(ctx)
	if err != nil {
		log.Fatal(err)
	}
	f.SetDatacenter(dc)

	vms, err := f.VirtualMachineList(ctx, "*")
	if err != nil || len(vms) == 0 {
		log.Fatal("no VMs found: ", err)
	}
	hosts, err := f.HostSystemList(ctx, "*")
	if err != nil || len(hosts) == 0 {
		log.Fatal("no hosts found: ", err)
	}
	clusters, err := f.ClusterComputeResourceList(ctx, "*")
	if err != nil || len(clusters) == 0 {
		log.Fatal("no clusters found: ", err)
	}
	datastores, err := f.DatastoreList(ctx, "*")
	if err != nil || len(datastores) == 0 {
		log.Fatal("no datastores found: ", err)
	}

	targets := []mo.Reference{vms[0].Reference(), hosts[0].Reference(), clusters[0].Reference(), datastores[0].Reference()}
	for _, ref := range targets {
		if err := tm.AttachTag(ctx, tagID, ref); err != nil {
			log.Fatalf("AttachTag to %s: %v", ref.Reference().Value, err)
		}
	}

	fmt.Println("tagged VM:", vms[0].Reference().Value, vms[0].InventoryPath)
	fmt.Println("tagged host:", hosts[0].Reference().Value, hosts[0].InventoryPath)
	fmt.Println("tagged cluster:", clusters[0].Reference().Value, clusters[0].InventoryPath)
	fmt.Println("tagged datastore:", datastores[0].Reference().Value, datastores[0].InventoryPath)
	fmt.Println("tag:", tagID, "category:", catID)

	// Custom Attributes — plain SOAP CustomFieldsManager, unrelated to the
	// REST tagging session above, just bundled here for one-shot testing.
	cfm := object.NewCustomFieldsManager(c.Client)
	fieldDef, err := cfm.Add(ctx, "vlens-test-field", "VirtualMachine", nil, nil)
	if err != nil {
		log.Fatal("CustomFieldsManager.Add: ", err)
	}
	if err := cfm.Set(ctx, vms[0].Reference(), fieldDef.Key, "vlens-test-value"); err != nil {
		log.Fatal("CustomFieldsManager.Set: ", err)
	}
	fmt.Println("set custom attribute on VM:", fieldDef.Name, "=", "vlens-test-value")
}
