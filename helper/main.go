// vlens-helper collects vSphere inventory data via govmomi (the same
// library behind Terraform/Packer/k8s' vsphere provider) and speaks a
// small JSON protocol over stdin/stdout to the SwiftUI app that embeds it.
// One process per request for the MVP — see VSphereHelperClient.swift for
// the rationale. Keep the request/response structs here in sync by hand
// with Sources/vLensCore/Helper/HelperProtocol.swift and Models/*.swift.
package main

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/vmware/govmomi"
	"github.com/vmware/govmomi/license"
	"github.com/vmware/govmomi/performance"
	"github.com/vmware/govmomi/property"
	"github.com/vmware/govmomi/session"
	"github.com/vmware/govmomi/view"
	"github.com/vmware/govmomi/vim25"
	"github.com/vmware/govmomi/vim25/mo"
	"github.com/vmware/govmomi/vim25/soap"
	"github.com/vmware/govmomi/vim25/types"
)

// ---------- protocol ----------

type helperRequest struct {
	Action   string `json:"action"`
	URL      string `json:"url"`
	Username string `json:"username"`
	Password string `json:"password"`
	// Kept only for `getCertificate` (a raw, credential-free TLS probe that
	// has nothing to pin against yet — see fetchCertificate). `collectAll`/
	// `collectPerformance` ignore this and always require ExpectedFingerprint
	// instead; see newPinnedClient's doc comment for why.
	Insecure            bool   `json:"insecure"`
	ExpectedFingerprint string `json:"expectedFingerprint,omitempty"`
	PerfIntervalMinutes int    `json:"perfIntervalMinutes,omitempty"`
}

type helperResponse struct {
	OK            bool                 `json:"ok"`
	Error         *string              `json:"error"`
	VMs           []virtualMachineInfo `json:"vms"`
	CPUs          []vmCPUInfo          `json:"cpus"`
	Memory        []vmMemoryInfo       `json:"memory"`
	Disks         []vmDiskInfo         `json:"disks"`
	Snapshots     []vmSnapshotInfo     `json:"snapshots"`
	Tools         []vmToolsInfo        `json:"tools"`
	Hosts         []hostInfo           `json:"hosts"`
	Datastores    []datastoreInfo      `json:"datastores"`
	Clusters      []clusterInfo        `json:"clusters"`
	Licenses      []licenseInfo        `json:"licenses"`
	VSwitches     []vSwitchInfo        `json:"vSwitches"`
	Ports         []vPortInfo          `json:"ports"`
	DVSwitches    []dvSwitchInfo       `json:"dvSwitches"`
	DVPorts       []dvPortInfo         `json:"dvPorts"`
	ResourcePools []resourcePoolInfo   `json:"resourcePools"`
	VApps         []vAppInfo           `json:"vApps"`
	HBAs          []hbaInfo            `json:"hbas"`
	Nics          []nicInfo            `json:"nics"`
	VMKernels     []vmkInfo            `json:"vmKernels"`
	Multipaths    []multipathInfo      `json:"multipaths"`
	CDs           []cdInfo             `json:"cds"`
	USBs          []usbInfo            `json:"usbs"`
	Partitions    []partitionInfo      `json:"partitions"`
	Networks      []vmNetworkInfo      `json:"networks"`
	Performance   []vmPerformanceInfo  `json:"performance"`
	// Present whenever `Performance` is, so the caller can tell "collected
	// every powered-on VM" apart from "collected some, then a batch failed"
	// apart from "the very first batch failed" instead of all three looking
	// like an equally clean (if possibly empty) result.
	PerformanceCoverage *performanceCoverage `json:"performanceCoverage,omitempty"`
	VCenter             *vCenterInfo         `json:"vCenter"`
	Certificate         *certificateInfo     `json:"certificate"`
}

// certificateInfo backs trust-on-first-use (see Sources/vLensCore/CertificateTrust.swift).
// Fetched via a raw TLS dial, deliberately without a full vCenter login —
// the whole point is to inspect the certificate *before* deciding whether
// to trust the connection at all.
type certificateInfo struct {
	SHA256Fingerprint string `json:"sha256Fingerprint"`
	Subject           string `json:"subject"`
	Issuer            string `json:"issuer"`
	NotAfter          string `json:"notAfter"`
}

type virtualMachineInfo struct {
	Name              string  `json:"name"`
	PowerState        string  `json:"powerState"`
	Template          bool    `json:"template"`
	GuestOSFullName   *string `json:"guestOSFullName"`
	CPUCount          int     `json:"cpuCount"`
	MemoryMiB         int     `json:"memoryMiB"`
	HostName          string  `json:"hostName"`
	ClusterName       *string `json:"clusterName"`
	ResourcePoolName  *string `json:"resourcePoolName"`
	PrimaryIPAddress  *string `json:"primaryIPAddress"`
	VMwareToolsStatus *string `json:"vmwareToolsStatus"`
	VMUUID            string  `json:"vmUUID"`
	// Not a vInfo column — carried only for the vHealth "consolidation
	// needed" rule (see HealthCheckEngine.swift), matching the doc comment's
	// "don't pre-model fields nothing reads" rule: this one is read.
	ConsolidationNeeded bool `json:"consolidationNeeded"`
}

type vmCPUInfo struct {
	ID               string  `json:"id"`
	VMName           string  `json:"vmName"`
	PowerState       string  `json:"powerState"`
	CPUCount         int     `json:"cpuCount"`
	Sockets          int     `json:"sockets"`
	CoresPerSocket   int     `json:"coresPerSocket"`
	OverallUsageMHz  *int    `json:"overallUsageMHz"`
	ReservationMHz   int     `json:"reservationMHz"`
	LimitMHz         int     `json:"limitMHz"`
	HotAddEnabled    bool    `json:"hotAddEnabled"`
	HotRemoveEnabled bool    `json:"hotRemoveEnabled"`
	HostName         string  `json:"hostName"`
	ClusterName      *string `json:"clusterName"`
}

type vmMemoryInfo struct {
	ID             string  `json:"id"`
	VMName         string  `json:"vmName"`
	PowerState     string  `json:"powerState"`
	SizeMiB        int     `json:"sizeMiB"`
	OverheadMiB    *int    `json:"overheadMiB"`
	ConsumedMiB    *int    `json:"consumedMiB"`
	ActiveMiB      *int    `json:"activeMiB"`
	SharedMiB      *int    `json:"sharedMiB"`
	SwappedMiB     *int    `json:"swappedMiB"`
	BalloonedMiB   *int    `json:"balloonedMiB"`
	ReservationMiB int     `json:"reservationMiB"`
	LimitMiB       int     `json:"limitMiB"`
	HotAddEnabled  bool    `json:"hotAddEnabled"`
	HostName       string  `json:"hostName"`
	ClusterName    *string `json:"clusterName"`
}

type vmDiskInfo struct {
	ID              string `json:"id"`
	VMName          string `json:"vmName"`
	PowerState      string `json:"powerState"`
	DiskLabel       string `json:"diskLabel"`
	CapacityMiB     int    `json:"capacityMiB"`
	ThinProvisioned bool   `json:"thinProvisioned"`
	DiskMode        string `json:"diskMode"`
	Controller      string `json:"controller"`
	UnitNumber      int    `json:"unitNumber"`
	DatastorePath   string `json:"datastorePath"`
	HostName        string `json:"hostName"`
}

type vmSnapshotInfo struct {
	ID                  string  `json:"id"`
	VMName              string  `json:"vmName"`
	PowerState          string  `json:"powerState"`
	SnapshotName        string  `json:"snapshotName"`
	SnapshotDescription *string `json:"snapshotDescription"`
	CreatedDate         string  `json:"createdDate"` // ISO8601 — Swift side must use .iso8601 date decoding
	SizeMiBTotal        *int    `json:"sizeMiBTotal"`
	Quiesced            bool    `json:"quiesced"`
	HostName            string  `json:"hostName"`
	ClusterName         *string `json:"clusterName"`
}

type vmToolsInfo struct {
	ID              string  `json:"id"`
	VMName          string  `json:"vmName"`
	PowerState      string  `json:"powerState"`
	HardwareVersion string  `json:"hardwareVersion"`
	ToolsStatus     string  `json:"toolsStatus"`
	ToolsVersion    *string `json:"toolsVersion"`
	HostName        string  `json:"hostName"`
	ClusterName     *string `json:"clusterName"`
}

type hostInfo struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	DatacenterName     *string  `json:"datacenterName"`
	ClusterName        *string  `json:"clusterName"`
	ConfigStatus       string   `json:"configStatus"`
	CPUModel           string   `json:"cpuModel"`
	CPUMhz             int      `json:"cpuMhz"`
	NumCPUCores        int      `json:"numCpuCores"`
	NumCPUThreads      int      `json:"numCpuThreads"`
	CPUUsagePercent    *float64 `json:"cpuUsagePercent"`
	MemoryTotalMiB     int      `json:"memoryTotalMiB"`
	MemoryUsagePercent *float64 `json:"memoryUsagePercent"`
	NumNics            int      `json:"numNics"`
	NumHbas            int      `json:"numHbas"`
	NumVMsTotal        int      `json:"numVMsTotal"`
	NumVMsRunning      int      `json:"numVMsRunning"`
	EsxVersion         string   `json:"esxVersion"`
	EsxBuild           string   `json:"esxBuild"`
	Vendor             *string  `json:"vendor"`
	Model              *string  `json:"model"`
	MaintenanceMode    bool     `json:"maintenanceMode"`
}

type datastoreInfo struct {
	ID                string  `json:"id"`
	Name              string  `json:"name"`
	Type              string  `json:"type"`
	CapacityMiB       int     `json:"capacityMiB"`
	FreeMiB           int     `json:"freeMiB"`
	NumVMsTotal       int     `json:"numVMsTotal"`
	NumHostsConnected int     `json:"numHostsConnected"`
	URL               *string `json:"url"`
}

type clusterInfo struct {
	ID                      string  `json:"id"`
	Name                    string  `json:"name"`
	ConfigStatus            string  `json:"configStatus"`
	NumHosts                int     `json:"numHosts"`
	NumEffectiveHosts       int     `json:"numEffectiveHosts"`
	TotalCPUMHz             int     `json:"totalCpuMHz"`
	TotalMemoryMiB          int     `json:"totalMemoryMiB"`
	HAEnabled               bool    `json:"haEnabled"`
	AdmissionControlEnabled bool    `json:"admissionControlEnabled"`
	DRSEnabled              bool    `json:"drsEnabled"`
	DRSDefaultVMBehavior    *string `json:"drsDefaultVMBehavior"`
}

type licenseInfo struct {
	Name           string   `json:"name"`
	Key            string   `json:"key"`
	Labels         []string `json:"labels"`
	CostUnit       string   `json:"costUnit"`
	Total          int      `json:"total"`
	Used           int      `json:"used"`
	ExpirationDate *string  `json:"expirationDate"`
	Features       []string `json:"features"`
}

type vSwitchInfo struct {
	ID                string `json:"id"`
	HostName          string `json:"hostName"`
	Name              string `json:"name"`
	NumPorts          int    `json:"numPorts"`
	NumPortsAvailable int    `json:"numPortsAvailable"`
	MTU               int    `json:"mtu"`
	NumUplinks        int    `json:"numUplinks"`
	NumPortGroups     int    `json:"numPortGroups"`
}

type vPortInfo struct {
	ID         string `json:"id"`
	HostName   string `json:"hostName"`
	SwitchName string `json:"switchName"`
	Name       string `json:"name"`
	VLANID     int    `json:"vlanId"`
}

type dvSwitchInfo struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	UUID          string `json:"uuid"`
	NumPorts      int    `json:"numPorts"`
	NumHosts      int    `json:"numHosts"`
	NumPortGroups int    `json:"numPortGroups"`
}

type dvPortInfo struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	SwitchName string `json:"switchName"`
	NumPorts   int    `json:"numPorts"`
	VLANID     *int   `json:"vlanId"`
}

type resourcePoolInfo struct {
	ID                   string  `json:"id"`
	Name                 string  `json:"name"`
	OwnerName            *string `json:"ownerName"`
	CPUReservationMHz    int     `json:"cpuReservationMHz"`
	CPULimitMHz          int     `json:"cpuLimitMHz"`
	MemoryReservationMiB int     `json:"memoryReservationMiB"`
	MemoryLimitMiB       int     `json:"memoryLimitMiB"`
	NumVMs               int     `json:"numVMs"`
}

type vAppInfo struct {
	ID             string  `json:"id"`
	Name           string  `json:"name"`
	OwnerName      *string `json:"ownerName"`
	NumVMs         int     `json:"numVMs"`
	ProductName    *string `json:"productName"`
	ProductVersion *string `json:"productVersion"`
}

type hbaInfo struct {
	ID       string `json:"id"`
	HostName string `json:"hostName"`
	Device   string `json:"device"`
	Model    string `json:"model"`
	Driver   string `json:"driver"`
	Status   string `json:"status"`
}

type nicInfo struct {
	ID          string  `json:"id"`
	HostName    string  `json:"hostName"`
	Device      string  `json:"device"`
	MAC         string  `json:"mac"`
	LinkSpeedMb *int    `json:"linkSpeedMb"`
	Driver      *string `json:"driver"`
}

type vmkInfo struct {
	ID        string  `json:"id"`
	HostName  string  `json:"hostName"`
	Device    string  `json:"device"`
	PortGroup string  `json:"portGroup"`
	IPAddress *string `json:"ipAddress"`
	MAC       string  `json:"mac"`
}

type multipathInfo struct {
	ID               string   `json:"id"`
	HostName         string   `json:"hostName"`
	Disk             string   `json:"disk"`
	DisplayName      string   `json:"displayName"`
	NumPaths         int      `json:"numPaths"`
	OperationalState []string `json:"operationalState"`
	Vendor           string   `json:"vendor"`
	Model            string   `json:"model"`
}

type cdInfo struct {
	ID         string  `json:"id"`
	VMName     string  `json:"vmName"`
	PowerState string  `json:"powerState"`
	Connected  bool    `json:"connected"`
	ISOPath    *string `json:"isoPath"`
	DeviceName *string `json:"deviceName"`
}

type usbInfo struct {
	ID         string `json:"id"`
	VMName     string `json:"vmName"`
	PowerState string `json:"powerState"`
	Connected  bool   `json:"connected"`
	Vendor     *int   `json:"vendor"`
	Product    *int   `json:"product"`
}

type partitionInfo struct {
	ID          string `json:"id"`
	VMName      string `json:"vmName"`
	DiskPath    string `json:"diskPath"`
	CapacityMiB int    `json:"capacityMiB"`
	FreeMiB     int    `json:"freeMiB"`
}

type vmNetworkInfo struct {
	ID          string  `json:"id"`
	VMName      string  `json:"vmName"`
	PowerState  string  `json:"powerState"`
	NICLabel    string  `json:"nicLabel"`
	AdapterType string  `json:"adapterType"`
	Network     string  `json:"network"`
	Connected   bool    `json:"connected"`
	MacAddress  string  `json:"macAddress"`
	IPv4Address *string `json:"ipv4Address"`
	IPv6Address *string `json:"ipv6Address"`
}

// vCenterInfo is free — client.Client.ServiceContent.About is populated
// during login itself (govmomi.NewClient), no extra round trip. Backs the
// vLens report's header (see ReportView.swift).
type vCenterInfo struct {
	FullName   string `json:"fullName"`
	Version    string `json:"version"`
	Build      string `json:"build"`
	APIVersion string `json:"apiVersion"`
}

type vmPerformanceInfo struct {
	ID                  string    `json:"id"`
	VMName              string    `json:"vmName"`
	IntervalMinutes     int       `json:"intervalMinutes"`
	CollectedAt         time.Time `json:"collectedAt"`
	AvgCPUUsagePercent  *float64  `json:"avgCpuUsagePercent"`
	MaxCPUUsagePercent  *float64  `json:"maxCpuUsagePercent"`
	AvgRAMUsagePercent  *float64  `json:"avgRamUsagePercent"`
	MaxRAMUsagePercent  *float64  `json:"maxRamUsagePercent"`
	MaxReadIOSizeBytes  *int64    `json:"maxReadIOSizeBytes"`
	MaxWriteIOSizeBytes *int64    `json:"maxWriteIOSizeBytes"`
}

// performanceCoverage tells the caller exactly how much of the requested
// performance collection actually completed — `Complete: true` means every
// powered-on VM was sampled; `false` means a batch failed partway through
// (`CollectedVMCount` says how many VMs got data before that happened, and
// `Error` carries the real reason). Without this, a batch failure and a
// fully successful-but-empty collection were indistinguishable from the
// caller's side — both just returned a plain (possibly empty) list.
type performanceCoverage struct {
	RequestedVMCount int     `json:"requestedVMCount"`
	CollectedVMCount int     `json:"collectedVMCount"`
	Complete         bool    `json:"complete"`
	Error            *string `json:"error,omitempty"`
}

// ---------- main ----------

func main() {
	if err := run(); err != nil {
		msg := err.Error()
		writeResponse(helperResponse{OK: false, Error: &msg})
		os.Exit(1)
	}
}

func run() error {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		return fmt.Errorf("stdin read failed: %w", err)
	}

	var req helperRequest
	if err := json.Unmarshal(input, &req); err != nil {
		return fmt.Errorf("request decode failed: %w", err)
	}

	switch req.Action {
	case "listVMs", "collectAll":
		resp, err := collectAll(req)
		if err != nil {
			return err
		}
		writeResponse(resp)
		return nil
	case "getCertificate":
		cert, err := fetchCertificate(req)
		if err != nil {
			return err
		}
		writeResponse(helperResponse{OK: true, Certificate: cert})
		return nil
	case "collectPerformance":
		resp, err := collectPerformanceAction(req)
		if err != nil {
			return err
		}
		writeResponse(resp)
		return nil
	default:
		return fmt.Errorf("unknown action %q", req.Action)
	}
}

func writeResponse(resp helperResponse) {
	if resp.VMs == nil {
		resp.VMs = []virtualMachineInfo{}
	}
	if resp.CPUs == nil {
		resp.CPUs = []vmCPUInfo{}
	}
	if resp.Memory == nil {
		resp.Memory = []vmMemoryInfo{}
	}
	if resp.Disks == nil {
		resp.Disks = []vmDiskInfo{}
	}
	if resp.Snapshots == nil {
		resp.Snapshots = []vmSnapshotInfo{}
	}
	if resp.Tools == nil {
		resp.Tools = []vmToolsInfo{}
	}
	if resp.Hosts == nil {
		resp.Hosts = []hostInfo{}
	}
	if resp.Datastores == nil {
		resp.Datastores = []datastoreInfo{}
	}
	if resp.Clusters == nil {
		resp.Clusters = []clusterInfo{}
	}
	if resp.Licenses == nil {
		resp.Licenses = []licenseInfo{}
	}
	if resp.VSwitches == nil {
		resp.VSwitches = []vSwitchInfo{}
	}
	if resp.Ports == nil {
		resp.Ports = []vPortInfo{}
	}
	if resp.DVSwitches == nil {
		resp.DVSwitches = []dvSwitchInfo{}
	}
	if resp.DVPorts == nil {
		resp.DVPorts = []dvPortInfo{}
	}
	if resp.ResourcePools == nil {
		resp.ResourcePools = []resourcePoolInfo{}
	}
	if resp.HBAs == nil {
		resp.HBAs = []hbaInfo{}
	}
	if resp.Nics == nil {
		resp.Nics = []nicInfo{}
	}
	if resp.VMKernels == nil {
		resp.VMKernels = []vmkInfo{}
	}
	if resp.Multipaths == nil {
		resp.Multipaths = []multipathInfo{}
	}
	if resp.CDs == nil {
		resp.CDs = []cdInfo{}
	}
	if resp.USBs == nil {
		resp.USBs = []usbInfo{}
	}
	if resp.Partitions == nil {
		resp.Partitions = []partitionInfo{}
	}
	enc := json.NewEncoder(os.Stdout)
	_ = enc.Encode(resp)
}

// ---------- certificate trust ----------

// fetchCertificate does a raw TLS handshake — no vim25/SOAP, no login — so
// the presented certificate can be inspected and a trust decision made
// *before* any credentials are sent. Always skips verification at this
// layer (InsecureSkipVerify) because the whole point is to see whatever
// certificate is actually being presented, self-signed or not; trust is
// then decided explicitly by Sources/vLensCore/CertificateTrust.swift via
// fingerprint pinning, not by the OS/Go's normal CA validation.
func fetchCertificate(req helperRequest) (*certificateInfo, error) {
	u, err := soap.ParseURL(req.URL)
	if err != nil {
		return nil, fmt.Errorf("invalid vCenter URL: %w", err)
	}

	host := u.Host
	if u.Port() == "" {
		host = net.JoinHostPort(u.Hostname(), "443")
	}

	dialer := &net.Dialer{Timeout: 10 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", host, &tls.Config{InsecureSkipVerify: true}) //nolint:gosec // intentional, see doc comment
	if err != nil {
		return nil, fmt.Errorf("TLS handshake to %s failed: %w", host, err)
	}
	defer conn.Close()

	certs := conn.ConnectionState().PeerCertificates
	if len(certs) == 0 {
		return nil, fmt.Errorf("%s presented no certificate", host)
	}

	leaf := certs[0]
	sum := sha256.Sum256(leaf.Raw)
	return &certificateInfo{
		SHA256Fingerprint: hex.EncodeToString(sum[:]),
		Subject:           leaf.Subject.String(),
		Issuer:            leaf.Issuer.String(),
		NotAfter:          leaf.NotAfter.UTC().Format(time.RFC3339),
	}, nil
}

// ---------- collection ----------

// newPinnedClient replaces the old `govmomi.NewClient(ctx, u, insecure)`
// blanket-insecure pattern for every authenticated action. That pattern was
// a real vulnerability: `getCertificate` fingerprints the server on one
// throwaway TLS connection, `ConnectionViewModel` checks that fingerprint
// against the locally pinned trust store, and then — on a completely
// separate connection — the actual login with real credentials happened
// with `InsecureSkipVerify: true` and no cryptographic link back to the
// fingerprint that was just "verified". A MITM only needs to let the first
// probe through untouched and can freely intercept the second.
//
// A first attempt at this fix used govmomi's own `soap.Client.SetThumbprint`
// (the mechanism govc/terraform-provider-vsphere also use). That turned out
// to be insufficient pinning, not a full fix: govmomi's `dialTLSContext`
// only ever consults the pinned thumbprint as a *fallback*, after a normal
// CA-trust `tls.Dial` fails — if the presented certificate happens to
// validate against the OS's own trust store for any reason (a legitimately
// re-issued cert, or a maliciously-issued one from some CA the OS trusts
// for this hostname), the connection succeeds without the thumbprint ever
// being checked at all. That's "CA trust OR pinned thumbprint", not real
// pinning. Confirmed directly: a deliberately wrong pinned fingerprint was
// rejected against an untrusted (self-signed) cert as expected, but
// accepted — HTTP 200, login succeeded — once that same cert was trusted
// via a CA, with the exact same wrong pin still configured.
//
// Fixed by not delegating to govmomi's built-in dial logic at all: the
// transport's `DialTLSContext` is replaced with a dialer that skips Go's
// chain verification entirely (`InsecureSkipVerify: true` — we are doing
// our own, different verification) and unconditionally compares the
// presented leaf certificate's SHA-256 thumbprint (`soap.ThumbprintSHA256`,
// the same format `ExpectedFingerprint` already arrives in) against
// `expectedFingerprint`. The only way to connect is an exact pin match —
// no CA-trust escape hatch, no fallback-only logic.
func newPinnedClient(ctx context.Context, u *url.URL, expectedFingerprint string) (*govmomi.Client, error) {
	if expectedFingerprint == "" {
		return nil, fmt.Errorf("expectedFingerprint is required — refusing to connect without certificate pinning")
	}

	soapClient := soap.NewClient(u, true)
	transport := soapClient.DefaultTransport()
	transport.DialTLSContext = func(dialCtx context.Context, network, addr string) (net.Conn, error) {
		dialer := tls.Dialer{Config: &tls.Config{InsecureSkipVerify: true}} //nolint:gosec // intentional — see doc comment, verification happens below
		conn, err := dialer.DialContext(dialCtx, network, addr)
		if err != nil {
			return nil, err
		}
		tlsConn, ok := conn.(*tls.Conn)
		if !ok {
			_ = conn.Close()
			return nil, fmt.Errorf("unexpected connection type dialing %q", addr)
		}
		certs := tlsConn.ConnectionState().PeerCertificates
		if len(certs) == 0 {
			_ = conn.Close()
			return nil, fmt.Errorf("host %q presented no certificate", addr)
		}
		actual := soap.ThumbprintSHA256(certs[0])
		if !strings.EqualFold(actual, expectedFingerprint) {
			_ = conn.Close()
			return nil, fmt.Errorf("host %q certificate does not match the pinned fingerprint (expected %s, got %s)", addr, expectedFingerprint, actual)
		}
		return conn, nil
	}

	vimClient, err := vim25.NewClient(ctx, soapClient)
	if err != nil {
		return nil, err
	}

	c := &govmomi.Client{
		Client:         vimClient,
		SessionManager: session.NewManager(vimClient),
	}

	if u.User != nil {
		if err := c.Login(ctx, u.User); err != nil {
			return nil, err
		}
	}

	return c, nil
}

func collectAll(req helperRequest) (helperResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	u, err := soap.ParseURL(req.URL)
	if err != nil {
		return helperResponse{}, fmt.Errorf("invalid vCenter URL: %w", err)
	}
	u.User = url.UserPassword(req.Username, req.Password)

	client, err := newPinnedClient(ctx, u, req.ExpectedFingerprint)
	if err != nil {
		return helperResponse{}, fmt.Errorf("login failed: %w", err)
	}
	defer client.Logout(ctx)

	// Cluster-only name map — deliberately NOT the broader "ComputeResource"
	// type (which also matches the invisible per-standalone-host wrapper
	// every HostSystem has). Using it there was a real bug: standalone
	// hosts showed a fake "cluster" name. Real vCenter/RVTools leave the
	// Cluster column blank for standalone hosts.
	clusterNames, err := nameMap(ctx, client, "ClusterComputeResource")
	if err != nil {
		return helperResponse{}, fmt.Errorf("cluster lookup failed: %w", err)
	}
	hostNames, err := nameMap(ctx, client, "HostSystem")
	if err != nil {
		return helperResponse{}, fmt.Errorf("host lookup failed: %w", err)
	}
	poolNames, err := nameMap(ctx, client, "ResourcePool")
	if err != nil {
		return helperResponse{}, fmt.Errorf("resource pool lookup failed: %w", err)
	}
	hostParents, err := parentMap(ctx, client, "HostSystem")
	if err != nil {
		return helperResponse{}, fmt.Errorf("host parent lookup failed: %w", err)
	}

	vms, err := collectVMs(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("VM collection failed: %w", err)
	}

	hosts, err := collectHosts(ctx, client, clusterNames, hostParents)
	if err != nil {
		return helperResponse{}, fmt.Errorf("host collection failed: %w", err)
	}

	datastores, err := collectDatastores(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("datastore collection failed: %w", err)
	}

	clusters, err := collectClusters(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("cluster collection failed: %w", err)
	}

	// License info requires elevated vCenter permissions (read-only accounts
	// can't see it — see rvtools.txt's Permissions chapter, which documents
	// the same restriction for RVTools itself). Missing permissions here
	// shouldn't fail the entire collection, just leave this one tab empty.
	licenses, licenseErr := collectLicenses(ctx, client)
	if licenseErr != nil {
		licenses = nil
	}

	vSwitches, ports, err := collectVSwitchesAndPorts(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("vswitch/port group collection failed: %w", err)
	}
	dvSwitches, err := collectDVSwitches(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("distributed switch collection failed: %w", err)
	}
	dvPorts, err := collectDVPortgroups(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("distributed port group collection failed: %w", err)
	}
	resourcePools, err := collectResourcePools(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("resource pool collection failed: %w", err)
	}
	vApps, err := collectVApps(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("vApp collection failed: %w", err)
	}
	hbas, err := collectHBAs(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("HBA collection failed: %w", err)
	}
	nics, err := collectNics(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("NIC collection failed: %w", err)
	}
	vmKernels, err := collectVMKernelPorts(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("VMkernel port collection failed: %w", err)
	}
	multipaths, err := collectMultipaths(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("multipath collection failed: %w", err)
	}
	dvpgNames, err := dvPortgroupKeyNameMap(ctx, client)
	if err != nil {
		return helperResponse{}, fmt.Errorf("distributed port group name lookup failed: %w", err)
	}

	about := client.Client.ServiceContent.About
	resp := helperResponse{
		OK: true, Hosts: hosts, Datastores: datastores, Clusters: clusters, Licenses: licenses,
		VSwitches: vSwitches, Ports: ports, DVSwitches: dvSwitches, DVPorts: dvPorts,
		ResourcePools: resourcePools, VApps: vApps, HBAs: hbas, Nics: nics, VMKernels: vmKernels, Multipaths: multipaths,
		VCenter: &vCenterInfo{
			FullName: about.FullName, Version: about.Version, Build: about.Build, APIVersion: about.ApiVersion,
		},
	}
	for _, vm := range vms {
		clusterName := clusterNameForHost(vm.Runtime.Host, hostParents, clusterNames)
		hostName := ""
		if vm.Runtime.Host != nil {
			hostName = hostNames[*vm.Runtime.Host]
		}
		var poolName *string
		if vm.ResourcePool != nil {
			if name, ok := poolNames[*vm.ResourcePool]; ok {
				poolName = &name
			}
		}

		resp.VMs = append(resp.VMs, mapVMInfo(vm, hostName, clusterName, poolName))
		resp.CPUs = append(resp.CPUs, mapVMCPU(vm, hostName, clusterName))
		resp.Memory = append(resp.Memory, mapVMMemory(vm, hostName, clusterName))
		resp.Disks = append(resp.Disks, mapVMDisks(vm, hostName)...)
		resp.Snapshots = append(resp.Snapshots, mapVMSnapshots(vm, hostName, clusterName)...)
		resp.Tools = append(resp.Tools, mapVMTools(vm, hostName, clusterName))
		resp.CDs = append(resp.CDs, mapVMCDs(vm)...)
		resp.USBs = append(resp.USBs, mapVMUSBs(vm)...)
		resp.Partitions = append(resp.Partitions, mapVMPartitions(vm)...)
		resp.Networks = append(resp.Networks, mapVMNetworks(vm, dvpgNames)...)
	}

	return resp, nil
}

// collectPerformanceAction handles the standalone "collectPerformance" action
// — its own login/logout, deliberately not part of collectAll. QueryPerf is a
// per-entity call (batched here, but still N calls where collectAll's other
// collectors are one PropertyCollector pass) and would otherwise break
// collectAll's "one login, one batch" performance guarantee (see the vcsim
// benchmark note in docs/vLens-Reference.md §3).
func collectPerformanceAction(req helperRequest) (helperResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	u, err := soap.ParseURL(req.URL)
	if err != nil {
		return helperResponse{}, fmt.Errorf("invalid vCenter URL: %w", err)
	}
	u.User = url.UserPassword(req.Username, req.Password)

	client, err := newPinnedClient(ctx, u, req.ExpectedFingerprint)
	if err != nil {
		return helperResponse{}, fmt.Errorf("login failed: %w", err)
	}
	defer client.Logout(ctx)

	perf, coverage, err := collectPerformance(ctx, client, req.PerfIntervalMinutes)
	if err != nil {
		return helperResponse{}, fmt.Errorf("performance collection failed: %w", err)
	}

	return helperResponse{OK: true, Performance: perf, PerformanceCoverage: &coverage}, nil
}

// perfSamplingParameters mirrors AWS's export-for-vcenter tool's own
// interval-selection table (same vCenter historical-interval documentation,
// see docs/vLens-Reference.md's vPerformance section) — picks the coarsest
// interval that still covers the requested window without exceeding
// vCenter's retention for that interval.
func perfSamplingParameters(intervalMins int) (samples int, intervalID int32) {
	switch {
	case intervalMins <= 60:
		return (intervalMins * 60) / 20, 20
	case intervalMins <= 1440:
		return intervalMins / 5, 300
	case intervalMins <= 10080:
		return intervalMins / 30, 1800
	case intervalMins <= 43200:
		return intervalMins / 120, 7200
	default:
		return intervalMins / 1440, 86400
	}
}

// perfSampler abstracts one batched QueryPerf round-trip (SampleByName +
// ToMetricSeries) so tests can inject a failure on a specific batch — the
// first, a later one, or none — without a live vCenter/vcsim connection.
type perfSampler interface {
	sampleBatch(ctx context.Context, spec types.PerfQuerySpec, metricNames []string, batch []types.ManagedObjectReference) ([]performance.EntityMetric, error)
}

type govmomiPerfSampler struct {
	manager *performance.Manager
}

func (s *govmomiPerfSampler) sampleBatch(ctx context.Context, spec types.PerfQuerySpec, metricNames []string, batch []types.ManagedObjectReference) ([]performance.EntityMetric, error) {
	series, err := s.manager.SampleByName(ctx, spec, metricNames, batch)
	if err != nil {
		return nil, err
	}
	return s.manager.ToMetricSeries(ctx, series)
}

// collectPerformance samples CPU/RAM usage and disk IOPS size for every
// powered-on VM over the requested time window. Only powered-on VMs are
// queried — powered-off VMs have no live performance samples. Chunked into
// batches (not one call per VM, not all VMs in a single call) to keep each
// QueryPerf request bounded in very large environments.
func collectPerformance(ctx context.Context, client *govmomi.Client, intervalMins int) ([]vmPerformanceInfo, performanceCoverage, error) {
	if intervalMins <= 0 {
		intervalMins = 60
	}
	samples, intervalID := perfSamplingParameters(intervalMins)

	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"VirtualMachine"}, true)
	if err != nil {
		return nil, performanceCoverage{}, err
	}
	defer cv.Destroy(ctx)

	var vms []mo.VirtualMachine
	if err := cv.Retrieve(ctx, []string{"VirtualMachine"}, []string{"name", "runtime.powerState", "config.uuid"}, &vms); err != nil {
		return nil, performanceCoverage{}, err
	}

	var refs []types.ManagedObjectReference
	nameByRef := map[types.ManagedObjectReference]string{}
	idByRef := map[types.ManagedObjectReference]string{}
	for _, vm := range vms {
		if vm.Runtime.PowerState != types.VirtualMachinePowerStatePoweredOn {
			continue
		}
		ref := vm.Reference()
		refs = append(refs, ref)
		nameByRef[ref] = vm.Name
		idByRef[ref] = vmID(vm)
	}
	if len(refs) == 0 {
		return nil, performanceCoverage{Complete: true}, nil
	}

	spec := types.PerfQuerySpec{MaxSample: int32(samples), IntervalId: intervalID}
	sampler := &govmomiPerfSampler{manager: performance.NewManager(client.Client)}
	result, coverage := samplePerformanceBatches(ctx, sampler, refs, nameByRef, idByRef, spec, intervalMins)
	return result, coverage, nil
}

// samplePerformanceBatches drives the batched QueryPerf loop against
// `sampler` — factored out of collectPerformance purely so a fake sampler
// can exercise "the first batch fails" separately from "a later batch fails
// after earlier ones already succeeded" (see main_test.go). A batch failure
// stops the loop (some environments, and vcsim, don't support QueryPerf for
// every counter) but — unlike before — is no longer silent: `Complete` is
// false and `Error` carries the real reason, so "0 of 400 VMs, first batch
// failed" and "250 of 400, a later batch failed" are each visible as
// incomplete instead of looking like a clean result.
func samplePerformanceBatches(
	ctx context.Context, sampler perfSampler, refs []types.ManagedObjectReference,
	nameByRef, idByRef map[types.ManagedObjectReference]string, spec types.PerfQuerySpec, intervalMins int,
) ([]vmPerformanceInfo, performanceCoverage) {
	metricNames := []string{
		"cpu.usage.average", "mem.usage.average",
		"virtualDisk.readIOSize.latest", "virtualDisk.writeIOSize.latest",
	}
	now := time.Now().UTC()
	coverage := performanceCoverage{RequestedVMCount: len(refs)}

	const batchSize = 50
	var result []vmPerformanceInfo
	for i := 0; i < len(refs); i += batchSize {
		end := i + batchSize
		if end > len(refs) {
			end = len(refs)
		}
		batch := refs[i:end]

		entityMetrics, err := sampler.sampleBatch(ctx, spec, metricNames, batch)
		if err != nil {
			msg := err.Error()
			coverage.Error = &msg
			coverage.CollectedVMCount = len(result)
			return result, coverage
		}
		for _, em := range entityMetrics {
			result = append(result, buildPerformanceInfo(em, nameByRef, idByRef, intervalMins, now))
		}
	}

	coverage.Complete = true
	coverage.CollectedVMCount = len(result)
	return result, coverage
}

// buildPerformanceInfo maps one entity's sampled counters to a single
// vmPerformanceInfo. A VM with multiple disks gets one PerfMetricSeries per
// disk instance (e.g. "scsi0:0", "scsi0:1") for both
// virtualDisk.readIOSize.latest and .writeIOSize.latest — merged here by
// taking the largest single-disk peak, rather than the previous behavior of
// letting whichever disk's series was processed last silently overwrite the
// others.
func buildPerformanceInfo(em performance.EntityMetric, nameByRef, idByRef map[types.ManagedObjectReference]string, intervalMins int, now time.Time) vmPerformanceInfo {
	info := vmPerformanceInfo{
		ID:              idByRef[em.Entity],
		VMName:          nameByRef[em.Entity],
		IntervalMinutes: intervalMins,
		CollectedAt:     now,
	}
	var maxRead, maxWrite *int64
	for _, ms := range em.Value {
		avg, max, ok := averageMax(ms.Value)
		if !ok {
			continue
		}
		switch ms.Name {
		case "cpu.usage.average":
			a, mx := avg/100.0, max/100.0
			info.AvgCPUUsagePercent, info.MaxCPUUsagePercent = &a, &mx
		case "mem.usage.average":
			a, mx := avg/100.0, max/100.0
			info.AvgRAMUsagePercent, info.MaxRAMUsagePercent = &a, &mx
		case "virtualDisk.readIOSize.latest":
			mx := int64(max)
			if maxRead == nil || mx > *maxRead {
				maxRead = &mx
			}
		case "virtualDisk.writeIOSize.latest":
			mx := int64(max)
			if maxWrite == nil || mx > *maxWrite {
				maxWrite = &mx
			}
		}
	}
	info.MaxReadIOSizeBytes = maxRead
	info.MaxWriteIOSizeBytes = maxWrite
	return info
}

// averageMax ignores negative values — vCenter uses -1 to mean "no data for
// this sample," not a real reading. Returns ok=false when every sample in
// the series was -1 (counter defined but nothing was actually collected).
func averageMax(values []int64) (avg, max float64, ok bool) {
	var sum int64
	count := 0
	max = -math.MaxFloat64
	for _, v := range values {
		if v < 0 {
			continue
		}
		sum += v
		count++
		if float64(v) > max {
			max = float64(v)
		}
	}
	if count == 0 {
		return 0, 0, false
	}
	return float64(sum) / float64(count), max, true
}

func collectVMs(ctx context.Context, client *govmomi.Client) ([]mo.VirtualMachine, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"VirtualMachine"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	props := []string{
		"name",
		"runtime.powerState",
		"runtime.consolidationNeeded",
		"config.template",
		"config.guestFullName",
		"config.hardware.numCPU",
		"config.hardware.numCoresPerSocket",
		"config.hardware.memoryMB",
		"config.hardware.device",
		"config.cpuAllocation",
		"config.memoryAllocation",
		"config.cpuHotAddEnabled",
		"config.cpuHotRemoveEnabled",
		"config.memoryHotAddEnabled",
		"config.version",
		"config.uuid",
		"runtime.host",
		"resourcePool",
		"guest.ipAddress",
		"guest.toolsStatus",
		"guest.toolsVersion",
		"guest.disk",
		"guest.net",
		"snapshot",
		"summary.quickStats",
		"layoutEx.file",
		"layoutEx.snapshot",
	}

	var raw []mo.VirtualMachine
	if err := cv.Retrieve(ctx, []string{"VirtualMachine"}, props, &raw); err != nil {
		return nil, err
	}
	return raw, nil
}

func collectHosts(ctx context.Context, client *govmomi.Client, clusterNames map[types.ManagedObjectReference]string, hostParents map[types.ManagedObjectReference]types.ManagedObjectReference) ([]hostInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"HostSystem"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	props := []string{
		"name",
		"configStatus",
		"summary.hardware",
		"summary.quickStats",
		"summary.config.product",
		"runtime.inMaintenanceMode",
		"vm",
	}

	var raw []mo.HostSystem
	if err := cv.Retrieve(ctx, []string{"HostSystem"}, props, &raw); err != nil {
		return nil, err
	}

	datacenterNames, err := nameMap(ctx, client, "Datacenter")
	if err != nil {
		return nil, fmt.Errorf("datacenter lookup failed: %w", err)
	}
	// The chain from a host up to its Datacenter is HostSystem ->
	// ComputeResource (or ClusterComputeResource) -> one or more nested
	// Folders -> Datacenter. Building one combined parent map over both
	// types lets resolveDatacenterName walk it generically without caring
	// how many folder levels an environment happens to have.
	computeResourceParents, err := parentMap(ctx, client, "ComputeResource")
	if err != nil {
		return nil, fmt.Errorf("compute resource parent lookup failed: %w", err)
	}
	folderParents, err := parentMap(ctx, client, "Folder")
	if err != nil {
		return nil, fmt.Errorf("folder parent lookup failed: %w", err)
	}
	ancestry := make(map[types.ManagedObjectReference]types.ManagedObjectReference, len(computeResourceParents)+len(folderParents))
	for ref, parent := range computeResourceParents {
		ancestry[ref] = parent
	}
	for ref, parent := range folderParents {
		ancestry[ref] = parent
	}

	result := make([]hostInfo, 0, len(raw))
	for _, h := range raw {
		info := hostInfo{
			ID:              h.Reference().Value,
			Name:            h.Name,
			ConfigStatus:    string(h.ConfigStatus),
			MaintenanceMode: h.Runtime.InMaintenanceMode,
			NumVMsTotal:     len(h.Vm),
		}

		if cname, ok := clusterNames[hostParents[h.Reference()]]; ok {
			info.ClusterName = &cname
		}
		if dcName, ok := resolveDatacenterName(hostParents[h.Reference()], ancestry, datacenterNames); ok {
			info.DatacenterName = &dcName
		}

		if hw := h.Summary.Hardware; hw != nil {
			info.CPUModel = hw.CpuModel
			info.CPUMhz = int(hw.CpuMhz)
			info.NumCPUCores = int(hw.NumCpuCores)
			info.NumCPUThreads = int(hw.NumCpuThreads)
			info.MemoryTotalMiB = int(hw.MemorySize / (1024 * 1024))
			info.NumNics = int(hw.NumNics)
			info.NumHbas = int(hw.NumHBAs)
			if hw.Vendor != "" {
				v := hw.Vendor
				info.Vendor = &v
			}
			if hw.Model != "" {
				mdl := hw.Model
				info.Model = &mdl
			}
		}

		qs := h.Summary.QuickStats
		if info.NumCPUCores > 0 {
			pct := float64(qs.OverallCpuUsage) / (float64(info.NumCPUCores) * float64(info.CPUMhz)) * 100
			info.CPUUsagePercent = &pct
		}
		if info.MemoryTotalMiB > 0 {
			pct := float64(qs.OverallMemoryUsage) / float64(info.MemoryTotalMiB) * 100
			info.MemoryUsagePercent = &pct
		}

		if p := h.Summary.Config.Product; p != nil {
			info.EsxVersion = p.Version
			info.EsxBuild = p.Build
		}

		result = append(result, info)
	}

	// Second pass: count only running VMs per host.
	hostVMPowerState, err := runningVMCountsByHost(ctx, client)
	if err == nil {
		for i := range result {
			result[i].NumVMsRunning = hostVMPowerState[result[i].ID]
		}
	}

	return result, nil
}

func runningVMCountsByHost(ctx context.Context, client *govmomi.Client) (map[string]int, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"VirtualMachine"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.VirtualMachine
	if err := cv.Retrieve(ctx, []string{"VirtualMachine"}, []string{"runtime.host", "runtime.powerState"}, &raw); err != nil {
		return nil, err
	}

	counts := make(map[string]int)
	for _, vm := range raw {
		if vm.Runtime.PowerState == types.VirtualMachinePowerStatePoweredOn && vm.Runtime.Host != nil {
			counts[vm.Runtime.Host.Value]++
		}
	}
	return counts, nil
}

func collectDatastores(ctx context.Context, client *govmomi.Client) ([]datastoreInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"Datastore"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.Datastore
	if err := cv.Retrieve(ctx, []string{"Datastore"}, []string{"summary", "vm", "host"}, &raw); err != nil {
		return nil, err
	}

	result := make([]datastoreInfo, 0, len(raw))
	for _, ds := range raw {
		info := datastoreInfo{
			ID:                ds.Reference().Value,
			Name:              ds.Summary.Name,
			Type:              ds.Summary.Type,
			CapacityMiB:       int(ds.Summary.Capacity / (1024 * 1024)),
			FreeMiB:           int(ds.Summary.FreeSpace / (1024 * 1024)),
			NumVMsTotal:       len(ds.Vm),
			NumHostsConnected: len(ds.Host),
		}
		if ds.Summary.Url != "" {
			u := ds.Summary.Url
			info.URL = &u
		}
		result = append(result, info)
	}
	return result, nil
}

func collectClusters(ctx context.Context, client *govmomi.Client) ([]clusterInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"ClusterComputeResource"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.ClusterComputeResource
	if err := cv.Retrieve(ctx, []string{"ClusterComputeResource"}, []string{"name", "configStatus", "summary", "configuration", "host"}, &raw); err != nil {
		return nil, err
	}

	result := make([]clusterInfo, 0, len(raw))
	for _, c := range raw {
		info := clusterInfo{
			ID:           c.Reference().Value,
			Name:         c.Name,
			ConfigStatus: string(c.ConfigStatus),
			NumHosts:     len(c.Host),
		}

		if summary := c.Summary.GetComputeResourceSummary(); summary != nil {
			info.NumEffectiveHosts = int(summary.NumEffectiveHosts)
			info.TotalCPUMHz = int(summary.TotalCpu)
			info.TotalMemoryMiB = int(summary.TotalMemory / (1024 * 1024))
		}

		if das := c.Configuration.DasConfig; das.Enabled != nil {
			info.HAEnabled = *das.Enabled
		}
		if das := c.Configuration.DasConfig; das.AdmissionControlEnabled != nil {
			info.AdmissionControlEnabled = *das.AdmissionControlEnabled
		}
		if drs := c.Configuration.DrsConfig; drs.Enabled != nil {
			info.DRSEnabled = *drs.Enabled
		}
		if behavior := string(c.Configuration.DrsConfig.DefaultVmBehavior); behavior != "" {
			info.DRSDefaultVMBehavior = &behavior
		}

		result = append(result, info)
	}
	return result, nil
}

func collectLicenses(ctx context.Context, client *govmomi.Client) ([]licenseInfo, error) {
	mgr := license.NewManager(client.Client)
	raw, err := mgr.List(ctx)
	if err != nil {
		return nil, err
	}

	result := make([]licenseInfo, 0, len(raw))
	for _, l := range raw {
		info := licenseInfo{
			Name:     l.Name,
			Key:      l.LicenseKey,
			Labels:   []string{},
			CostUnit: l.CostUnit,
			Total:    int(l.Total),
			Used:     int(l.Used),
			Features: []string{},
		}

		for _, label := range l.Labels {
			info.Labels = append(info.Labels, fmt.Sprintf("%s: %s", label.Key, label.Value))
		}

		for _, prop := range l.Properties {
			switch {
			case prop.Key == "feature":
				if kv, ok := prop.Value.(types.KeyValue); ok {
					if kv.Value != "" {
						info.Features = append(info.Features, kv.Value)
					} else {
						info.Features = append(info.Features, kv.Key)
					}
				}
			case strings.EqualFold(prop.Key, "expirationDate"):
				// VMware's documented convention for this property is an
				// int64 (epoch seconds); handle both that and a plain
				// string defensively since it's not part of the typed
				// vim25 schema — permanent licenses simply omit it.
				switch v := prop.Value.(type) {
				case int64:
					s := time.Unix(v, 0).UTC().Format(time.RFC3339)
					info.ExpirationDate = &s
				case int:
					s := time.Unix(int64(v), 0).UTC().Format(time.RFC3339)
					info.ExpirationDate = &s
				case string:
					if v != "" {
						info.ExpirationDate = &v
					}
				}
			}
		}

		result = append(result, info)
	}
	return result, nil
}

// collectVSwitchesAndPorts does one host retrieval pass for both standard
// vSwitches and their port groups. Combined deliberately: a port group's
// `Vswitch` field is the *key* of its switch (e.g.
// "key-vim.host.VirtualSwitch-vSwitch0"), not a name, and that key is only
// unique per-host — resolving it to a friendly switch name means building
// a key->name map scoped to the same host's vSwitch list, which is easiest
// to get right in one pass over the same host record rather than two
// separate collectors trying to stay in sync.
func collectVSwitchesAndPorts(ctx context.Context, client *govmomi.Client) ([]vSwitchInfo, []vPortInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"HostSystem"}, true)
	if err != nil {
		return nil, nil, err
	}
	defer cv.Destroy(ctx)

	var hosts []mo.HostSystem
	props := []string{"name", "config.network.vswitch", "config.network.portgroup"}
	if err := cv.Retrieve(ctx, []string{"HostSystem"}, props, &hosts); err != nil {
		return nil, nil, err
	}

	switches := []vSwitchInfo{}
	ports := []vPortInfo{}
	for _, h := range hosts {
		if h.Config == nil {
			continue
		}

		switchNameByKey := make(map[string]string, len(h.Config.Network.Vswitch))
		for _, sw := range h.Config.Network.Vswitch {
			switchNameByKey[sw.Key] = sw.Name
			switches = append(switches, vSwitchInfo{
				ID:                fmt.Sprintf("%s-%s", h.Reference().Value, sw.Key),
				HostName:          h.Name,
				Name:              sw.Name,
				NumPorts:          int(sw.NumPorts),
				NumPortsAvailable: int(sw.NumPortsAvailable),
				MTU:               int(sw.Mtu),
				NumUplinks:        len(sw.Pnic),
				NumPortGroups:     len(sw.Portgroup),
			})
		}

		for _, pg := range h.Config.Network.Portgroup {
			switchName := pg.Vswitch
			if name, ok := switchNameByKey[pg.Vswitch]; ok {
				switchName = name
			}
			ports = append(ports, vPortInfo{
				ID:         fmt.Sprintf("%s-%s", h.Reference().Value, pg.Key),
				HostName:   h.Name,
				SwitchName: switchName,
				Name:       pg.Spec.Name,
				VLANID:     int(pg.Spec.VlanId),
			})
		}
	}
	return switches, ports, nil
}

func collectDVSwitches(ctx context.Context, client *govmomi.Client) ([]dvSwitchInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"DistributedVirtualSwitch"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.DistributedVirtualSwitch
	if err := cv.Retrieve(ctx, []string{"DistributedVirtualSwitch"}, []string{"name", "uuid", "summary", "portgroup"}, &raw); err != nil {
		return nil, err
	}

	result := make([]dvSwitchInfo, 0, len(raw))
	for _, dvs := range raw {
		result = append(result, dvSwitchInfo{
			ID:            dvs.Reference().Value,
			Name:          dvs.Name,
			UUID:          dvs.Uuid,
			NumPorts:      int(dvs.Summary.NumPorts),
			NumHosts:      len(dvs.Summary.HostMember),
			NumPortGroups: len(dvs.Portgroup),
		})
	}
	return result, nil
}

func collectDVPortgroups(ctx context.Context, client *govmomi.Client) ([]dvPortInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"DistributedVirtualPortgroup"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.DistributedVirtualPortgroup
	if err := cv.Retrieve(ctx, []string{"DistributedVirtualPortgroup"}, []string{"name", "config"}, &raw); err != nil {
		return nil, err
	}

	dvsNames, err := nameMap(ctx, client, "DistributedVirtualSwitch")
	if err != nil {
		return nil, err
	}

	result := make([]dvPortInfo, 0, len(raw))
	for _, pg := range raw {
		info := dvPortInfo{
			ID:       pg.Reference().Value,
			Name:     pg.Config.Name,
			NumPorts: int(pg.Config.NumPorts),
		}
		if pg.Config.DistributedVirtualSwitch != nil {
			if name, ok := dvsNames[*pg.Config.DistributedVirtualSwitch]; ok {
				info.SwitchName = name
			}
		}
		// Only handles the common single-VLAN-ID case. Trunk/PVLAN
		// configs (different concrete Vlan types) are left nil rather
		// than guessed at.
		if setting, ok := pg.Config.DefaultPortConfig.(*types.VMwareDVSPortSetting); ok {
			if vlanSpec, ok := setting.Vlan.(*types.VmwareDistributedVirtualSwitchVlanIdSpec); ok {
				v := int(vlanSpec.VlanId)
				info.VLANID = &v
			}
		}
		result = append(result, info)
	}
	return result, nil
}

func collectResourcePools(ctx context.Context, client *govmomi.Client) ([]resourcePoolInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"ResourcePool"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.ResourcePool
	if err := cv.Retrieve(ctx, []string{"ResourcePool"}, []string{"name", "owner", "config", "vm"}, &raw); err != nil {
		return nil, err
	}

	// Any ComputeResource (cluster or standalone host wrapper) can own a
	// resource pool — unlike the VM/host cluster-name resolution
	// elsewhere, we don't need to distinguish the two here, just show
	// *something* recognizable as the owner.
	ownerNames, err := nameMap(ctx, client, "ComputeResource")
	if err != nil {
		return nil, err
	}

	result := make([]resourcePoolInfo, 0, len(raw))
	for _, rp := range raw {
		info := resourcePoolInfo{
			ID:     rp.Reference().Value,
			Name:   rp.Name,
			NumVMs: len(rp.Vm),
		}
		if name, ok := ownerNames[rp.Owner]; ok {
			info.OwnerName = &name
		}
		if alloc := rp.Config.CpuAllocation; alloc.Reservation != nil {
			info.CPUReservationMHz = int(*alloc.Reservation)
		}
		if alloc := rp.Config.CpuAllocation; alloc.Limit != nil {
			info.CPULimitMHz = int(*alloc.Limit)
		} else {
			info.CPULimitMHz = -1
		}
		if alloc := rp.Config.MemoryAllocation; alloc.Reservation != nil {
			info.MemoryReservationMiB = int(*alloc.Reservation)
		}
		if alloc := rp.Config.MemoryAllocation; alloc.Limit != nil {
			info.MemoryLimitMiB = int(*alloc.Limit)
		} else {
			info.MemoryLimitMiB = -1
		}
		result = append(result, info)
	}
	return result, nil
}

// collectVApps mirrors collectResourcePools almost exactly — VirtualApp
// (vim25/mo) embeds ResourcePool, so it's the same container-view-plus-owner-
// name-map pattern, just over a different vim25 type and with product
// metadata (VAppConfig.Product) added on top.
func collectVApps(ctx context.Context, client *govmomi.Client) ([]vAppInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"VirtualApp"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var raw []mo.VirtualApp
	if err := cv.Retrieve(ctx, []string{"VirtualApp"}, []string{"name", "owner", "vm", "vAppConfig"}, &raw); err != nil {
		return nil, err
	}

	ownerNames, err := nameMap(ctx, client, "ComputeResource")
	if err != nil {
		return nil, err
	}

	result := []vAppInfo{}
	for _, va := range raw {
		info := vAppInfo{
			ID:     va.Reference().Value,
			Name:   va.Name,
			NumVMs: len(va.Vm),
		}
		if name, ok := ownerNames[va.Owner]; ok {
			info.OwnerName = &name
		}
		if va.VAppConfig != nil && len(va.VAppConfig.Product) > 0 {
			product := va.VAppConfig.Product[0]
			if product.Name != "" {
				name := product.Name
				info.ProductName = &name
			}
			if product.Version != "" {
				version := product.Version
				info.ProductVersion = &version
			}
		}
		result = append(result, info)
	}
	return result, nil
}

func collectHBAs(ctx context.Context, client *govmomi.Client) ([]hbaInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"HostSystem"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var hosts []mo.HostSystem
	if err := cv.Retrieve(ctx, []string{"HostSystem"}, []string{"name", "config.storageDevice.hostBusAdapter"}, &hosts); err != nil {
		return nil, err
	}

	result := []hbaInfo{}
	for _, h := range hosts {
		if h.Config == nil || h.Config.StorageDevice == nil {
			continue
		}
		for _, base := range h.Config.StorageDevice.HostBusAdapter {
			hba := base.GetHostHostBusAdapter()
			result = append(result, hbaInfo{
				ID:       fmt.Sprintf("%s-%s", h.Reference().Value, hba.Key),
				HostName: h.Name,
				Device:   hba.Device,
				Model:    hba.Model,
				Driver:   hba.Driver,
				Status:   hba.Status,
			})
		}
	}
	return result, nil
}

func collectNics(ctx context.Context, client *govmomi.Client) ([]nicInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"HostSystem"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var hosts []mo.HostSystem
	if err := cv.Retrieve(ctx, []string{"HostSystem"}, []string{"name", "config.network.pnic"}, &hosts); err != nil {
		return nil, err
	}

	result := []nicInfo{}
	for _, h := range hosts {
		if h.Config == nil {
			continue
		}
		for _, pnic := range h.Config.Network.Pnic {
			info := nicInfo{
				ID:       fmt.Sprintf("%s-%s", h.Reference().Value, pnic.Key),
				HostName: h.Name,
				Device:   pnic.Device,
				MAC:      pnic.Mac,
			}
			if pnic.LinkSpeed != nil {
				v := int(pnic.LinkSpeed.SpeedMb)
				info.LinkSpeedMb = &v
			}
			if pnic.Driver != "" {
				d := pnic.Driver
				info.Driver = &d
			}
			result = append(result, info)
		}
	}
	return result, nil
}

func collectVMKernelPorts(ctx context.Context, client *govmomi.Client) ([]vmkInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"HostSystem"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var hosts []mo.HostSystem
	if err := cv.Retrieve(ctx, []string{"HostSystem"}, []string{"name", "config.network.vnic"}, &hosts); err != nil {
		return nil, err
	}

	result := []vmkInfo{}
	for _, h := range hosts {
		if h.Config == nil {
			continue
		}
		for _, vnic := range h.Config.Network.Vnic {
			info := vmkInfo{
				ID:        fmt.Sprintf("%s-%s", h.Reference().Value, vnic.Key),
				HostName:  h.Name,
				Device:    vnic.Device,
				PortGroup: vnic.Portgroup,
				MAC:       vnic.Spec.Mac,
			}
			if vnic.Spec.Ip != nil && vnic.Spec.Ip.IpAddress != "" {
				ip := vnic.Spec.Ip.IpAddress
				info.IPAddress = &ip
			}
			result = append(result, info)
		}
	}
	return result, nil
}

func collectMultipaths(ctx context.Context, client *govmomi.Client) ([]multipathInfo, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"HostSystem"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var hosts []mo.HostSystem
	props := []string{"name", "config.storageDevice.multipathInfo", "config.storageDevice.scsiLun"}
	if err := cv.Retrieve(ctx, []string{"HostSystem"}, props, &hosts); err != nil {
		return nil, err
	}

	result := []multipathInfo{}
	for _, h := range hosts {
		if h.Config == nil || h.Config.StorageDevice == nil || h.Config.StorageDevice.MultipathInfo == nil {
			continue
		}

		// Vendor/model live on the ScsiLun record, keyed the same way as
		// the LogicalUnit's `lun` field — a separate list on the same
		// HostConfigInfo, joined here by key.
		lunDetails := make(map[string]*types.ScsiLun, len(h.Config.StorageDevice.ScsiLun))
		for _, base := range h.Config.StorageDevice.ScsiLun {
			lun := base.GetScsiLun()
			lunDetails[lun.Key] = lun
		}

		for _, lu := range h.Config.StorageDevice.MultipathInfo.Lun {
			info := multipathInfo{
				ID:       fmt.Sprintf("%s-%s", h.Reference().Value, lu.Key),
				HostName: h.Name,
				Disk:     lu.Lun,
				NumPaths: len(lu.Path),
			}
			if details, ok := lunDetails[lu.Lun]; ok {
				info.DisplayName = details.DisplayName
				info.Vendor = details.Vendor
				info.Model = details.Model
				info.OperationalState = details.OperationalState
			}
			if info.OperationalState == nil {
				info.OperationalState = []string{}
			}
			result = append(result, info)
		}
	}
	return result, nil
}

// ---------- per-VM mapping ----------

func mapVMInfo(vm mo.VirtualMachine, hostName string, clusterName *string, poolName *string) virtualMachineInfo {
	info := virtualMachineInfo{
		Name:                vm.Name,
		PowerState:          string(vm.Runtime.PowerState),
		HostName:            hostName,
		ClusterName:         clusterName,
		ConsolidationNeeded: vm.Runtime.ConsolidationNeeded,
		// vmID falls back to the VM's moref when Config is nil or Config.Uuid
		// is empty — matching every other per-VM mapper (mapVMCPU, etc.).
		// Using vm.Config.Uuid directly here left every such VM with an
		// identical empty VMUUID, colliding in the GUI/exports.
		VMUUID: vmID(vm),
	}
	if vm.Config != nil {
		info.Template = vm.Config.Template
		if vm.Config.GuestFullName != "" {
			v := vm.Config.GuestFullName
			info.GuestOSFullName = &v
		}
		info.CPUCount = int(vm.Config.Hardware.NumCPU)
		info.MemoryMiB = int(vm.Config.Hardware.MemoryMB)
	}
	info.ResourcePoolName = poolName
	if vm.Guest != nil {
		if vm.Guest.IpAddress != "" {
			ip := vm.Guest.IpAddress
			info.PrimaryIPAddress = &ip
		}
		if s := string(vm.Guest.ToolsStatus); s != "" {
			info.VMwareToolsStatus = &s
		}
	}
	return info
}

func mapVMCPU(vm mo.VirtualMachine, hostName string, clusterName *string) vmCPUInfo {
	info := vmCPUInfo{
		ID:          vmID(vm),
		VMName:      vm.Name,
		PowerState:  string(vm.Runtime.PowerState),
		HostName:    hostName,
		ClusterName: clusterName,
		LimitMHz:    -1,
	}
	if vm.Config == nil {
		return info
	}
	info.CPUCount = int(vm.Config.Hardware.NumCPU)
	coresPerSocket := 1
	if vm.Config.Hardware.NumCoresPerSocket != nil && *vm.Config.Hardware.NumCoresPerSocket > 0 {
		coresPerSocket = int(*vm.Config.Hardware.NumCoresPerSocket)
	}
	info.CoresPerSocket = coresPerSocket
	if coresPerSocket > 0 {
		info.Sockets = info.CPUCount / coresPerSocket
		if info.Sockets == 0 {
			info.Sockets = 1
		}
	}
	if alloc := vm.Config.CpuAllocation; alloc != nil {
		if alloc.Reservation != nil {
			info.ReservationMHz = int(*alloc.Reservation)
		}
		if alloc.Limit != nil {
			info.LimitMHz = int(*alloc.Limit)
		}
	}
	if vm.Config.CpuHotAddEnabled != nil {
		info.HotAddEnabled = *vm.Config.CpuHotAddEnabled
	}
	if vm.Config.CpuHotRemoveEnabled != nil {
		info.HotRemoveEnabled = *vm.Config.CpuHotRemoveEnabled
	}
	if vm.Runtime.PowerState == types.VirtualMachinePowerStatePoweredOn {
		usage := int(vm.Summary.QuickStats.OverallCpuUsage)
		info.OverallUsageMHz = &usage
	}
	return info
}

func mapVMMemory(vm mo.VirtualMachine, hostName string, clusterName *string) vmMemoryInfo {
	info := vmMemoryInfo{
		ID:          vmID(vm),
		VMName:      vm.Name,
		PowerState:  string(vm.Runtime.PowerState),
		HostName:    hostName,
		ClusterName: clusterName,
		LimitMiB:    -1,
	}
	if vm.Config == nil {
		return info
	}
	info.SizeMiB = int(vm.Config.Hardware.MemoryMB)
	if alloc := vm.Config.MemoryAllocation; alloc != nil {
		if alloc.Reservation != nil {
			info.ReservationMiB = int(*alloc.Reservation)
		}
		if alloc.Limit != nil {
			info.LimitMiB = int(*alloc.Limit)
		}
	}
	if vm.Config.MemoryHotAddEnabled != nil {
		info.HotAddEnabled = *vm.Config.MemoryHotAddEnabled
	}
	if vm.Runtime.PowerState == types.VirtualMachinePowerStatePoweredOn {
		qs := vm.Summary.QuickStats
		consumed := int(qs.HostMemoryUsage)
		active := int(qs.ActiveMemory)
		shared := int(qs.SharedMemory)
		swapped := int(qs.SwappedMemory)
		ballooned := int(qs.BalloonedMemory)
		overhead := int(qs.ConsumedOverheadMemory)
		info.ConsumedMiB = &consumed
		info.ActiveMiB = &active
		info.SharedMiB = &shared
		info.SwappedMiB = &swapped
		info.BalloonedMiB = &ballooned
		info.OverheadMiB = &overhead
	}
	return info
}

func mapVMDisks(vm mo.VirtualMachine, hostName string) []vmDiskInfo {
	if vm.Config == nil {
		return nil
	}
	devices := vm.Config.Hardware.Device
	var disks []vmDiskInfo
	for _, d := range devices {
		disk, ok := d.(*types.VirtualDisk)
		if !ok {
			continue
		}
		base := disk.GetVirtualDevice()
		info := vmDiskInfo{
			ID:          fmt.Sprintf("%s-disk%d", vmID(vm), base.Key),
			VMName:      vm.Name,
			PowerState:  string(vm.Runtime.PowerState),
			DiskLabel:   deviceLabel(base),
			CapacityMiB: int(disk.CapacityInKB / 1024),
			Controller:  controllerLabel(devices, base.ControllerKey),
			HostName:    hostName,
		}
		if base.UnitNumber != nil {
			info.UnitNumber = int(*base.UnitNumber)
		}
		if backing, ok := disk.Backing.(*types.VirtualDiskFlatVer2BackingInfo); ok {
			info.DiskMode = backing.DiskMode
			if backing.ThinProvisioned != nil {
				info.ThinProvisioned = *backing.ThinProvisioned
			}
			info.DatastorePath = backing.FileName
		}
		disks = append(disks, info)
	}
	return disks
}

// mapVMCDs, mapVMUSBs, and mapVMDisks all walk the same
// config.hardware.device list already fetched for vInfo/vCPU/etc — no
// extra property round-trip needed per device type.
func mapVMCDs(vm mo.VirtualMachine) []cdInfo {
	if vm.Config == nil {
		return nil
	}
	var result []cdInfo
	for _, d := range vm.Config.Hardware.Device {
		cdrom, ok := d.(*types.VirtualCdrom)
		if !ok {
			continue
		}
		base := cdrom.GetVirtualDevice()
		info := cdInfo{
			ID:         fmt.Sprintf("%s-cd%d", vmID(vm), base.Key),
			VMName:     vm.Name,
			PowerState: string(vm.Runtime.PowerState),
		}
		if base.Connectable != nil {
			info.Connected = base.Connectable.Connected
		}
		switch backing := cdrom.Backing.(type) {
		case *types.VirtualCdromIsoBackingInfo:
			path := backing.FileName
			info.ISOPath = &path
		case *types.VirtualCdromAtapiBackingInfo:
			name := backing.DeviceName
			info.DeviceName = &name
		case *types.VirtualCdromRemoteAtapiBackingInfo:
			name := backing.DeviceName
			info.DeviceName = &name
		}
		result = append(result, info)
	}
	return result
}

func mapVMUSBs(vm mo.VirtualMachine) []usbInfo {
	if vm.Config == nil {
		return nil
	}
	var result []usbInfo
	for _, d := range vm.Config.Hardware.Device {
		usb, ok := d.(*types.VirtualUSB)
		if !ok {
			continue
		}
		base := usb.GetVirtualDevice()
		info := usbInfo{
			ID:         fmt.Sprintf("%s-usb%d", vmID(vm), base.Key),
			VMName:     vm.Name,
			PowerState: string(vm.Runtime.PowerState),
			Connected:  usb.Connected,
		}
		if usb.Vendor != 0 {
			v := int(usb.Vendor)
			info.Vendor = &v
		}
		if usb.Product != 0 {
			p := int(usb.Product)
			info.Product = &p
		}
		result = append(result, info)
	}
	return result
}

func mapVMPartitions(vm mo.VirtualMachine) []partitionInfo {
	if vm.Guest == nil {
		return nil
	}
	var result []partitionInfo
	for i, disk := range vm.Guest.Disk {
		result = append(result, partitionInfo{
			ID:          fmt.Sprintf("%s-part%d", vmID(vm), i),
			VMName:      vm.Name,
			DiskPath:    disk.DiskPath,
			CapacityMiB: int(disk.Capacity / (1024 * 1024)),
			FreeMiB:     int(disk.FreeSpace / (1024 * 1024)),
		})
	}
	return result
}

// mapVMNetworks builds one row per virtual NIC (config.hardware.device is
// the baseline, always-present source — a VM without VMware Tools still
// gets a row, just without IP addresses). When guest.net is present (Tools
// running and reporting), its Network field overrides the device-backing
// resolution — guest.net already resolves standard and distributed port
// group names uniformly, so it's authoritative when available; the
// device-backing switch below is the fallback for VMs without Tools.
func mapVMNetworks(vm mo.VirtualMachine, dvpgNames map[string]string) []vmNetworkInfo {
	if vm.Config == nil {
		return nil
	}

	guestNicByKey := map[int32]types.GuestNicInfo{}
	if vm.Guest != nil {
		for _, nic := range vm.Guest.Net {
			guestNicByKey[nic.DeviceConfigId] = nic
		}
	}

	var result []vmNetworkInfo
	for _, d := range vm.Config.Hardware.Device {
		eth, ok := d.(types.BaseVirtualEthernetCard)
		if !ok {
			continue
		}
		base := eth.GetVirtualEthernetCard()
		info := vmNetworkInfo{
			ID:          fmt.Sprintf("%s-net%d", vmID(vm), base.Key),
			VMName:      vm.Name,
			PowerState:  string(vm.Runtime.PowerState),
			NICLabel:    deviceLabel(&base.VirtualDevice),
			AdapterType: adapterTypeLabel(d),
			MacAddress:  base.MacAddress,
		}
		if base.Connectable != nil {
			info.Connected = base.Connectable.Connected
		}

		switch backing := base.Backing.(type) {
		case *types.VirtualEthernetCardNetworkBackingInfo:
			info.Network = backing.DeviceName
		case *types.VirtualEthernetCardDistributedVirtualPortBackingInfo:
			info.Network = dvpgNames[backing.Port.PortgroupKey]
		}

		if nic, ok := guestNicByKey[base.Key]; ok {
			if nic.Network != "" {
				info.Network = nic.Network
			}
			for _, ip := range nic.IpAddress {
				if strings.Contains(ip, ":") {
					if info.IPv6Address == nil {
						v := ip
						info.IPv6Address = &v
					}
				} else if info.IPv4Address == nil {
					v := ip
					info.IPv4Address = &v
				}
			}
		}

		result = append(result, info)
	}
	return result
}

// adapterTypeLabel names the virtual NIC hardware type — mirrors
// controllerLabel's pattern (type-switch over the concrete Go type) for
// the small, fixed set of adapter types vSphere actually offers.
func adapterTypeLabel(d types.BaseVirtualDevice) string {
	switch d.(type) {
	case *types.VirtualVmxnet3:
		return "VMXNET3"
	case *types.VirtualVmxnet2:
		return "VMXNET2"
	case *types.VirtualVmxnet:
		return "VMXNET"
	case *types.VirtualE1000e:
		return "E1000e"
	case *types.VirtualE1000:
		return "E1000"
	case *types.VirtualPCNet32:
		return "PCNet32"
	case *types.VirtualSriovEthernetCard:
		return "SR-IOV"
	default:
		return fmt.Sprintf("%T", d)
	}
}

func mapVMSnapshots(vm mo.VirtualMachine, hostName string, clusterName *string) []vmSnapshotInfo {
	if vm.Snapshot == nil {
		return nil
	}

	// Size is the data (.vmsn metadata) + memory file for this specific
	// snapshot, from layoutEx — deliberately NOT the disk delta chain
	// (VirtualMachineFileLayoutExSnapshotLayout.Disk), because attributing
	// how much of a chain's cumulative size belongs to any one snapshot in
	// the chain isn't well-defined without guessing. This underreports
	// vs. RVTools' "Size MiB (total)" (which does include disk deltas) but
	// every number it reports is real, not estimated.
	fileSizeByKey := map[int32]int64{}
	snapshotLayoutByRef := map[types.ManagedObjectReference]types.VirtualMachineFileLayoutExSnapshotLayout{}
	if vm.LayoutEx != nil {
		for _, f := range vm.LayoutEx.File {
			fileSizeByKey[f.Key] = f.Size
		}
		for _, sl := range vm.LayoutEx.Snapshot {
			snapshotLayoutByRef[sl.Key] = sl
		}
	}

	var result []vmSnapshotInfo
	var walk func(tree []types.VirtualMachineSnapshotTree)
	walk = func(tree []types.VirtualMachineSnapshotTree) {
		for _, s := range tree {
			info := vmSnapshotInfo{
				ID:           fmt.Sprintf("%s-%s", vmID(vm), s.Snapshot.Value),
				VMName:       vm.Name,
				PowerState:   string(vm.Runtime.PowerState),
				SnapshotName: s.Name,
				CreatedDate:  s.CreateTime.UTC().Format(time.RFC3339),
				Quiesced:     s.Quiesced,
				HostName:     hostName,
				ClusterName:  clusterName,
			}
			if s.Description != "" {
				d := s.Description
				info.SnapshotDescription = &d
			}
			if layout, ok := snapshotLayoutByRef[s.Snapshot]; ok {
				var totalBytes int64
				var found bool
				if size, ok := fileSizeByKey[layout.DataKey]; ok {
					totalBytes += size
					found = true
				}
				if layout.MemoryKey != -1 {
					if size, ok := fileSizeByKey[layout.MemoryKey]; ok {
						totalBytes += size
						found = true
					}
				}
				if found {
					mib := int(totalBytes / (1024 * 1024))
					info.SizeMiBTotal = &mib
				}
			}
			result = append(result, info)
			if len(s.ChildSnapshotList) > 0 {
				walk(s.ChildSnapshotList)
			}
		}
	}
	walk(vm.Snapshot.RootSnapshotList)
	return result
}

func mapVMTools(vm mo.VirtualMachine, hostName string, clusterName *string) vmToolsInfo {
	info := vmToolsInfo{
		ID:          vmID(vm),
		VMName:      vm.Name,
		PowerState:  string(vm.Runtime.PowerState),
		HostName:    hostName,
		ClusterName: clusterName,
	}
	if vm.Config != nil {
		info.HardwareVersion = vm.Config.Version
	}
	if vm.Guest != nil {
		info.ToolsStatus = string(vm.Guest.ToolsStatus)
		if vm.Guest.ToolsVersion != "" {
			v := vm.Guest.ToolsVersion
			info.ToolsVersion = &v
		}
	}
	if info.ToolsStatus == "" {
		info.ToolsStatus = "toolsNotInstalled"
	}
	return info
}

// ---------- shared helpers ----------

func vmID(vm mo.VirtualMachine) string {
	if vm.Config != nil && vm.Config.Uuid != "" {
		return vm.Config.Uuid
	}
	return vm.Reference().Value
}

// resolveDatacenterName walks an ancestry map (ComputeResource/Folder ->
// parent) starting from a host's immediate parent until it reaches a
// Datacenter reference, then looks up that Datacenter's name. Bounded to
// 20 hops as a cycle guard — real vCenter folder nesting never comes close.
func resolveDatacenterName(start types.ManagedObjectReference, ancestry map[types.ManagedObjectReference]types.ManagedObjectReference, datacenterNames map[types.ManagedObjectReference]string) (string, bool) {
	current := start
	for i := 0; i < 20; i++ {
		if current.Type == "Datacenter" {
			name, ok := datacenterNames[current]
			return name, ok
		}
		next, ok := ancestry[current]
		if !ok {
			return "", false
		}
		current = next
	}
	return "", false
}

func clusterNameForHost(hostRef *types.ManagedObjectReference, hostParents map[types.ManagedObjectReference]types.ManagedObjectReference, clusterNames map[types.ManagedObjectReference]string) *string {
	if hostRef == nil {
		return nil
	}
	parent, ok := hostParents[*hostRef]
	if !ok {
		return nil
	}
	name, ok := clusterNames[parent]
	if !ok {
		return nil // parent is a plain (non-cluster) ComputeResource — standalone host
	}
	return &name
}

func deviceLabel(d *types.VirtualDevice) string {
	if d.DeviceInfo != nil {
		if summary := d.DeviceInfo.GetDescription(); summary != nil && summary.Label != "" {
			return summary.Label
		}
	}
	return fmt.Sprintf("Disk (key %d)", d.Key)
}

func controllerLabel(devices []types.BaseVirtualDevice, controllerKey int32) string {
	for _, d := range devices {
		base := d.GetVirtualDevice()
		if base.Key != controllerKey {
			continue
		}
		switch d.(type) {
		case *types.ParaVirtualSCSIController:
			return "SCSI controller (Paravirtual)"
		case *types.VirtualLsiLogicController:
			return "SCSI controller (LSI Logic Parallel)"
		case *types.VirtualLsiLogicSASController:
			return "SCSI controller (LSI Logic SAS)"
		case *types.VirtualBusLogicController:
			return "SCSI controller (BusLogic Parallel)"
		case *types.VirtualIDEController:
			return "IDE controller"
		case *types.VirtualAHCIController:
			return "SATA controller (AHCI)"
		case *types.VirtualNVMEController:
			return "NVMe controller"
		default:
			return deviceLabel(base)
		}
	}
	return "Unknown controller"
}

// dvPortgroupKeyNameMap returns DistributedVirtualPortgroup.Key -> Name.
// Deliberately keyed by the `key` property (not the MOID's `.Value`,
// though the two happen to coincide in practice) since `key` is the field
// documented as matching DistributedVirtualSwitchPortConnection.PortgroupKey.
func dvPortgroupKeyNameMap(ctx context.Context, client *govmomi.Client) (map[string]string, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{"DistributedVirtualPortgroup"}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var pgs []mo.DistributedVirtualPortgroup
	if err := cv.Retrieve(ctx, []string{"DistributedVirtualPortgroup"}, []string{"name", "key"}, &pgs); err != nil {
		return nil, err
	}

	result := make(map[string]string, len(pgs))
	for _, pg := range pgs {
		result[pg.Key] = pg.Name
	}
	return result, nil
}

// ---------- name/parent lookups ----------

// nameMap returns moref -> Name for every object of the given vim25 type.
func nameMap(ctx context.Context, client *govmomi.Client, kind string) (map[types.ManagedObjectReference]string, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{kind}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	var objs []mo.ManagedEntity
	if err := cv.Retrieve(ctx, []string{kind}, []string{"name"}, &objs); err != nil {
		return nil, err
	}

	result := make(map[types.ManagedObjectReference]string, len(objs))
	for _, o := range objs {
		result[o.Reference()] = o.Name
	}
	return result, nil
}

// parentMap returns moref -> parent moref for every object of the given type
// (used to resolve a HostSystem's owning ComputeResource/ClusterComputeResource).
func parentMap(ctx context.Context, client *govmomi.Client, kind string) (map[types.ManagedObjectReference]types.ManagedObjectReference, error) {
	m := view.NewManager(client.Client)
	cv, err := m.CreateContainerView(ctx, client.Client.ServiceContent.RootFolder, []string{kind}, true)
	if err != nil {
		return nil, err
	}
	defer cv.Destroy(ctx)

	pc := property.DefaultCollector(client.Client)
	objRefs, err := cv.Find(ctx, []string{kind}, nil)
	if err != nil {
		return nil, err
	}
	var refs []mo.ManagedEntity
	if err := pc.Retrieve(ctx, objRefs, []string{"parent"}, &refs); err != nil {
		return nil, err
	}

	result := make(map[types.ManagedObjectReference]types.ManagedObjectReference, len(refs))
	for _, o := range refs {
		if o.Parent != nil {
			result[o.Reference()] = *o.Parent
		}
	}
	return result, nil
}
