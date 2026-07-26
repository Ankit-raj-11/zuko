package rules

import (
	"context"
)

// Rule 2: Correlated CR Cliff
type CRRule struct {
	MinAffectedAgents int     // default 3
	DropPctThreshold  float64 // default 0.05 (5%)
	WindowBlocks      uint64  // default 10

	// Dynamic test/mock state
	AffectedAgents int
	DropPct        float64
}

func NewCRRule() *CRRule {
	return &CRRule{
		MinAffectedAgents: 3,
		DropPctThreshold:  0.05,
		WindowBlocks:      10,
	}
}

func (r *CRRule) Evaluate(ctx context.Context, block uint64) *ZukoVerdict {
	if r.AffectedAgents >= r.MinAffectedAgents && r.DropPct >= r.DropPctThreshold {
		return &ZukoVerdict{
			Severity:               SeverityMedium,
			RulesTriggered:         RuleBit2CR,
			OpsPauseDuration:       7200, // 2 hours ops pause
			TransfersPauseDuration: 0,
			BlockRangeStart:        block - r.WindowBlocks,
			BlockRangeEnd:          block,
			Message:                "Rule 2: Correlated CR cliff detected across multiple agent vaults",
		}
	}

	return &ZukoVerdict{
		Severity:       SeverityInfo,
		RulesTriggered: 0,
		Message:        "Rule 2: CR levels normal",
	}
}
