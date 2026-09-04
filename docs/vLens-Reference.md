# vLens Reference

This is vLens's own comprehensive reference document, in the spirit of the official
RVTools PDF — one place documenting exactly what every tab shows, where each field
comes from, what's implemented versus still a gap, and how the app is built. Update
this file whenever a tab, field, or architectural decision changes; treat drift
between this document and the code as a bug.

Status snapshot: **2026-09-03**. vLens is pre-release, in active development, not yet
validated against a real production vCenter (see [Testing without a real
vCenter](#testing-without-a-real-vcenter-vcsim)).

---

## 1. What vLens is

vLens is a native macOS alternative to [RVTools](https://www.robware.net/rvtools) —
the Windows-only .NET tool nearly every VMware administrator uses to pull a full
vCenter inventory into a fast, sortable table and export it to CSV/XLSX. There is no
real macOS-native equivalent; Mac-based admins run RVTools in Parallels/BootCamp or
use partial CLI workarounds (see the demand evidence in the project's planning
history: AWS built and ships `awslabs/export-for-vcenter` specifically because
customers on Mac/Linux couldn't use RVTools).

vLens is not a port of anything. A prior attempt at this idea,
`~/Documents/Projects/vInventory`, chose Tauri + a pure-REST-API approach and is
shelved (Windows-only scope, no real backend). vLens is a clean, macOS-first,
native SwiftUI rewrite that also fixes vInventory's core architectural mistake:
RVTools gets ~95% of its data from the SOAP-based vSphere Web Services SDK (vim25)
via `PropertyCollector`, not the newer REST API — so vLens does too, via an embedded
Go/govmomi helper (see [§3](#3-architecture)).

---

## 2. Getting started

```bash
# Swift app
swift build
swift test
swift run vLens          # dev mode; finds the helper via helper/vlens-helper

# Go helper (vSphere client)
cd helper
go build -o vlens-helper .

# Local vCenter simulator — no real vCenter/VPN needed, see §9
go build -o vcsim/vcsim ./vcsim && ./vcsim/vcsim
```

`ConnectionViewModel` (`Sources/vLens/ConnectionViewModel.swift`) resolves the
helper binary in this order: packaged app's `Contents/Resources` → `VLENS_HELPER_PATH`
env var → dev fallback at `helper/vlens-helper` relative to the source tree.

**Demo mode**: the Connect screen has a "Try demo mode" button that loads
`DemoData` (`Sources/vLensCore/Demo/DemoData.swift`) — 40 consistent mock VMs across
every tab — with no network access at all. Use it to review UI changes without any
backend running.

---

## 3. Architecture

```
┌─────────────────────────────┐        stdin/stdout        ┌──────────────────────────┐
│   vLens.app (SwiftUI)        │ ── one JSON line in ──────▶ │  vlens-helper (Go)        │
│   Sources/vLens/              │ ◀── one JSON line out ─────  │  helper/main.go           │
│   Sources/vLensCore/          │                              │  govmomi → vim25 SOAP     │
└─────────────────────────────┘                              └──────────────────────────┘
                                                                          │
                                                                          ▼
                                                              vCenter / ESXi (or vcsim)
```

- **One process per collection run.** The Swift app spawns `vlens-helper` fresh for
  each `collectAll` call rather than keeping a long-lived daemon. This keeps the
  failure mode simple (a crash or hang in the helper can't leak into the next call)
  at the cost of re-authenticating with vCenter every refresh. Revisit only if
  per-call login latency becomes a real problem at higher tab-refresh frequency.
- **`vLensCore`** is a plain Swift library (no AppKit/SwiftUI dependency) so it can
  eventually be shared with a CLI target for headless/`launchd`-driven exports — see
  the gaps list in [§10](#10-known-gaps--roadmap).
- **Why Go/govmomi instead of a pure-Swift SOAP client**: Swift has no maintained
  vSphere SDK. govmomi is the same mature library behind Terraform, Packer, and
  Kubernetes' vsphere provider. Embedding a non-Swift protocol layer inside a native
  Mac app isn't a new pattern for this codebase's author — Docky already embeds
  libssh2/Citadel/NIOSSH for its SSH layer. This spends engineering effort on what
  actually differentiates vLens from RVTools (UI speed, polish, export quality)
  instead of re-deriving a SOAP client govmomi already solved.

### JSON protocol

Request (stdin, one line):

```json
{"action": "collectAll", "url": "https://vcenter.local/sdk", "username": "...", "password": "...", "insecure": true}
```

Response (stdout, one line): `{"ok": true, "error": null, "vms": [...], "cpus": [...], "memory": [...], "disks": [...], "snapshots": [...], "tools": [...], "hosts": [...], "datastores": [...], "clusters": [...]}`

One login, one `PropertyCollector` pass per vim25 object type — every tab's data
comes back together, matching RVTools' own "collect everything up front" behavior
rather than re-authenticating per tab click. **One deliberate exception**:
`collectPerformance` (vPerformance tab, see §4) is its own `HelperAction` with its
own login — `QueryPerf` is a per-entity call, not a `PropertyCollector` batch, and
folding it into `collectAll` would tax every regular refresh for one tab's sake.

The Swift and Go sides are kept in sync
**by hand** (no codegen): `Sources/vLensCore/Helper/HelperProtocol.swift` ↔
`helper/main.go`'s struct definitions. Field names must match exactly — Swift's
synthesized `Codable` keys off property names 1:1, no custom `CodingKeys`. Dates are
encoded as RFC3339/ISO8601 strings on the Go side; the Swift decoder sets
`.dateDecodingStrategy = .iso8601` to match.

---

## 4. Tab reference

Every tab is a representative subset of RVTools' documented columns (source: the
official 145-page Dell RVTools reference), not a 1:1 port — see [§10](#10-known-gaps--roadmap)
for exactly what's missing. All tables support click-to-sort on every column marked
**sortable** below (via `FieldComparator`, `Sources/vLensCore/FieldComparator.swift`) and
are filtered by the single search box against the fields listed under **searchable**.

Tabs are navigated via a `NavigationSplitView` sidebar (`ContentView.sidebar`), grouped
by `AppTab.group` into VM / Infrastructure / Networking / Storage / Licensing / Health /
History sections (`AppTab.swift`) — not a horizontal tab-bar row, which stopped scaling
once the tab count passed ~10. Adding a new tab only requires a `label` and a `group` on
`AppTab`; the sidebar itself needs no changes.

### vInfo

Model: `VirtualMachineInfo` · View: `VInfoTabView` · Source: `mapVMInfo` in `helper/main.go`

| Column | Type | vim25 source | Sortable |
|---|---|---|---|
| VM | String | `name` | ✓ |
| Power | enum (poweredOn/poweredOff/suspended) | `runtime.powerState` | ✓ |
| Guest OS | String? | `config.guestFullName` | ✓ (optional) |
| CPU | Int | `config.hardware.numCPU` | ✓ |
| Memory MiB | Int | `config.hardware.memoryMB` | ✓ |
| Host | String | resolved from `runtime.host` | ✓ |
| Cluster | String? | resolved from host's parent, **only if** it's a `ClusterComputeResource` (blank for standalone hosts — see the bugfix note in §9) | ✓ (optional) |
| IP | String? | `guest.ipAddress` | ✓ (optional) |
| VMware Tools | String? | `guest.toolsStatus` | ✓ (optional) |

Also carried but not yet a column: `template` (Bool, `config.template`), `resourcePoolName`
(String?, resolved from `resourcePool`), `vmUUID` (String, `config.uuid`).
Searchable: name, guestOSFullName, hostName, clusterName, primaryIPAddress.

### vCPU

Model: `VMCpuInfo` · View: `VCpuTabView` · Source: `mapVMCPU`

| Column | Type | vim25 source |
|---|---|---|
| VM | String | `name` |
| Power | enum | `runtime.powerState` |
| CPUs | Int | `config.hardware.numCPU` |
| Sockets | Int | computed: `numCPU / numCoresPerSocket` |
| Cores p/s | Int | `config.hardware.numCoresPerSocket` (defaults to 1 if unset) |
| Overall MHz | Int? | `summary.quickStats.overallCpuUsage`, powered-on VMs only |
| Hot Add | Bool (not sortable — `Bool` isn't `Comparable`) | `config.cpuHotAddEnabled` |
| Hot Remove | Bool (not sortable) | `config.cpuHotRemoveEnabled` |
| Host / Cluster | String / String? | same resolution as vInfo |

Also carried: `reservationMHz` (Int, `config.cpuAllocation.reservation`), `limitMHz`
(Int, `-1` = no limit, `config.cpuAllocation.limit`).

### vMemory

Model: `VMMemoryInfo` · View: `VMemoryTabView` · Source: `mapVMMemory`

| Column | Type | vim25 source |
|---|---|---|
| VM / Power | — | same as above |
| Size MiB | Int | `config.hardware.memoryMB` |
| Consumed MiB | Int? | `summary.quickStats.hostMemoryUsage`, powered-on only |
| Active MiB | Int? | `summary.quickStats.activeMemory` |
| Shared MiB | Int? | `summary.quickStats.sharedMemory` |
| Swapped MiB | Int? | `summary.quickStats.swappedMemory` |
| Ballooned MiB | Int? | `summary.quickStats.balloonedMemory` |
| Host / Cluster | — | same as above |

Also carried: `overheadMiB` (from `consumedOverheadMemory`), `reservationMiB`/`limitMiB`
(from `config.memoryAllocation`), `hotAddEnabled` (`config.memoryHotAddEnabled`).

### vDisk

Model: `VMDiskInfo` (one row per virtual disk device, not per VM) · View: `VDiskTabView` · Source: `mapVMDisks`

| Column | Type | vim25 source |
|---|---|---|
| VM | String | `name` |
| Disk | String | device label (`deviceInfo.label`, falls back to `"Disk (key N)"`) |
| Capacity MiB | Int | `VirtualDisk.capacityInKB / 1024` |
| Thin | Bool (not sortable) | `VirtualDiskFlatVer2BackingInfo.thinProvisioned` |
| Disk Mode | String | `...BackingInfo.diskMode` (e.g. `persistent`) |
| Controller | String | resolved by matching `controllerKey` against sibling devices, labeled by Go type (`ParaVirtualSCSIController`, `VirtualLsiLogicController`, `VirtualIDEController`, `VirtualAHCIController`, `VirtualNVMEController`, etc.) |
| Path | String | `...BackingInfo.fileName`, e.g. `[datastore1] vm/vm.vmdk` |
| Host | String | — |

Iterates `config.hardware.device`, type-asserting to `*types.VirtualDisk`. Devices
that aren't disks are skipped. **Known gap**: doesn't yet resolve `unitNumber`'s
human meaning (SCSI 0:0 style) beyond the raw integer.

### vSnapshot

Model: `VMSnapshotInfo` (one row per snapshot, tree flattened) · View: `VSnapshotTabView` · Source: `mapVMSnapshots`

| Column | Type | vim25 source |
|---|---|---|
| VM | String | `name` |
| Snapshot | String | `VirtualMachineSnapshotTree.name` |
| Description | String? | `...Tree.description` |
| Created | Date | `...Tree.createTime`, RFC3339 over the wire |
| Age (days) | Int (computed) | `VMSnapshotInfo.ageInDays`, `Calendar` diff from `createdDate` to now |
| Size MiB | Int? | `layoutEx.file[]` sizes for the snapshot's data + memory files (see below) |
| Quiesced | Bool (not sortable) | `...Tree.quiesced` |
| Host / Cluster | — | resolved from the VM, not the snapshot |

Recursively walks `snapshot.rootSnapshotList` and each node's `childSnapshotList`.
Size is computed from `config` VM property `layoutEx`: each
`VirtualMachineFileLayoutExSnapshotLayout` entry (keyed by the snapshot's
`ManagedObjectReference`) points at a `dataKey` and (when present, i.e. not `-1`)
a `memoryKey` into `layoutEx.file[]`, whose `size` fields are summed. **Deliberately
excludes** the disk delta chain (`...SnapshotLayout.disk[].chain[]`) — attributing
how much of a chain's cumulative size belongs to any one snapshot isn't well-defined
without guessing, and this project doesn't report numbers it can't stand behind. So
this undercounts vs. RVTools' "Size MiB (total)" (which does fold in disk deltas),
but every byte it does report is real, verified against a real snapshot created in
vcsim (`helper/vcsim/mksnap`), not estimated.

### vTools

Model: `VMToolsInfo` · View: `VToolsTabView` · Source: `mapVMTools`

| Column | Type | vim25 source |
|---|---|---|
| VM / Power | — | — |
| HW Version | String | `config.version` (e.g. `vmx-19`) |
| Tools | enum (`toolsNotInstalled`/`toolsNotRunning`/`toolsOk`/`toolsOld`) | `guest.toolsStatus`; defaults to `toolsNotInstalled` if the property is empty |
| Tools Version | String? | `guest.toolsVersion` |
| Host / Cluster | — | — |

The "Tools" column is colored orange when not `toolsOk` (`VToolsTabView.swift`).

### vNetwork

Model: `VMNetworkInfo` (one row per virtual NIC) · View: `VNetworkTabView` · Source: `mapVMNetworks`

Distinct from `vNic` (host physical pNICs) and `vSC+VMK` (host VMkernel adapters) —
this is "which port group is this VM's virtual NIC connected to," a commonly-used
RVTools tab (rvtools.txt ~line 1581) vLens didn't have until this pass.

| Column | Type | vim25 source |
|---|---|---|
| VM / Power | — | — |
| NIC Label | String | `VirtualDevice.deviceInfo.label`, e.g. "Network adapter 1" |
| Adapter Type | String | Go type of the device (`VirtualVmxnet3`, `VirtualE1000`, etc.), same labeling pattern as vDisk's controller resolution |
| Network | String | see below |
| Connected | Bool | `VirtualDevice.connectable.connected` |
| MAC Address | String | `VirtualEthernetCard.macAddress` |
| IPv4 Address | String? | from `guest.net`, requires VMware Tools |
| IPv6 Address | String? | from `guest.net`, requires VMware Tools |

Iterates `config.hardware.device` (already fetched), type-asserting to
`types.BaseVirtualEthernetCard` — always produces a row, even without VMware Tools,
unlike a `guest.net`-only design would. **Network** resolution has two layers:
the device backing is resolved first (`VirtualEthernetCardNetworkBackingInfo.deviceName`
for a standard vSwitch port group; a `DistributedVirtualPortgroup.key` → name map,
built once per collection, for a distributed port group), then overridden by
`guest.net`'s own `network` field when Tools is present and reporting — matched to
the hardware device via `GuestNicInfo.deviceConfigId == device.key`. This means the
Network/IPv4/IPv6 columns degrade gracefully without Tools rather than the whole row
disappearing. Verified against vcsim with a real distributed port group
(`DC0_DVPG0` resolved correctly via the key→name map, not guessed).

### vCD

Model: `CDInfo` · View: `VCDTabView` · Source: `mapVMCDs`

Per-VM CD/DVD drives, read from `config.hardware.device` — already fetched for
vDisk, so this adds no extra property round-trip.

| Column | Type | vim25 source |
|---|---|---|
| VM / Power | — | — |
| Connected | Bool | `VirtualDevice.connectable.connected` |
| ISO Path | String? | `VirtualCdromIsoBackingInfo.fileName` |
| Device | String? | `VirtualCdromAtapiBackingInfo`/`VirtualCdromRemoteAtapiBackingInfo.deviceName` |

Exactly one of ISO Path/Device is populated depending on backing type; both can
be `nil` for other backing kinds this MVP doesn't distinguish.

### vUSB

Model: `USBInfo` · View: `VUSBTabView` · Source: `mapVMUSBs`

Per-VM USB devices, also read from the already-fetched `config.hardware.device`
list — filters for `*types.VirtualUSB`.

| Column | Type | vim25 source |
|---|---|---|
| VM / Power | — | — |
| Connected | Bool | `VirtualUSB.connected` |
| Vendor | Int? | `VirtualUSB.vendor` (0 treated as absent, mapped to `nil`) |
| Product | Int? | `VirtualUSB.product` (0 treated as absent, mapped to `nil`) |

### vPartition

Model: `PartitionInfo` · View: `VPartitionTabView` · Source: `mapVMPartitions`

Guest-reported disk partitions, from `guest.disk` (added to the VM property
fetch list alongside `summary.quickStats` and the rest — see §9's quickStats
bug fix for the same pattern).

| Column | Type | vim25 source |
|---|---|---|
| VM | String | `vm.name` |
| Disk Path | String | `GuestDiskInfo.diskPath` |
| Capacity MiB | Int | `GuestDiskInfo.capacity / 1MiB` |
| Free MiB | Int | `GuestDiskInfo.freeSpace / 1MiB` |
| Free % | Double (computed) | `PartitionInfo.freePercent`, colored red below 10% |

Requires VMware Tools running and actively reporting guest disk usage — VMs
without Tools, or Tools that haven't reported yet, simply contribute no rows.
`VPartitionTabView` shows a dedicated empty state explaining this rather than
a bare "no rows".

### vPerformance (not an RVTools tab)

Model: `VMPerformanceInfo` · View: `VPerformanceTabView` · Source: `collectPerformance`

RVTools' own columns (vCPU's "Overall MHz", vMemory's "Consumed MiB", etc.) are all
`summary.quickStats` — a single instantaneous value at collection time. This tab is
different in kind: **historical**, sampled over a time window the user picks, via
`PerformanceManager`. Found while surveying `awslabs/export-for-vcenter` (an AWS
Transform for VMware assessment tool that collects the same kind of data) — not
something RVTools itself has, added because it's genuinely useful, not for parity.

| Column | Type | vim25 source |
|---|---|---|
| VM | String | — |
| Avg/Max CPU % | Double? | `cpu.usage.average` counter, averaged/maxed across samples |
| Avg/Max RAM % | Double? | `mem.usage.average` counter |
| Max Read/Write IO Size | Int64? (bytes) | `virtualDisk.readIOSize.latest`/`writeIOSize.latest` counters |

**Why a separate helper action, not part of `collectAll`**: every other collector
is one `PropertyCollector` batch pass — `collectAll`'s whole performance story
(1200 VMs / 0.58s, see §3) depends on that. `QueryPerf` is a per-entity call
(batched here in groups of 50, matching `awslabs/export-for-vcenter`'s own
per-VM batching for the same underlying API); folding it into `collectAll` would
make every regular connect/refresh pay a cost that only this one tab needs. So
`collectPerformance` is its own `HelperAction`, triggered by the tab's own
"Collect" button and time-window picker (1h/4h/24h/7d/30d), not by connecting or
refreshing — powered-off VMs are skipped (no live samples to report).

**Every metric field is optional, not defaulted to 0**: vCenter (or a simulator —
verified against vcsim, whose default model doesn't simulate disk IOPS counters
at all) not reporting a counter is a real, distinct state from "the reading was
zero," and a 0 in this app means a real zero. `averageMax` in `helper/main.go`
also drops `-1` samples (vCenter's own "no data for this sample" sentinel) before
averaging, rather than letting them skew the result toward zero.

Interval-to-sampling-parameters mapping (`perfSamplingParameters` in
`helper/main.go`) mirrors vCenter's own historical-interval documentation:

| Requested window | vCenter interval used |
|---|---|
| ≤ 1 hour | 20-second real-time |
| ≤ 24 hours | 5-minute short-term |
| ≤ 7 days | 30-minute medium-term |
| ≤ 30 days | 2-hour long-term |
| > 30 days | 1-day historical |

### vApp

Model: `VAppInfo` · View: `VAppTabView` · Source: `collectVApps`

A container grouping related VMs with shared power-on order/product
metadata — real vSphere feature, but niche enough (RVTools' own users rarely
rely on it) that vLens deferred it until the RVTools-parity closeout pass.
`VirtualApp` (vim25) extends `ResourcePool`, so this mirrors `collectResourcePools`
almost exactly — same container-view-plus-owner-name-map pattern, over a
different vim25 type, with product metadata (`VAppConfig.Product`) added on top.

| Column | Type | vim25 source |
|---|---|---|
| vApp | String | `name` |
| Owner | String? | resolved from `owner` via the same `ComputeResource` name map as vRP |
| VMs | Int | `len(virtualApp.vm)` |
| Product | String? | `vAppConfig.product[0].name`, first product entry only |
| Version | String? | `vAppConfig.product[0].version` |

Verified against a real `VirtualApp` instance created in vcsim (`helper/vcsim/mkvapp`,
mirrors `mksnap`'s pattern) — not assumed from the type definitions alone. vcsim's
`ResourcePool.createChild` requires every `ResourceAllocationInfo` field set
(reservation/limit/expandable/shares) or it rejects the creation with
`InvalidArgument` — found by testing against the real simulator, not guessed.

### vHost

Model: `HostInfo` · View: `VHostTabView` · Source: `collectHosts`

| Column | Type | vim25 source |
|---|---|---|
| Host | String | `name` |
| Datacenter | String? | resolved by walking the ancestry chain (see below) |
| Cluster | String? | see the cluster-resolution note above |
| Status | enum (red/yellow/green/gray) | `configStatus` |
| CPU Model | String | `summary.hardware.cpuModel` |
| CPU % | Double? (computed) | `overallCpuUsage / (numCpuCores × cpuMhz) × 100` |
| Memory MiB | Int | `summary.hardware.memorySize / 1MiB` |
| Mem % | Double? (computed) | `overallMemoryUsage / memoryTotalMiB × 100` |
| VMs | "running/total" | `numVMsRunning` (computed by a second pass over all VMs' `runtime.powerState`) / `len(host.vm)` |
| ESXi Version | String | `summary.config.product.version` |

Also carried but not yet columns (SwiftUI's `Table` result builder caps at 10
columns — `Cores` was cut in favor of `Datacenter` once it became real data, not
dropped for lack of a slot): `numCpuCores`, `numCpuThreads`, `numNics`/`numHbas`
(`summary.hardware.numNics`/`numHBAs`), `vendor`/`model` (`summary.hardware`),
`maintenanceMode` (`runtime.inMaintenanceMode`).

**Datacenter resolution** (`resolveDatacenterName` in `helper/main.go`): the chain
from a host up to its Datacenter is HostSystem → ComputeResource/ClusterComputeResource
→ one or more nested Folders → Datacenter. `collectHosts` builds one combined
ancestry map over both `ComputeResource` and `Folder` container-view queries, then
walks it generically from each host's immediate parent until it hits a reference
whose `Type` is `"Datacenter"` — this works regardless of how many folder levels a
given environment happens to nest hosts under, without hardcoding a fixed depth.
Verified against vcsim (`datacenterName: "DC0"` for the default model).

### vDatastore

Model: `DatastoreInfo` · View: `VDatastoreTabView` · Source: `collectDatastores`

| Column | Type | vim25 source |
|---|---|---|
| Datastore | String | `summary.name` |
| Type | String | `summary.type` (e.g. `VMFS`, `NFS`) |
| Capacity MiB | Int | `summary.capacity / 1MiB` |
| Free MiB | Int | `summary.freeSpace / 1MiB` |
| Free % | Double (computed) | `DatastoreInfo.freePercent`, colored red below 10% |
| VMs | Int | `len(datastore.vm)` |
| Hosts | Int | `len(datastore.host)` |

### vCluster

Model: `ClusterInfo` · View: `VClusterTabView` · Source: `collectClusters`

Queries `ClusterComputeResource` specifically (not the broader `ComputeResource`
type — see §9).

| Column | Type | vim25 source |
|---|---|---|
| Cluster | String | `name` |
| Status | enum | `configStatus` |
| Hosts | Int | `len(cluster.host)` |
| Effective Hosts | Int | `summary.numEffectiveHosts` (via `GetComputeResourceSummary()`) |
| Total CPU MHz | Int | `summary.totalCpu` |
| Total Memory MiB | Int | `summary.totalMemory / 1MiB` |
| HA | "Enabled"/"Disabled" (not sortable) | `configuration.dasConfig.enabled` |
| DRS | "Enabled"/"Disabled" (not sortable) | `configuration.drsConfig.enabled` |
| Admission Control | "Enabled"/"Disabled" (not sortable) | `configuration.dasConfig.admissionControlEnabled` |

Also carried: `drsDefaultVMBehavior` (String?, `configuration.drsConfig.defaultVmBehavior`).

### vRP

Model: `ResourcePoolInfo` · View: `VRPTabView` · Source: `collectResourcePools`

Resource pools, container view over `ResourcePool`.

| Column | Type | vim25 source |
|---|---|---|
| Name | String | `name` |
| Owner | String? | resolved from `owner` via a `ComputeResource` name map |
| CPU Reservation MHz | Int | `config.cpuAllocation.reservation` |
| CPU Limit MHz | Int (-1 = no limit) | `config.cpuAllocation.limit` |
| Memory Reservation MiB | Int | `config.memoryAllocation.reservation` |
| Memory Limit MiB (-1 = no limit) | Int | `config.memoryAllocation.limit` |
| VMs | Int | `len(resourcePool.vm)` |

The owner lookup reuses the generic `ComputeResource` type (covers both
clusters and standalone-host wrappers) rather than distinguishing them —
unlike the cluster-name resolution used elsewhere (see §9), here any
recognizable owner name is enough; the tab isn't trying to answer "is this
pool on a cluster or a standalone host."

### vSwitch

Model: `VSwitchInfo` · View: `VSwitchTabView` · Source: `collectVSwitchesAndPorts`
(shared with vPort — see below)

Standard (per-host) virtual switches, one row per switch per host.

| Column | Type | vim25 source |
|---|---|---|
| Switch | String | `HostVirtualSwitch.name` |
| Host | String | — |
| Ports | Int | `HostVirtualSwitch.numPorts` |
| Ports Available | Int | `HostVirtualSwitch.numPortsAvailable` |
| MTU | Int | `HostVirtualSwitch.mtu` |
| Uplinks | Int | `len(HostVirtualSwitch.pnic)` |
| Port Groups | Int | `len(HostVirtualSwitch.portgroup)` |

Fetched via `config.network.vswitch` on `HostSystem`.

### vPort

Model: `VPortInfo` · View: `VPortTabView` · Source: `collectVSwitchesAndPorts`

Standard (per-host) port groups. Fetched via `config.network.portgroup` on
`HostSystem`, in the same pass as vSwitch — deliberately combined, not two
separate collectors, because a port group's `vswitch` field is the switch's
**key** (e.g. `key-vim.host.VirtualSwitch-vSwitch0`), not its name, and that
key is only unique per host. Resolving it to a friendly name means building a
key→name map scoped to the same host's vSwitch list; doing both collections in
one pass over the same host record is the only way to get that resolution
right without a second round trip. (This was a real bug caught during vcsim
testing: an earlier version showed the raw key instead of the switch name.)

| Column | Type | vim25 source |
|---|---|---|
| Port Group | String | `HostPortGroupSpec.name` |
| Switch | String | resolved from `vswitch` key via the per-host map above |
| Host | String | — |
| VLAN | Int | `HostPortGroupSpec.vlanId` |

### dvSwitch

Model: `DVSwitchInfo` · View: `DVSwitchTabView` · Source: `collectDVSwitches`

Distributed virtual switches — container view over `DistributedVirtualSwitch`
(matches the `VmwareDistributedVirtualSwitch` concrete subtype too, same
subtype-inclusion behavior noted for `ClusterComputeResource` in §9).

| Column | Type | vim25 source |
|---|---|---|
| Switch | String | `name` |
| UUID | String | `uuid` |
| Ports | Int | `summary.numPorts` |
| Hosts | Int | `len(summary.hostMember)` |
| Port Groups | Int | `len(portgroup)` |

### dvPort

Model: `DVPortInfo` · View: `DVPortTabView` · Source: `collectDVPortgroups`

Distributed port groups — container view over `DistributedVirtualPortgroup`.

| Column | Type | vim25 source |
|---|---|---|
| Port Group | String | `config.name` |
| Switch | String | resolved from `config.distributedVirtualSwitch` via a name map |
| Ports | Int | `config.numPorts` |
| VLAN | Int? | see below |

VLAN resolution only handles the common single-VLAN-ID case: it type-asserts
`config.defaultPortConfig` to `*types.VMwareDVSPortSetting` and its `.vlan` to
`*types.VmwareDistributedVirtualSwitchVlanIdSpec`. Trunk mode and private VLANs
use different concrete types and are deliberately left `nil` rather than
guessed at.

### vNic

Model: `NicInfo` · View: `VNicTabView` · Source: `collectNics`

Physical network adapters, one row per host per pnic, fetched via
`config.network.pnic` on `HostSystem`.

| Column | Type | vim25 source |
|---|---|---|
| Host | String | — |
| Device | String | `PhysicalNic.device` |
| MAC | String | `PhysicalNic.mac` |
| Link Speed Mb | Int? | `PhysicalNic.linkSpeed.speedMb`; `nil` if the link is down/unset |
| Driver | String? | `PhysicalNic.driver`; `nil` if empty |

### vSC+VMK

Model: `VMKernelInfo` · View: `VMKTabView` · Source: `collectVMKernelPorts`

VMkernel network adapters, one row per host per vnic, fetched via
`config.network.vnic` on `HostSystem`. Named `VMKernelInfo` rather than
matching the tab's odd "vSC+VMK" label directly — Service Console adapters
are legacy (pre-ESXi 5.0) and don't apply to any environment this app
targets, so only the VMkernel half is implemented.

| Column | Type | vim25 source |
|---|---|---|
| Host | String | — |
| Device | String | `HostVirtualNic.device` |
| Port Group | String | `HostVirtualNic.portgroup` |
| IP Address | String? | `HostVirtualNic.spec.ip.ipAddress`; `nil` if unset/empty |
| MAC | String | `HostVirtualNic.spec.mac` |

### vHBA

Model: `HBAInfo` · View: `VHBATabView` · Source: `collectHBAs`

Host bus adapters, one row per host per HBA, fetched via
`config.storageDevice.hostBusAdapter` on `HostSystem`.

| Column | Type | vim25 source |
|---|---|---|
| Host | String | — |
| Device | String | `HostHostBusAdapter.device` |
| Model | String | `HostHostBusAdapter.model` |
| Driver | String | `HostHostBusAdapter.driver` |
| Status | String | `HostHostBusAdapter.status` |

### vMultipath

Model: `MultipathInfo` · View: `VMultipathTabView` · Source: `collectMultipaths`

Storage multipathing, one row per host per logical unit, fetched via
`config.storageDevice.multipathInfo` and `config.storageDevice.scsiLun` on
`HostSystem` (joined by the LUN key — vendor/model/operational-state live on
the `ScsiLun` record, path count on the `MultipathInfo` record).

| Column | Type | vim25 source |
|---|---|---|
| Host | String | — |
| Disk | String | `HostMultipathInfoLogicalUnit.lun` |
| Display Name | String | `ScsiLun.displayName` |
| Num Paths | Int | `len(HostMultipathInfoLogicalUnit.path)` |
| Operational State | [String] (joined for display/export) | `ScsiLun.operationalState` |
| Vendor | String | `ScsiLun.vendor` |
| Model | String | `ScsiLun.model` |

Deliberately doesn't extract the path-selection `Policy` field — that's a
type-switch over roughly four concrete vim25 policy types for a display
string of low value on this already-niche tab. `operationalState` covers the
actually useful signal (degraded/dead paths).

### vLicense

Model: `LicenseInfo` · View: `VLicenseTabView` · Source: `collectLicenses`

| Column | Type | vim25 source |
|---|---|---|
| Name | String | `LicenseManagerLicenseInfo.name` |
| Key | String | `licenseKey` |
| Cost Unit | String | `costUnit` |
| Total | Int | `total` |
| Used | Int | `used` |
| Expiration | String? | see below |
| Labels | [String] (joined for display/export) | `labels[]`, formatted `"key: value"` |
| Features | [String] (joined for display/export) | `properties[]` entries where `key == "feature"` |

Uses `govmomi/license.Manager.List()`. **Requires elevated vCenter
permissions** — RVTools' own docs note the same restriction for read-only
accounts. If the call fails, `collectAll` doesn't fail the whole collection;
this one tab just comes back empty (`VLicenseTabView` shows a dedicated empty
state explaining why, rather than a bare "no rows").

Expiration date parsing is defensive rather than guaranteed: it looks for a
`properties[]` entry keyed `expirationDate` (a documented VMware convention,
not part of the typed vim25 schema) and handles it as either an int64 epoch
timestamp or a plain string. Permanent licenses simply omit this property, so
`nil` is the common case, not a bug.

### vHealth

Model: `HealthCheckResult` · View: `VHealthTabView` · Source: `HealthCheckEngine.evaluate`
in `Sources/vLensCore/HealthCheckEngine.swift`

Unlike the other tabs, vHealth isn't collected from vCenter directly — it's computed
from data already gathered for the other tabs, matching RVTools' own design. See
[§5](#5-vhealth-rule-status) for the full rule-by-rule status against RVTools' 24
documented rules.

| Column | Type |
|---|---|
| Severity | enum (red/yellow/green/gray), colored |
| Rule | String |
| Object | String (the VM/host/datastore name the finding is about) |
| Message | String (human-readable, e.g. `"web-01: active snapshot for 22 day(s) (Before patching)."`) |

### Snapshots (not an RVTools tab — local history, own sidebar group)

Model: `InventorySnapshot`/`InventorySnapshotMetrics` · View: `SnapshotsTabView` ·
Source: `ConnectionViewModel.takeSnapshot`/`loadSnapshotHistory`

This app's own idea, not RVTools': take a point-in-time record of a curated set
of aggregate counts, then compare any two records later ("how many VMs did we
have today vs. a month from now"). Nothing to do with vSphere VM snapshots
(`VMSnapshotInfo`/vSnapshot tab) despite the name overlap. Lives in its own
sidebar group, **History** — it isn't vCenter inventory data like every other
group, it's local and persisted.

**What gets captured** (`InventorySnapshotMetrics.compute`, zero extra vCenter
calls — computed from whatever's already loaded in `ConnectionViewModel`):
VM count (total/powered-on/powered-off), host/cluster/datastore counts, the
single **worst** datastore's free % (not an average — an average can hide the
one datastore that's about to fill up), active snapshot count, VMs with Tools
issues, and vHealth red/yellow finding counts.

**Storage**: `SnapshotStore` (JSON under Application Support, same pattern as
`ConnectionProfileStore`) — one file holding every snapshot for every vCenter
host ever connected to; `ConnectionViewModel.loadSnapshotHistory` filters by the
currently-connected host. All fields are cheap scalars, so every metric is
always captured — there's no "pick which fields to save" option, because that
would only add null-handling complexity for zero storage benefit.

**What's user-configurable instead**: which metric rows the Compare panel
*displays* — `SnapshotPreferencesStore` (UserDefaults, same pattern as
`HealthCheckPreferencesStore`), toggled in Preferences under "Snapshot
comparison metrics." Each metric also carries a `MetricComparisonDirection`
(`higherIsBetter`/`lowerIsBetter`/`neutral`) so the Compare panel's delta
column colors green/red based on whether the change is actually good or bad
for that specific metric, not just its sign — e.g. more active snapshots is
red, more free datastore space is green, more total VMs is neutral (growth
isn't inherently good or bad).

**(v1.1, 2026-09-04) Storage location is user-configurable**:
`SnapshotPreferencesStore.customStorageDirectory` (plain path string in
UserDefaults, not a security-scoped bookmark — vLens isn't sandboxed, so the
extra complexity buys nothing) overrides where `inventory-snapshots.json`
lives; `nil` (the default) resolves to `SnapshotStore.defaultDirectory`
(Application Support). Set from Preferences → "Snapshot storage" (current
path, Reveal in Finder, Change Location…, Reset to Default). Switching
**copies** the existing file into the new location (never moves — the old
file is left in place as a safety net) only when the new location doesn't
already have one. No concurrent-write protection is provided if two vLens
instances point at the same shared folder simultaneously — documented
single-writer assumption, not a real sync mechanism.

**(v1.1, 2026-09-04) Optional full VM inventory + "VM Changes" diff**: the
"Take Snapshot" row has an "Include full VM inventory" checkbox (default
**off** — keeps the lightweight-by-default behavior, especially once a
scheduler is taking snapshots unattended). When on, `InventorySnapshot.fullVMList`
embeds the current `[VirtualMachineInfo]` array. When **both** snapshots being
compared have a `fullVMList`, the Compare panel adds a "VM Changes" section
below the metrics table — VMs added/removed, matched by `vmUUID` (a simple
set difference, not a field-by-field diff of every VM's CPU/memory/etc. —
deliberately out of scope, a much bigger feature). Snapshots list rows show a
small icon next to entries that carry full detail.

---

## 5. vHealth rule status

RVTools documents 24 built-in health-check rules (rvtools.txt's vHealth section).
vLens implements the 10 computable from data the other tabs already collect. All
numeric thresholds are user-adjustable — RVTools' equivalent is its Health
Properties panel; vLens' is the standard macOS Settings scene (Cmd+,,
`Sources/vLens/PreferencesView.swift`), backed by `HealthCheckPreferencesStore`
(UserDefaults). Changing a threshold there re-evaluates vHealth immediately against
whatever's already collected, in both the main window and the shared
`ConnectionViewModel` — no reconnect needed.

| # (RVTools numbering) | Rule | vLens status |
|---|---|---|
| 1 | VM has a CDROM device connected! | ✅ Implemented — one finding per connected CD/DVD device |
| 3 | VM has an active snapshot! | ✅ Implemented — one finding per snapshot, includes age in the message |
| 4 | VMware tools are out of date, not running or not installed! | ✅ Implemented — severity red if not installed, yellow otherwise |
| 5 | On disk xx is yy% disk space available! (guest-level) | ✅ Implemented — reads vPartition, default threshold 10%, adjustable in Preferences |
| 6 | On datastore xx is yy% disk space available! | ✅ Implemented — default threshold 10%, adjustable in Preferences |
| 7 | There are xx virtual CPUs active per core on this host! | ✅ Implemented — default threshold 4.0, adjustable in Preferences |
| 8 | There are xx VMs active on this datastore! | ✅ Implemented — counts registered VMs (`numVMsTotal`), not power-state-filtered; default threshold 30, adjustable in Preferences |
| 12 | Multipath operational state | ✅ Implemented — flags any path not in `active`/`standby` state |
| 13 | Virtual machine consolidation needed | ✅ Implemented — reads `runtime.consolidationNeeded`, one finding per VM needing it |
| — | Host config status not green | ✅ Implemented (not a numbered RVTools rule, rolled into the general vHealth concept) |
| 2 | VM has a Floppy device connected! | ❌ needs a vFloppy tab (not built — floppy devices are effectively extinct on modern guests, low priority) |
| 9 | Possibly a zombie vmdk file! | ❌ needs `vFileInfo` (datastore file browser — deliberately deferred, see §10) |
| 10 | Possibly a zombie vm! | ❌ same dependency |
| 11 | Inconsistent Folder Names | ❌ needs folder-path data vLens doesn't collect yet — buildable without a real vCenter (vcsim), planned in the parity-closeout pass |
| 14 | Search datastore errors | ❌ N/A without a datastore browser |
| 15 | VM config issues | ❌ needs `configIssue` events, not fetched |
| 16 | Host config issues | ❌ same |
| 17 | NTP issues | ❌ needs host NTP config, not fetched |
| 18 | Cluster config issues | ❌ needs `configIssue` on clusters |
| 19 | Datastore config issues | ❌ same |
| 20 | ESXi shell enabled warning | ❌ needs host service state, not fetched |
| 21 | SSH enabled warning | ❌ same |
| 22 | Disk I/O performance tip (PVSCSI controller count vs. disk count) | ❌ logic is well-defined (see rvtools.txt) but not implemented |
| 23 | In-memory performance tip (NUMA/hot-add settings) | ❌ same |
| 24 | Certificate expiry warning | ❌ needs host certificate info, not fetched |

Add new rules to `HealthCheckEngine.evaluate` as their source tabs/properties get
built — the function signature already takes every currently-collected array, so
most new rules are pure additions, not refactors.

---

## 6. Export

`Sources/vLensCore/CSVExport.swift` defines a `CSVExportable` protocol (`csvHeader`
+ `csvRow`) implemented by every model, and a `CSVWriter` that RFC 4180-escapes
fields (quotes any value containing a comma, quote, or newline; doubles embedded
quotes). The toolbar's "Export" menu (`ContentView.swift`) offers "Export as CSV"
and "Export as XLSX", both driven by `Sources/vLens/ExportPanel.swift`'s standard
`NSSavePanel`, and both export whatever the current tab shows — already filtered by
the search box, matching what the user is actually looking at.

**XLSX** (`Sources/vLensCore/XLSXExport.swift`, `XLSXWriter`) is a minimal,
dependency-light OOXML writer built on
[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) rather than a full
spreadsheet library — no mature "write .xlsx" Swift package exists. It reuses each
model's existing `CSVExportable` header/row data, so there's no separate per-model
XLSX mapping to maintain. Design choices:

- **One sheet, no shared-strings table.** Cells use inline strings
  (`t="inlineStr"`) instead of a deduplicated shared-strings part — simpler to
  generate correctly, and at these row counts the size difference is negligible.
- **Numeric cells are real numbers**, not text. `XLSXWriter` conservatively detects
  whether a cell's string value parses as `Int` or `Double` and writes a numeric
  `<v>` cell instead of an inline string when it does, so Excel/Numbers sort and sum
  those columns correctly. Deliberately conservative — version strings like
  `"8.0.3"` and IP addresses don't parse as a single number, so they correctly stay
  text.
- **Sheet names are sanitized** to Excel's real constraints: max 31 characters, no
  `[ ] : * ? / \`.
- **Tested via a real round-trip**, not just "it compiles": `XLSXExportTests.swift`
  writes a file with `XLSXWriter`, then reads it back with `ZIPFoundation`'s own
  independent read path (`Archive(data:accessMode:.read)`) and asserts on the
  actual XML content — including that special characters were escaped and numeric
  cells came back as real numbers, not strings. This is a meaningfully independent
  check: the read path and write path are different code in a mature third-party
  library, not our own code checking itself.

**PDF report** (`Sources/vLens/ReportView.swift` + `ReportRenderer.swift`) is a
different kind of output from CSV/XLSX — not a tab data dump, a curated one-page
management summary (vCenter identity/version, VM/host/cluster/datastore counts, a
power-state chart and a datastore free-space chart via native **Swift Charts**, a
vHealth red/yellow summary). Toolbar's "Report" button, next to "Export". Rendered
via `ImageRenderer`'s closure-based `render(rasterizationScale:renderer:)` straight
into a `CGContext`-backed PDF (`CGDataConsumer`/`beginPDFPage`/`endPDFPage`) — the
documented way to get SwiftUI content into an arbitrary graphics context, not just
an image. One page, sized to the view's natural height — deliberately not
paginated, since this is meant to be skimmed in one screen, not read like a report
document. No new dependency (Swift Charts and `ImageRenderer` are both part of the
SDK on this app's macOS 14 minimum). This is why CSV/XLSX still doesn't do PDF: a
data export needs every row, which a one-page infographic can't hold — the two
serve different purposes rather than one superseding the other.

---

## 7. Search

One text field above every tab (`ContentView.toolbar`), filtering live against each
model's `Searchable.searchableText` (`Sources/vLensCore/Searchable.swift`) — a
lowercase-insensitive substring match (`localizedCaseInsensitiveContains`) over a
per-model blob of the fields that matter (name, host, cluster, IP, guest OS, etc. —
see each model's `Searchable` extension for the exact field list).

---

## 8. Connections & credentials

- **Ephemeral by default**: typing host/username/password and pressing Connect
  never touches disk.
- **"Save this connection to Keychain"** toggle: on success, `ConnectionProfile`
  (host + username, *never* the password) is upserted into
  `ConnectionProfileStore` — JSON at `~/Library/Application Support/vLens/connection-profiles.json`
  — and the password is written to the macOS Keychain via `KeychainCredentialStore`
  (service `com.vlens.credentials`, keyed by a per-profile UUID reference ID). The
  shape of this — `CredentialStoreProtocol` + Keychain impl + an ephemeral in-memory
  impl for "don't save" — deliberately mirrors Docky's own
  `Core/Keychain/CredentialStoreProtocol.swift`, a proven pattern reused rather than
  re-derived.
- **"Saved connections" menu** on the Connect screen lets the user pick a saved
  profile, which fills the form and recalls the password from Keychain — the user
  still has to press Connect, nothing auto-connects.
- **Certificate trust-on-first-use** (`Sources/vLensCore/CertificateTrust.swift`):
  mirrors Docky's `Core/SSH/HostKeyTrust.swift` pattern (`CertificateFingerprint`,
  `TrustedCertificate`, `CertificateTrustDecision`, `LocalJSONCertificateTrustStore`
  — same shape, same on-disk JSON approach, same TOFU semantics), adapted from SSH
  host keys to TLS certs. Before every connection, `ConnectionViewModel` calls the
  helper's `getCertificate` action (`helper/main.go`'s `fetchCertificate` — a raw
  TLS dial with no vCenter login, just to see what certificate is being presented)
  and checks it against the trust store:
  - **Trusted** (fingerprint matches a prior record): proceeds silently.
  - **Unknown** (first contact): `pendingCertificateApproval` is set, and
    `ContentView` shows a confirmation sheet with the subject, issuer, expiry, and
    a colon-separated SHA-256 fingerprint (the same display format vSphere admins
    already recognize from ESXi host SSL thumbprints). "Trust & Connect" pins the
    fingerprint and proceeds; "Cancel" aborts.
  - **Mismatch** (a previously-pinned host now presents a different fingerprint):
    hard block, `CertificateMismatchError`, no "connect anyway" escape hatch — this
    is the actual MITM defense, and it's stricter than RVTools itself, which
    doesn't do certificate verification at all.

  Deliberate simplification: since on-prem vCenter overwhelmingly uses self-signed
  or internal-CA certificates, vLens doesn't try to distinguish "real CA-signed" from
  "self-signed" — every host gets fingerprint-pinned via TOFU, matching how Docky
  already treats every SSH host. Transport-level validation
  (`govmomi.NewClient`'s `insecure` flag) is therefore always `true`; the trust
  decision happens explicitly, before credentials are ever sent, not implicitly via
  the OS's CA trust store. There is no longer an "Allow self-signed certificate"
  toggle — TOFU pinning replaced it entirely, and `ConnectionProfile` no longer
  carries an `allowInsecureTLS` field. Trust records live independently of saved
  connection profiles (keyed by host, not by profile ID), so even an ephemeral,
  never-saved connection is still protected.

---

## 9. Testing without a real vCenter: vcsim

**Context**: as of 2026-09-03 the user's VPN access to their real vCenter has been
revoked by their Nw-Sec team, with no ETA for restoration outside the office. This
does **not** block real integration testing.

govmomi ships a `simulator` package — the same engine behind the upstream `vcsim`
CLI tool — that stands up a real SOAP/PropertyCollector HTTP(S) server backed by an
in-memory simulated vCenter inventory. `helper/vcsim/main.go` is a small dev-only
wrapper around it:

```go
model := simulator.VPX()
model.Datacenter = 1
model.Cluster = 4
model.ClusterHost = 8
model.Host = 2       // + standalone hosts outside any cluster
model.Datastore = 12
model.Machine = 200  // → ~1,200 VMs at these counts
model.Create()
model.Service.TLS = new(tls.Config)  // self-signed HTTPS, matches real vCenter
server := model.Service.NewServer()
```

Run it (`go build -o vcsim/vcsim ./vcsim && ./vcsim/vcsim`), then point either
`vlens-helper` directly or the vLens app's Connect screen at the printed URL
(`https://127.0.0.1:PORT/sdk`, username `user`, password `pass` — vcsim accepts any
credentials). The first connect will show the certificate trust-on-first-use sheet
(see [§8](#8-connections--credentials)) — approve it, same as you would for a real
vCenter's self-signed certificate.

This is **not a mock** — `vlens-helper` performs a real login and real
`PropertyCollector` calls against it, over real HTTPS. It validates:

- The entire Swift ↔ Go JSON contract end to end
- Every govmomi property path actually resolves the way the code assumes
- Performance at real RVTools scale

**What it already caught**: while first testing `collectAll` against vcsim, the
returned data showed *every* host — including deliberately standalone ones with no
real cluster — reporting a cluster name. The bug: every `HostSystem` has an
invisible per-host `ComputeResource` wrapper in the vSphere object model, distinct
from an actual `ClusterComputeResource`. The original code queried the broad
`"ComputeResource"` container-view type (which matches both, since
`ClusterComputeResource` is a vim25 subtype), so standalone hosts got a fake
"cluster." Fixed by querying `"ClusterComputeResource"` specifically for the
cluster-name lookup — real vCenter/RVTools leave the Cluster column blank for
standalone hosts, and vLens now matches.

**Performance validated**: `collectAll` against a 1,200-VM / 34-host / 4-cluster /
12-datastore vcsim model completed in **0.58 seconds**. No performance concern at
the scale RVTools' own userbase typically runs.

**What vcsim can't validate**: anything specific to the user's actual environment —
their real naming conventions, real-world edge cases (weird guest OS strings,
unusual controller types, actual certificate chains), and genuine end-to-end UI
interaction against a live target. Once VPN access returns, a real-vCenter pass is
still worth doing — but it's no longer the blocker it looked like.

---

## 10. Known gaps & roadmap

Organized by "buildable without a real vCenter" (everything, via vcsim + demo data)
versus what's simply not started yet:

**Missing tabs** (1 of RVTools' 24 — every tab now has a vLens counterpart except
this one, see [§4](#4-tab-reference)): `vFileInfo` (datastore file browser).
Explicitly out of scope indefinitely since RVTools' own docs flag it as slow and
rarely used interactively — this is the one tab that's a deliberate, permanent
scope decision rather than a "not gotten to it yet."

**vHealth**: 10 of 24 rules implemented, 14 remaining — see [§5](#5-vhealth-rule-status)
for the full table.

**Export**: CSV and XLSX are both done — see [§6](#6-export). A PDF **report**
(one-page management summary, not a tab data dump) is also done, see §6's "PDF
report" note — RVTools itself doesn't have anything like it.

**Automation**: a CLI target sharing `vLensCore`, driven by `launchd` (the macOS
analogue of the Windows Task Scheduler workflows RVTools users lean on for scheduled
headless exports). Not started.

**Multi-vCenter merge**: RVTools ships a separate `RVToolsMergeExcelFiles` utility.
vLens's MVP supports one active connection at a time, switchable. Not started.

**Distribution**: `scripts/release.sh` builds a real, signed `.app` bundle now —
`swift build -c release`, hand-constructed `Contents/{MacOS,Resources}` (no Xcode
project — mirrors the same developer's already-proven PkgLens release pattern),
signs the embedded `vlens-helper` binary before the outer app (nested code must
be signed first), verified with `codesign --verify --deep --strict`. Only
notarization/DMG remain gated on a one-time manual step (`xcrun notarytool
store-credentials`, needs an Apple ID app-specific password — can't be automated,
needs the developer's own Apple ID login) — the script detects whether that's
done and skips straight to a clear instruction if not, rather than failing.
`Resources/Info.plist` carries real versioning (`CFBundleShortVersionString`
1.0.0 — the first real release; Package.swift's old "v0.1.0" comment was never
distributed) and `Resources/AppIcon.icns` (placeholder, SF Symbol-based, per
§10's icon note below). Auto-update (target: Sparkle) still needs the
notarized/hosted release this unblocks. The project itself is on GitHub
(`github.com/canberkys/vlens`, private) as of 2026-09-04 — this unblocked the
Feedback screen's GitHub-Issue channel, see [§13](#13-feedback--bug-reports).
See `~/.claude/plans/swirling-painting-snail.md` for the phased plan.

**VMSA security advisory awareness**: Phase A done — see [§12](#12-security-advisory-awareness).
Phase B (build-level matching against `HostInfo.esxVersion`/`VCenterInfo.build`)
deliberately deferred — depends on scraping a per-advisory detail-page format
Broadcom doesn't document or guarantee to keep stable.

**In-app Help & Tutorials**: done — see [§11](#11-in-app-help--onboarding).

---

## 11. In-app Help & Onboarding

**About** (`Sources/vLens/AboutView.swift`) replaces SwiftUI's default About
panel (`CommandGroup(replacing: .appInfo)` in `vLensApp.swift`) — the default
panel reads version info from `Bundle.main`'s Info.plist, which is empty in
`swift run` development mode (only the real packaged `.app` has one), so it'd
show blank. `AppVersion.swift` reads `Bundle.main` first (correct in the
packaged app) and falls back to the same values hardcoded in
`Resources/Info.plist` (correct in dev mode) — same shape as
`HelperLocator.resolve()`'s bundle-then-dev-fallback pattern.

**Help** (`Sources/vLens/HelpView.swift`) replaces the default Help menu item
(`CommandGroup(replacing: .help)` in `vLensApp.swift`) rather than linking out
to an external site. `HelpTopic` is a small enum (Getting Started, Tabs,
Snapshots & Compare, vPerformance, Security Advisories, Export & Reports,
Feedback & Bug Reports, Preferences) with hand-written, user-facing copy —
deliberately not a rendering of this reference doc, which is written for
contributors, not end users. Opens as its own `Window` scene, Cmd+Shift+? or
Help menu. Styled loosely after macOS' own Tips app (user feedback,
2026-09-04) — each topic carries an `accentColor` and renders as a colored
`RoundedRectangle` icon badge, in both the sidebar rows and a larger version
at the top of the detail pane, rather than a plain text list.

**Onboarding** (`Sources/vLens/Tutorial.swift`, `Sources/vLensCore/TutorialStore.swift`):
a first-run welcome (`WelcomeOverlayView`, one dismissible sheet over the
connect screen — 3 bullets, not a multi-step slideshow; the audience is
technical/pro users, not consumers) plus a reusable `.tutorialPopover(id:title:text:)`
view modifier any tab view can attach to show a one-time coachmark on first
visit. Applied deliberately, not to every tab: Snapshots and vPerformance
(vLens' own inventions, no RVTools equivalent), vHealth (the one tab that's
computed rather than collected), and vNetwork (easily confused with vNic/
vSC+VMK, which are host-level, not per-VM). A direct, obviously-named RVTools
mirror (vInfo, vCPU, vDisk, ...) doesn't get one — an admin who knows RVTools
already knows what it does, and a coachmark on every tab would be exactly the
kind of nagging this feature exists to avoid. When adding a new tab, the test
is "would an RVTools-literate admin be confused by this one specifically" —
see the doc comment on `TutorialID` in `Tutorial.swift`. `TutorialStore` is the same
UserDefaults-backed one-time-flag pattern as `HealthCheckPreferencesStore`/
`SnapshotPreferencesStore`, keyed by freeform IDs (`TutorialID` in
`Tutorial.swift`) — **a new feature that wants a coachmark just adds a new ID
constant and one `.tutorialPopover(...)` call on its tab view, no other
wiring**. Preferences has a "Reset Tutorials" button (clears every ID in
`TutorialID.all`) for deliberately seeing them again.

---

## 12. Security advisory awareness

Not RVTools' concept — vLens keeps admins aware of recently-published VMware/
Broadcom security advisories (VMSAs) without them needing to check the support
portal manually. Independent of any vCenter connection: a plain HTTPS call,
doesn't go through the Go helper.

**`Sources/vLensCore/VMSAClient.swift`**: `POST
https://support.broadcom.com/web/ecx/security-advisory/-/securityadvisory/getSecurityAdvisoryList`,
no auth. This endpoint (not the GET URL Broadcom's own documentation names —
that one 404s in practice) was found and verified with real requests during
planning:

- The documented GET endpoint from
  `knowledge.broadcom.com/external/article/408302/json-api-for-product-security-advisories.html`
  doesn't actually work.
- This POST endpoint (independently confirmed by community write-ups, e.g.
  William Lam's) does, and returns far more than the minimal "title/ID/date/
  link" originally assumed during planning: **severity tier** (`CRITICAL`/
  `HIGH`/`MEDIUM`/`LOW`, verified against live data), a **comma-separated CVE
  list**, and affected product names — all without needing to scrape any
  per-advisory detail page. What's still *not* here: a numeric CVSS score and
  exact affected build ranges (Phase B, deferred — see §10).
- `segment=VC` was verified to return the full VMware-by-Broadcom family
  relevant to a vSphere admin (ESX, vCenter, Cloud Foundation, Workstation,
  Fusion, Aria Operations), not narrowly VCF-only as some documentation implies.

`SecurityAdvisory` (`Models/SecurityAdvisory.swift`) keeps `severity` as a raw
`String`, not a strict enum — this is an external, unversioned API vLens
doesn't control; a future severity value it doesn't recognize should degrade
gracefully (fall through a `default` case in the UI), not fail to decode and
break the whole feature. `isNotable` (`CRITICAL`/`HIGH` only) is what the
toolbar badge counts — deliberately excludes `MEDIUM`/`LOW` so a non-zero badge
stays meaningful rather than becoming background noise.

**UI**: `ConnectionViewModel.checkSecurityAdvisories()` fires once per launch
(`ContentView`'s `.task`, independent of connect/demo state) and silently
no-ops on any failure — network down, Broadcom changes the response shape,
anything — this is a nice-to-have, never something that should interrupt or
alarm the user with an error dialog. A toolbar button (`shield.lefthalf.filled`,
red) appears **only when there's something notable to show** — no icon at all
when the count is zero, rather than a permanently-present-but-uninformative
indicator. Tapping it opens `SecurityAdvisoriesView`, a popover listing each
advisory's severity, publish date, and title, linking out to Broadcom's own
advisory page for the full text.

**Grouped by recency and tagged by affected product** (user feedback,
2026-09-04) — advisories render under section headers (New/This Month/This
Year/Older, bucketed off `publishedDate`) instead of one flat list, and each
row shows small tag chips parsed from `affectedProducts` (e.g. `ESXi`,
`vCenter`, `Workstation`) so a user who doesn't run a given product can tell
without clicking through. The API's own truncation quirk (`"VMware
Fusion,VMware Work..."` — see above) is handled by stripping any `...`-suffixed
fragment rather than showing a meaningless partial word as its own tag.

**Tested against a real captured response** (`VMSAClientTests.swift`), not a
guessed schema — the fixture JSON is a verbatim response from a live request
made during development. Uses a stubbed `URLProtocol` (not a live network call
in tests) so the suite stays offline-safe and deterministic; the stub's shared
mutable response state means these specific tests must run serialized
(`@Suite(.serialized)`) rather than in Swift Testing's default parallel mode.

---

## 13. Feedback / bug reports

`Sources/vLens/FeedbackView.swift`, reached from the Help menu ("Send
Feedback…", `vLensApp.swift`'s Feedback `Window` scene). Faz 5 of
`~/.claude/plans/swirling-painting-snail.md` — **done, both channels**: email
and GitHub Issue. The project moved to GitHub (`github.com/canberkys/vlens`,
private) on 2026-09-04, which unblocked the second channel.

Fields: type (Bug Report / Feature Request), title, description, and
automatically-attached diagnostic info shown transparently before sending —
macOS version, and connected vCenter's version/build if there is one.
**Never** the vCenter host, username, or password.

- **"Send via Email"** builds a `mailto:` URL (`URLComponents`, scheme
  `mailto`) and opens it with `NSWorkspace.shared.open` — the user's own mail
  client opens with a ready-made draft that *they* review and send.
- **"Open as GitHub Issue"** builds a prefilled
  `github.com/canberkys/vlens/issues/new?title=...&body=...&labels=...` URL
  (label `bug` or `enhancement` depending on the selected type — both exist
  as GitHub's own default labels, verified via `gh api repos/.../labels`
  rather than assumed) and opens it in the browser — the user's own GitHub
  session reviews and submits it.

Both are the same "prefilled deep link, human confirms" pattern — no
backend, no embedded credentials. Sending an email or opening a GitHub issue
automatically and silently would need a secret (SMTP creds or a GitHub
token) shipped inside the app binary, extractable by anyone — a real
security anti-pattern this deliberately avoids. A *silent*, one-click send
(no visible mail client/browser step) was explicitly requested and just as
explicitly deferred to release time — see the note in
`~/.claude/projects/-Users-c-kilicarsl/memory/project_vlens.md` and Faz 5's
"Kullanıcı onayı" note in the plan file: it needs a small serverless relay
holding the secret server-side, real infrastructure not yet justified before
the app has real users.

**On "PR" vs. "issue"**: the user also asked about feature requests becoming
GitHub PRs directly, not just issues. Deliberately not built — auto-opening a
PR (an actual code change) from a freeform text description isn't something
a mechanical transformation can respect; it needs a human/agent to actually
understand the request and write the fix. What issues *do* enable: a future
Claude Code session can be pointed at an open issue and triage/fix/PR it
quickly — a workflow, not a feature embedded in the app.

Recipient is currently a hardcoded default (the developer's own address) —
confirm or change `FeedbackView.recipientEmail` before relying on this for
real user feedback.
