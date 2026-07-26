package rules

import (
	"context"
)

// Rule 5: Liquidation Payout Deviation (Alert only)
type LiqPayRule struct {
	DeviationDetected bool
}

func NewLiqPayRule() *LiqPayRule {
	return &LiqPayRule{}
}

func (r *LiqPayRule) Evaluate(ctx context.Context, block uint64) *ZukoVerdict {
	if r.DeviationDetected {
		return &ZukoVerdict{
			Severity:       SeverityInfo,
			RulesTriggered: RuleBit5LiqPay,
			Message:        "Rule 5 ALERT: Liquidation payout deviation detected below FTSO-implied value",
		}
	}
	return &ZukoVerdict{
		Severity:       SeverityInfo,
		RulesTriggered: 0,
		Message:        "Rule 5: Liquidation payouts normal",
	}
}
