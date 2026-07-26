package rules

import (
	"context"
)

// Rule 3: Compound Redemption Burst
type RedeemRule struct {
	BurstMultipleThreshold float64 // default 5.0x
	FDCTimeoutSeconds      uint64  // default 300s

	// Dynamic test state
	CurrentVolumeMultiple float64
	FDCAttestationTimeout bool
	FDCAttestationRef     [32]byte
	BaselineReady         bool
}

func NewRedeemRule() *RedeemRule {
	return &RedeemRule{
		BurstMultipleThreshold: 5.0,
		FDCTimeoutSeconds:      300,
		BaselineReady:          true,
	}
}

func (r *RedeemRule) Evaluate(ctx context.Context, block uint64) *ZukoVerdict {
	if !r.BaselineReady {
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: 0,
			Message:        "Rule 3: Baseline backfill incomplete (gated)",
		}
	}

	burstDetected := r.CurrentVolumeMultiple >= r.BurstMultipleThreshold

	if !burstDetected {
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: 0,
			Message:        "Rule 3: Redemption volume normal",
		}
	}

	if !r.FDCAttestationTimeout {
		// Burst alone = INFO alert (never pause on burst alone)
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: RuleBit3Redeem,
			Message:        "Rule 3: Redemption burst detected (FDC attestation pending)",
		}
	}

	// Compound A + B = HIGH pause
	return &ZukoVerdict{
		Severity:               SeverityHigh,
		RulesTriggered:         RuleBit3Redeem,
		OpsPauseDuration:       14400, // 4 hours ops pause
		TransfersPauseDuration: 14400, // 4 hours transfer pause
		FDCAttestationRef:      r.FDCAttestationRef,
		Message:                "Rule 3: Compound redemption burst + FDC attestation failure confirmed",
	}
}
