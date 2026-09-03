// Dev-only scratch tool: creates a real VirtualApp on the default resource
// pool, purely to exercise vLens's vApp collector against vcsim (whose
// default model doesn't create any vApp instances on its own). Not part of
// the shipped app — mirrors mksnap's pattern.
package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"

	"github.com/vmware/govmomi"
	"github.com/vmware/govmomi/find"
	"github.com/vmware/govmomi/object"
	"github.com/vmware/govmomi/vim25/soap"
	"github.com/vmware/govmomi/vim25/types"
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

	f := find.NewFinder(c.Client, true)
	dc, err := f.DefaultDatacenter(ctx)
	if err != nil {
		log.Fatal(err)
	}
	f.SetDatacenter(dc)

	pools, err := f.ResourcePoolList(ctx, "*")
	if err != nil {
		log.Fatal(err)
	}
	if len(pools) == 0 {
		log.Fatal("no resource pools found")
	}
	var pool *object.ResourcePool
	for _, p := range pools {
		fmt.Println("pool:", p.InventoryPath, p.Reference().Value)
		if pool == nil && strings.Contains(p.InventoryPath, "_C0/Resources") {
			pool = p
		}
	}
	if pool == nil {
		pool = pools[0]
	}
	folder, err := f.DefaultFolder(ctx)
	if err != nil {
		log.Fatal(err)
	}

	// vcsim's ResourcePool.createChild requires every allocation field set
	// (see simulator/resource_pool.go's allResourceFieldsSet) — a zero-value
	// spec fails with InvalidArgument, found by testing against the real
	// simulator rather than guessing.
	reservation, limit := int64(0), int64(-1)
	expandable := true
	shares := types.SharesInfo{Level: types.SharesLevelNormal}
	allocation := types.ResourceAllocationInfo{
		Reservation:           &reservation,
		Limit:                 &limit,
		ExpandableReservation: &expandable,
		Shares:                &shares,
	}
	resSpec := types.ResourceConfigSpec{
		CpuAllocation:    allocation,
		MemoryAllocation: allocation,
	}
	configSpec := types.VAppConfigSpec{
		VmConfigSpec: types.VmConfigSpec{
			Product: []types.VAppProductSpec{
				{
					ArrayUpdateSpec: types.ArrayUpdateSpec{Operation: types.ArrayUpdateOperationAdd},
					Info:            &types.VAppProductInfo{Name: "vLens Test App", Vendor: "vLens", Version: "1.0"},
				},
			},
		},
	}

	fmt.Println("creating vApp on pool", pool.Reference().Value)
	vapp, err := pool.CreateVApp(ctx, "test-vApp", resSpec, configSpec, folder)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("done:", vapp.Reference().Value)
}
