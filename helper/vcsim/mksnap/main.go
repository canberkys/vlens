// Dev-only scratch tool: creates a snapshot on the first VM found, purely
// to exercise vLens's snapshot-size calculation against vcsim. Not part of
// the shipped app.
package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"

	"github.com/vmware/govmomi"
	"github.com/vmware/govmomi/find"
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

	f := find.NewFinder(c.Client, true)
	dc, err := f.DefaultDatacenter(ctx)
	if err != nil {
		log.Fatal(err)
	}
	f.SetDatacenter(dc)

	vms, err := f.VirtualMachineList(ctx, "*")
	if err != nil {
		log.Fatal(err)
	}
	if len(vms) == 0 {
		log.Fatal("no VMs found")
	}
	vm := vms[0]
	fmt.Println("creating snapshot on", vm.Name())

	task, err := vm.CreateSnapshot(ctx, "test-snapshot", "created by mksnap for size testing", false, false)
	if err != nil {
		log.Fatal(err)
	}
	if err := task.Wait(ctx); err != nil {
		log.Fatal(err)
	}
	fmt.Println("done")
}
