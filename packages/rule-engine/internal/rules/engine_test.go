package rules

import (
	"context"
	"testing"
)

func TestPhase1_Rule1_ThreeStep_SingleBlock_NoPause(t *testing.T) {
	// PHASE-1-TC-07: Rule 1 three-step — does not fire on single-block spike
	r1 := NewFTSORule(2.0, 0.015)
	r1.CurrentZScore = 3.5
	r1.CurrentAnchorDev = 0.05

	ctx := context.Background()
	// Block 1
	v1 := r1.Evaluate(ctx, 100)
	if v1.Severity != SeverityInfo {
		t.Fatalf("Expected Info severity on step 1, got %d", v1.Severity)
	}
}

func TestPhase1_Rule1_ThreeStep_Sustained_FiresMedium(t *testing.T) {
	// PHASE-1-TC-08: Rule 1 three-step — fires when sustained across 3 blocks
	r1 := NewFTSORule(2.0, 0.015)
	r1.CurrentZScore = 3.5
	r1.CurrentAnchorDev = 0.05

	ctx := context.Background()
	_ = r1.Evaluate(ctx, 100) // step 1
	_ = r1.Evaluate(ctx, 101) // step 2
	v3 := r1.Evaluate(ctx, 102) // step 3

	if v3.Severity != SeverityMedium {
		t.Fatalf("Expected Medium severity on step 3 sustained, got %d", v3.Severity)
	}
	if v3.RulesTriggered&RuleBit1FTSO == 0 {
		t.Fatalf("Expected RuleBit1FTSO set in verdict")
	}
	if v3.OpsPauseDuration == 0 {
		t.Fatalf("Expected opsPauseDuration > 0 for Medium severity")
	}
}

func TestPhase1_Rule2_IgnoresSingleAgentDrop(t *testing.T) {
	// PHASE-1-TC-09: Rule 2 — ignores single-agent drops
	r2 := NewCRRule()
	r2.AffectedAgents = 1
	r2.DropPct = 0.15 // 15% drop

	ctx := context.Background()
	v := r2.Evaluate(ctx, 100)
	if v.Severity != SeverityInfo {
		t.Fatalf("Expected Info for single agent drop, got %d", v.Severity)
	}
}

func TestPhase1_Rule2_FiresOnCorrelatedCollapse(t *testing.T) {
	// PHASE-1-TC-10: Rule 2 — fires on correlated collapse across 5 agents
	r2 := NewCRRule()
	r2.AffectedAgents = 5
	r2.DropPct = 0.08 // 8% drop

	ctx := context.Background()
	v := r2.Evaluate(ctx, 100)
	if v.Severity != SeverityMedium {
		t.Fatalf("Expected Medium severity for correlated collapse, got %d", v.Severity)
	}
	if v.RulesTriggered&RuleBit2CR == 0 {
		t.Fatalf("Expected RuleBit2CR set")
	}
}

func TestPhase1_Rule3_BurstAlone_NoPause(t *testing.T) {
	// PHASE-1-TC-11: Rule 3 — burst alone, no pause (INFO alert only)
	r3 := NewRedeemRule()
	r3.CurrentVolumeMultiple = 10.0
	r3.FDCAttestationTimeout = false // Attested in time

	ctx := context.Background()
	v := r3.Evaluate(ctx, 100)
	if v.Severity != SeverityInfo {
		t.Fatalf("Expected Info severity for burst alone, got %d", v.Severity)
	}
}

func TestPhase1_Rule3_CompoundFires(t *testing.T) {
	// PHASE-1-TC-12: Rule 3 — compound burst + FDC timeout fires HIGH
	r3 := NewRedeemRule()
	r3.CurrentVolumeMultiple = 10.0
	r3.FDCAttestationTimeout = true // Timeout exceeded

	ctx := context.Background()
	v := r3.Evaluate(ctx, 100)
	if v.Severity != SeverityHigh {
		t.Fatalf("Expected High severity for compound redemption burst, got %d", v.Severity)
	}
	if v.RulesTriggered&RuleBit3Redeem == 0 {
		t.Fatalf("Expected RuleBit3Redeem set")
	}
	if v.TransfersPauseDuration == 0 {
		t.Fatalf("Expected transfer pause duration for High severity")
	}
}

func TestPhase1_Rule4_CoreVaultAnomalyFiresCritical(t *testing.T) {
	// PHASE-1-TC-13: Rule 4 — Core Vault anomaly fires CRITICAL immediately
	r4 := NewVaultRule()
	r4.AnomalyDetected = true

	ctx := context.Background()
	v := r4.Evaluate(ctx, 100)
	if v.Severity != SeverityCritical {
		t.Fatalf("Expected Critical severity for Rule 4, got %d", v.Severity)
	}
	if v.RulesTriggered&RuleBit4Vault == 0 {
		t.Fatalf("Expected RuleBit4Vault set")
	}
}

func TestPhase1_Rule5_AlertOnly(t *testing.T) {
	// PHASE-1-TC-14: Rule 5 — alert only (INFO)
	r5 := NewLiqPayRule()
	r5.DeviationDetected = true

	ctx := context.Background()
	v := r5.Evaluate(ctx, 100)
	if v.Severity != SeverityInfo {
		t.Fatalf("Expected Info severity for Rule 5, got %d", v.Severity)
	}
	if v.RulesTriggered&RuleBit5LiqPay == 0 {
		t.Fatalf("Expected RuleBit5LiqPay bit set in alert")
	}
}

func TestPhase1_Engine_HighestSeverityWins(t *testing.T) {
	r1 := NewFTSORule(2.0, 0.015)
	r2 := NewCRRule()
	r3 := NewRedeemRule()
	r4 := NewVaultRule()
	r5 := NewLiqPayRule()
	r6 := NewSelfDealRule()

	// Setup: Rule 2 (Medium) + Rule 4 (Critical) both trigger
	r2.AffectedAgents = 5
	r2.DropPct = 0.10
	r4.AnomalyDetected = true

	engine := NewEngine(r1, r2, r3, r4, r5, r6)
	v, err := engine.Evaluate(context.Background(), 100)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if v.Severity != SeverityCritical {
		t.Fatalf("Expected Critical severity (highest wins), got %d", v.Severity)
	}
	// Both bitmasks should be set
	if v.RulesTriggered&(RuleBit2CR|RuleBit4Vault) != (RuleBit2CR | RuleBit4Vault) {
		t.Fatalf("Expected both RuleBit2CR and RuleBit4Vault set in bitmask, got 0x%02x", v.RulesTriggered)
	}
}
