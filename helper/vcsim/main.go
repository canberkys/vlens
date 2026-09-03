// Standalone vCenter simulator for local integration testing of
// vlens-helper without needing a real vCenter/VPN. Not shipped in the app —
// dev-only tool. Uses govmomi's own `simulator` package (the same engine
// behind the upstream `vcsim` CLI), so this is a real SOAP/PropertyCollector
// server, not a mock — vlens-helper talks to it exactly as it would talk to
// a real vCenter.
package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"log"

	"github.com/vmware/govmomi/simulator"
)

func main() {
	addr := flag.String("l", "127.0.0.1:8989", "listen address")
	bulk := flag.Bool("bulk", false, "use a large-scale model (~1,200 VMs / 34 hosts) instead of the small default")
	flag.Parse()

	model := simulator.VPX()
	if *bulk {
		// Matches the benchmark noted in CLAUDE.md: 1200 VM / 34 host / 4
		// cluster / 12 datastore, ~0.58s for collectAll at this scale.
		model.Datacenter = 1
		model.Cluster = 4
		model.ClusterHost = 8
		model.Host = 2 // + standalone hosts outside any cluster
		model.Datastore = 12
		model.Machine = 200 // VMs per resource pool -> ~1,200 VMs total (Machine * (Cluster + Host))
	} else {
		model.Datacenter = 1
		model.Cluster = 1
		model.ClusterHost = 2
		model.Host = 1 // + standalone hosts outside any cluster
		model.Datastore = 2
		model.Machine = 5 // VMs per resource pool -> 10 VMs total, fast for quick iteration
	}

	if err := model.Create(); err != nil {
		log.Fatalf("model.Create: %v", err)
	}
	defer model.Remove()

	model.Service.TLS = new(tls.Config) // force HTTPS w/ self-signed cert (matches real vCenter/allowInsecureTLS flow)
	server := model.Service.NewServer()
	defer server.Close()

	fmt.Printf("vcsim listening at %s\n", server.URL.String())
	fmt.Println("username: user  password: pass  (vcsim accepts any credentials)")
	fmt.Println("Point vLens at this host with 'Allow self-signed certificate' ON.")

	_ = addr
	select {}
}
