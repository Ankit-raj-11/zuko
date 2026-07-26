package rules

import (
	"context"
)

// Rule 6: Agent Self-Dealing Heuristic (Alert only)
type SelfDealRule struct {
	SelfDealingDetected bool
}

func NewSelfDealRule() *SelfDealRule {
	return &SelfDealRule{}
}

func (r *SelfDealRule) Evaluate(ctx context.Context, block uint64) *ZukoVerdict {
	if r.SelfDealingDetected {
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: RuleBit6Self,
			Message:        "Rule 6 ALERT: Agent self-dealing heuristic anomaly flagged",
		}
	}
	return &ZukoVerdict{
		Severity:       SeverityInfo,
		RulesTriggered: 0,
		Message:        "Rule 6: Agent behaviour normal",
	}
}
