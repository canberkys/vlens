package main

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/vmware/govmomi/performance"
	"github.com/vmware/govmomi/vim25/types"
)

// fakePerfSampler lets a test script exactly which batch (by call order)
// returns data and which one fails, without a live vCenter/vcsim connection.
type fakePerfSampler struct {
	calls          int
	failOnCall     int // -1 disables failure entirely
	failWith       error
	metricsPerCall [][]performance.EntityMetric
}

func (f *fakePerfSampler) sampleBatch(_ context.Context, _ types.PerfQuerySpec, _ []string, _ []types.ManagedObjectReference) ([]performance.EntityMetric, error) {
	call := f.calls
	f.calls++
	if call == f.failOnCall {
		return nil, f.failWith
	}
	if call < len(f.metricsPerCall) {
		return f.metricsPerCall[call], nil
	}
	return nil, nil
}

func refsNamed(n int, prefix string) []types.ManagedObjectReference {
	refs := make([]types.ManagedObjectReference, n)
	for i := range refs {
		refs[i] = types.ManagedObjectReference{Type: "VirtualMachine", Value: prefix + string(rune('a'+i))}
	}
	return refs
}

func metricSeriesFor(ref types.ManagedObjectReference) performance.EntityMetric {
	return performance.EntityMetric{
		Entity: ref,
		Value: []performance.MetricSeries{
			{Name: "cpu.usage.average", Value: []int64{5000}},
		},
	}
}

func TestSamplePerformanceBatchesFirstBatchFails(t *testing.T) {
	refs := refsNamed(60, "vm-") // 2 batches of 50 + 10 at batchSize 50
	nameByRef := map[types.ManagedObjectReference]string{}
	idByRef := map[types.ManagedObjectReference]string{}
	for _, r := range refs {
		nameByRef[r] = r.Value
		idByRef[r] = r.Value
	}

	sampler := &fakePerfSampler{failOnCall: 0, failWith: errors.New("QueryPerf: NotSupported")}

	result, coverage := samplePerformanceBatches(context.Background(), sampler, refs, nameByRef, idByRef, types.PerfQuerySpec{}, 60)

	if len(result) != 0 {
		t.Fatalf("expected no results when the first batch fails, got %d", len(result))
	}
	if coverage.Complete {
		t.Fatal("expected Complete=false when the first batch fails")
	}
	if coverage.RequestedVMCount != 60 {
		t.Fatalf("expected RequestedVMCount=60, got %d", coverage.RequestedVMCount)
	}
	if coverage.CollectedVMCount != 0 {
		t.Fatalf("expected CollectedVMCount=0, got %d", coverage.CollectedVMCount)
	}
	if coverage.Error == nil || *coverage.Error == "" {
		t.Fatal("expected a non-empty Error describing the failure")
	}
}

func TestSamplePerformanceBatchesLaterBatchFails(t *testing.T) {
	refs := refsNamed(60, "vm-") // batch 0 = first 50, batch 1 = remaining 10
	nameByRef := map[types.ManagedObjectReference]string{}
	idByRef := map[types.ManagedObjectReference]string{}
	for _, r := range refs {
		nameByRef[r] = r.Value
		idByRef[r] = r.Value
	}

	firstBatchMetrics := make([]performance.EntityMetric, 50)
	for i, r := range refs[:50] {
		firstBatchMetrics[i] = metricSeriesFor(r)
	}

	sampler := &fakePerfSampler{
		failOnCall:     1,
		failWith:       errors.New("QueryPerf: connection reset"),
		metricsPerCall: [][]performance.EntityMetric{firstBatchMetrics},
	}

	result, coverage := samplePerformanceBatches(context.Background(), sampler, refs, nameByRef, idByRef, types.PerfQuerySpec{}, 60)

	if len(result) != 50 {
		t.Fatalf("expected the first batch's 50 results to survive, got %d", len(result))
	}
	if coverage.Complete {
		t.Fatal("expected Complete=false when a later batch fails")
	}
	if coverage.RequestedVMCount != 60 {
		t.Fatalf("expected RequestedVMCount=60, got %d", coverage.RequestedVMCount)
	}
	if coverage.CollectedVMCount != 50 {
		t.Fatalf("expected CollectedVMCount=50 (only the first batch), got %d", coverage.CollectedVMCount)
	}
	if coverage.Error == nil || *coverage.Error == "" {
		t.Fatal("expected a non-empty Error describing the second batch's failure")
	}
}

func TestSamplePerformanceBatchesFullSuccess(t *testing.T) {
	refs := refsNamed(3, "vm-")
	nameByRef := map[types.ManagedObjectReference]string{}
	idByRef := map[types.ManagedObjectReference]string{}
	metrics := make([]performance.EntityMetric, len(refs))
	for i, r := range refs {
		nameByRef[r] = r.Value
		idByRef[r] = r.Value
		metrics[i] = metricSeriesFor(r)
	}

	sampler := &fakePerfSampler{failOnCall: -1, metricsPerCall: [][]performance.EntityMetric{metrics}}

	result, coverage := samplePerformanceBatches(context.Background(), sampler, refs, nameByRef, idByRef, types.PerfQuerySpec{}, 60)

	if !coverage.Complete {
		t.Fatal("expected Complete=true when every batch succeeds")
	}
	if coverage.Error != nil {
		t.Fatalf("expected no Error on full success, got %q", *coverage.Error)
	}
	if coverage.RequestedVMCount != 3 || coverage.CollectedVMCount != 3 {
		t.Fatalf("expected 3/3, got requested=%d collected=%d", coverage.RequestedVMCount, coverage.CollectedVMCount)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 results, got %d", len(result))
	}
}

// TestBuildPerformanceInfoMergesMultipleDisks is the direct regression test
// for the review's "metric instances for different disks can overwrite each
// other" finding: a VM with two disks produces two separate
// virtualDisk.readIOSize.latest/writeIOSize.latest series (one per disk
// instance) — the merged result must reflect the larger of the two, not
// whichever series happened to be processed last.
func TestBuildPerformanceInfoMergesMultipleDisks(t *testing.T) {
	ref := types.ManagedObjectReference{Type: "VirtualMachine", Value: "vm-multidisk"}
	em := performance.EntityMetric{
		Entity: ref,
		Value: []performance.MetricSeries{
			{Name: "virtualDisk.readIOSize.latest", Instance: "scsi0:0", Value: []int64{1024}},
			{Name: "virtualDisk.readIOSize.latest", Instance: "scsi0:1", Value: []int64{65536}},
			{Name: "virtualDisk.writeIOSize.latest", Instance: "scsi0:0", Value: []int64{32768}},
			{Name: "virtualDisk.writeIOSize.latest", Instance: "scsi0:1", Value: []int64{4096}},
		},
	}
	nameByRef := map[types.ManagedObjectReference]string{ref: "multidisk-vm"}
	idByRef := map[types.ManagedObjectReference]string{ref: "vm-multidisk"}

	info := buildPerformanceInfo(em, nameByRef, idByRef, 60, time.Now())

	if info.MaxReadIOSizeBytes == nil || *info.MaxReadIOSizeBytes != 65536 {
		t.Fatalf("expected merged max read IO of 65536 (the larger disk), got %v", info.MaxReadIOSizeBytes)
	}
	if info.MaxWriteIOSizeBytes == nil || *info.MaxWriteIOSizeBytes != 32768 {
		t.Fatalf("expected merged max write IO of 32768 (the larger disk), got %v", info.MaxWriteIOSizeBytes)
	}
}

func TestBuildPerformanceInfoIgnoresNoDataSeries(t *testing.T) {
	ref := types.ManagedObjectReference{Type: "VirtualMachine", Value: "vm-nodata"}
	em := performance.EntityMetric{
		Entity: ref,
		Value: []performance.MetricSeries{
			// All -1 means the counter is defined but nothing was actually
			// collected — must stay nil, not become a false "0".
			{Name: "cpu.usage.average", Value: []int64{-1, -1, -1}},
		},
	}
	nameByRef := map[types.ManagedObjectReference]string{ref: "nodata-vm"}
	idByRef := map[types.ManagedObjectReference]string{ref: "vm-nodata"}

	info := buildPerformanceInfo(em, nameByRef, idByRef, 60, time.Now())

	if info.AvgCPUUsagePercent != nil || info.MaxCPUUsagePercent != nil {
		t.Fatalf("expected nil CPU fields for an all-(-1) series, got avg=%v max=%v", info.AvgCPUUsagePercent, info.MaxCPUUsagePercent)
	}
}
