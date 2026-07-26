package rules

import (
	"context"
)

// Rule 4: Core Vault FDC Anomaly
type VaultRule struct {
	AnomalyDetected   bool
	FDCAttestationRef [32]byte
}

func NewVaultRule() *VaultRule {
	return &VaultRule{}
}

func (r *VaultRule) Evaluate(ctx context.Context, block uint64) *ZukoVerdict {
	if r.AnomalyDetected {
		return &ZukoVerdict{
			Severity:               SeverityCritical,
			RulesTriggered:         RuleBit4Vault,
			OpsPauseDuration:       21600, // 6 hours ops pause
			TransfersPauseDuration: 21600, // 6 hours transfer pause
			FDCAttestationRef:      r.FDCAttestationRef,
			Message:                "Rule 4: Core Vault FDC payment anomaly detected",
		}
	}

	return &ZukoVerdict{
		Severity:       SeverityInfo,
		RulesTriggered: 0,
		Message:        "Rule 4: Core Vault normal",
	}
}
