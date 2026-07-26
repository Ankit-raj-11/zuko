package rules

import (
	"context"
	"math/big"
)

// Severity levels — match Solidity ZukoInstruction.severity
const (
	SeverityInfo     uint8 = 0
	SeverityMedium   uint8 = 1
	SeverityHigh     uint8 = 2
	SeverityCritical uint8 = 3
)

// Rule bitmask constants — match Solidity ZukoInstruction.rulesTriggered
const (
	RuleBit1FTSO   uint8 = 0x01
	RuleBit2CR     uint8 = 0x02
	RuleBit3Redeem uint8 = 0x04
	RuleBit4Vault  uint8 = 0x08
	RuleBit5LiqPay uint8 = 0x10
	RuleBit6Self   uint8 = 0x20
)

// ZukoVerdict is the output of one rule engine evaluation cycle.
type ZukoVerdict struct {
	Severity               uint8
	RulesTriggered         uint8
	OpsPauseDuration       uint32
	TransfersPauseDuration uint32
	FeedID                 [21]byte
	FeedValue              *big.Int
	AnchorValue            *big.Int
	BlockRangeStart        uint64
	BlockRangeEnd          uint64
	FDCAttestationRef      [32]byte
	Message                string
}

type Rule interface {
	Evaluate(ctx context.Context, block uint64) *ZukoVerdict
}

// Engine evaluates all 6 detection rules and merges verdicts (highest severity wins).
type Engine struct {
	Rule1 Rule
	Rule2 Rule
	Rule3 Rule
	Rule4 Rule
	Rule5 Rule
	Rule6 Rule
}

func NewEngine(r1, r2, r3, r4, r5, r6 Rule) *Engine {
	return &Engine{
		Rule1: r1,
		Rule2: r2,
		Rule3: r3,
		Rule4: r4,
		Rule5: r5,
		Rule6: r6,
	}
}

func (e *Engine) Evaluate(ctx context.Context, block uint64) (*ZukoVerdict, error) {
	var verdicts []*ZukoVerdict

	if e.Rule1 != nil { verdicts = append(verdicts, e.Rule1.Evaluate(ctx, block)) }
	if e.Rule2 != nil { verdicts = append(verdicts, e.Rule2.Evaluate(ctx, block)) }
	if e.Rule3 != nil { verdicts = append(verdicts, e.Rule3.Evaluate(ctx, block)) }
	if e.Rule4 != nil { verdicts = append(verdicts, e.Rule4.Evaluate(ctx, block)) }
	if e.Rule5 != nil { verdicts = append(verdicts, e.Rule5.Evaluate(ctx, block)) }
	if e.Rule6 != nil { verdicts = append(verdicts, e.Rule6.Evaluate(ctx, block)) }

	return MergeVerdicts(verdicts), nil
}

func MergeVerdicts(verdicts []*ZukoVerdict) *ZukoVerdict {
	merged := &ZukoVerdict{
		Severity:    SeverityInfo,
		FeedValue:   big.NewInt(0),
		AnchorValue: big.NewInt(0),
	}

	for _, v := range verdicts {
		if v == nil {
			continue
		}

		merged.RulesTriggered |= v.RulesTriggered

		if v.Severity > merged.Severity {
			merged.Severity = v.Severity
			merged.OpsPauseDuration = v.OpsPauseDuration
			merged.TransfersPauseDuration = v.TransfersPauseDuration
			merged.FeedID = v.FeedID
			if v.FeedValue != nil {
				merged.FeedValue = new(big.Int).Set(v.FeedValue)
			}
			if v.AnchorValue != nil {
				merged.AnchorValue = new(big.Int).Set(v.AnchorValue)
			}
			merged.BlockRangeStart = v.BlockRangeStart
			merged.BlockRangeEnd = v.BlockRangeEnd
			merged.FDCAttestationRef = v.FDCAttestationRef
			merged.Message = v.Message
		}
	}

	return merged
}
