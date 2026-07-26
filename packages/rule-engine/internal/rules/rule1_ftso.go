package rules

import (
	"context"
	"math/big"
)

// Rule 1: FTSO Anchor Deviation (3-step)
type FTSORule struct {
	SigmaWarnThreshold float64 // e.g., 2.0
	AnchorDevThreshold float64 // e.g., 0.015 (1.5%)
	ConsecutiveBlocks  map[uint64]int
	FeedID             [21]byte
	CurrentZScore      float64
	CurrentAnchorDev   float64
	CurrentFeedValue   *big.Int
	CurrentAnchorValue *big.Int
	ActiveStep         int
}

func NewFTSORule(sigmaThreshold, anchorDevThreshold float64) *FTSORule {
	return &FTSORule{
		SigmaWarnThreshold: sigmaThreshold,
		AnchorDevThreshold: anchorDevThreshold,
		ConsecutiveBlocks:  make(map[uint64]int),
		CurrentFeedValue:   big.NewInt(0),
		CurrentAnchorValue: big.NewInt(0),
	}
}

func (r *FTSORule) Evaluate(ctx context.Context, block uint64) *ZukoVerdict {
	deviationDetected := r.CurrentZScore > r.SigmaWarnThreshold && r.CurrentAnchorDev > r.AnchorDevThreshold

	if !deviationDetected {
		r.ActiveStep = 0
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: 0,
			Message:        "Rule 1: FTSO normal",
		}
	}

	r.ActiveStep++
	if r.ActiveStep < 3 {
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: RuleBit1FTSO,
			FeedID:         r.FeedID,
			FeedValue:      r.CurrentFeedValue,
			AnchorValue:    r.CurrentAnchorValue,
			Message:        "Rule 1 Step 1/2: Deviation detected, paying volatility incentive fee",
		}
	}

	// Step 3: Sustained across 3 consecutive blocks -> MEDIUM pause
	return &ZukoVerdict{
		Severity:               SeverityMedium,
		RulesTriggered:         RuleBit1FTSO,
		OpsPauseDuration:       3600, // 1 hour ops pause
		TransfersPauseDuration: 0,
		FeedID:                 r.FeedID,
		FeedValue:              r.CurrentFeedValue,
		AnchorValue:            r.CurrentAnchorValue,
		BlockRangeStart:        block - 2,
		BlockRangeEnd:          block,
		Message:                "Rule 1: Sustained FTSO deviation confirmed across 3 blocks",
	}
}
