package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/vmware/govmomi/find"
	"github.com/vmware/govmomi/simulator"
	"github.com/vmware/govmomi/vapi/rest"
	"github.com/vmware/govmomi/vapi/tags"
	"github.com/vmware/govmomi/vim25"

	_ "github.com/vmware/govmomi/vapi/simulator"
)

// End-to-end collectAll against govmomi's in-process vCenter simulator,
// with exactly ONE VM tagged — the Reddit-reported shape where every
// untagged VM came back as "tags":null and the app failed to decode.
func TestCollectAllAgainstSimulatorWithPartialTags(t *testing.T) {
	simulator.Test(func(ctx context.Context, c *vim25.Client) {
		rc := rest.NewClient(c)
		if err := rc.Login(ctx, simulator.DefaultLogin); err != nil {
			t.Fatal(err)
		}
		tm := tags.NewManager(rc)
		catID, err := tm.CreateCategory(ctx, &tags.Category{Name: "env", Cardinality: "SINGLE", AssociableTypes: []string{"VirtualMachine"}})
		if err != nil {
			t.Fatal(err)
		}
		tagID, err := tm.CreateTag(ctx, &tags.Tag{Name: "prod", CategoryID: catID})
		if err != nil {
			t.Fatal(err)
		}
		vms, err := find.NewFinder(c).VirtualMachineList(ctx, "*")
		if err != nil || len(vms) < 2 {
			t.Fatalf("need >=2 simulator VMs, got %d (%v)", len(vms), err)
		}
		if err := tm.AttachTag(ctx, tagID, vms[0].Reference()); err != nil {
			t.Fatal(err)
		}

		u := *c.URL()
		u.User = simulator.DefaultLogin
		cert, err := fetchCertificate(helperRequest{URL: u.String(), Insecure: true})
		if err != nil {
			t.Fatal(err)
		}
		resp, err := collectAll(helperRequest{
			Action:              "collectAll",
			URL:                 u.String(),
			Username:            u.User.Username(),
			Password:            func() string { p, _ := u.User.Password(); return p }(),
			ExpectedFingerprint: colonFingerprint(cert.SHA256Fingerprint),
		})
		if err != nil {
			t.Fatalf("collectAll: %v", err)
		}
		data, err := json.Marshal(resp)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(data), `"tags":null`) {
			t.Fatal(`response contains "tags":null`)
		}
		tagged := 0
		for _, vm := range resp.VMs {
			if len(vm.Tags) > 0 {
				tagged++
			}
		}
		if len(resp.VMs) < 2 || tagged != 1 {
			t.Fatalf("expected exactly 1 of %d VMs tagged, got %d", len(resp.VMs), tagged)
		}
	})
}

// The app pins the colon-separated form (CertificateFingerprint.displayValue),
// which is what soap.ThumbprintSHA256 produces.
func colonFingerprint(hex string) string {
	var parts []string
	for i := 0; i+2 <= len(hex); i += 2 {
		parts = append(parts, strings.ToUpper(hex[i:i+2]))
	}
	return strings.Join(parts, ":")
}
