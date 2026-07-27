// Package enclave implements the TEE HTTP handler for the Zuko Rule Engine.
// This is the POST /action 4-step handler: validate → evaluate → sign → respond.
package enclave

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"time"

	"github.com/ethereum/go-ethereum/crypto"

	"github.com/ankit-raj-11/zuko/packages/rule-engine/internal/rules"
)

// ActionRequest is the JSON body POSTed by the backend to trigger rule evaluation.
type ActionRequest struct {
	BlockNumber     uint64  `json:"blockNumber"`
	FeedID          string  `json:"feedId"`
	FeedValue       string  `json:"feedValue"`
	AnchorValue     string  `json:"anchorValue"`
	ZScore          float64 `json:"zScore"`
	AnchorDeviation float64 `json:"anchorDeviation"`
	ChainID         uint32  `json:"chainId"`
	Nonce           uint64  `json:"nonce"`
}

// ActionResponse is the JSON body returned after rule evaluation and signing.
type ActionResponse struct {
	Severity               uint8  `json:"severity"`
	RulesTriggered         uint8  `json:"rulesTriggered"`
	OpsPauseDuration       uint32 `json:"opsPauseDuration"`
	TransfersPauseDuration uint32 `json:"transfersPauseDuration"`
	FeedID                 string `json:"feedId"`
	FeedValue              string `json:"feedValue"`
	AnchorValue            string `json:"anchorValue"`
	BlockRangeStart        uint64 `json:"blockRangeStart"`
	BlockRangeEnd          uint64 `json:"blockRangeEnd"`
	EncodedInstruction     string `json:"encodedInstruction"`
	Signature              string `json:"signature"`
	SignerAddress          string `json:"signerAddress"`
	Timestamp              int64  `json:"timestamp"`
	Message                string `json:"message"`
}

// Handler holds the rule engine and signing key for TEE enclave operations.
type Handler struct {
	Engine     *rules.Engine
	PrivateKey *ecdsa.PrivateKey
	ChainID    uint32
}

// NewHandler creates a new enclave handler with the given engine and signing key.
func NewHandler(engine *rules.Engine, privateKey *ecdsa.PrivateKey, chainID uint32) *Handler {
	return &Handler{
		Engine:     engine,
		PrivateKey: privateKey,
		ChainID:    chainID,
	}
}

// ServeHTTP implements the POST /action 4-step handler.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// ── Step 1: Validate input ──────────────────────────────────────────
	var req ActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"invalid JSON: %s"}`, err.Error()), http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	if req.BlockNumber == 0 {
		http.Error(w, `{"error":"blockNumber is required"}`, http.StatusBadRequest)
		return
	}
	if req.ChainID == 0 {
		http.Error(w, `{"error":"chainId is required"}`, http.StatusBadRequest)
		return
	}

	// ── Step 2: Run rules ───────────────────────────────────────────────
	feedValue := new(big.Int)
	feedValue.SetString(req.FeedValue, 10)
	anchorValue := new(big.Int)
	anchorValue.SetString(req.AnchorValue, 10)

	// Inject live data into rules before evaluation
	if ftsoRule, ok := h.Engine.Rule1.(*rules.FTSORule); ok {
		ftsoRule.CurrentZScore = req.ZScore
		ftsoRule.CurrentAnchorDev = req.AnchorDeviation
		ftsoRule.CurrentFeedValue = feedValue
		ftsoRule.CurrentAnchorValue = anchorValue
	}

	ctx := context.Background()
	verdict, err := h.Engine.Evaluate(ctx, req.BlockNumber)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"rule evaluation failed: %s"}`, err.Error()), http.StatusInternalServerError)
		return
	}

	// If no pause-worthy verdict, return info-level response (no signing needed)
	if verdict.Severity == rules.SeverityInfo {
		resp := ActionResponse{
			Severity:       verdict.Severity,
			RulesTriggered: verdict.RulesTriggered,
			BlockRangeEnd:  req.BlockNumber,
			Timestamp:      time.Now().Unix(),
			Message:        verdict.Message,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
		return
	}

	// ── Step 3: Build and sign ZukoInstruction ──────────────────────────
	instruction := buildInstruction(verdict, req)
	encodedInstruction := encodeInstruction(instruction)

	// EIP-191 prefix: keccak256("\x19Ethereum Signed Message:\n32" + keccak256(encodedInstruction))
	innerHash := crypto.Keccak256(encodedInstruction)
	prefixed := crypto.Keccak256(
		append([]byte("\x19Ethereum Signed Message:\n32"), innerHash...),
	)

	sig, err := crypto.Sign(prefixed, h.PrivateKey)
	if err != nil {
		log.Printf("[FATAL] TEE signing failed: %v", err)
		http.Error(w, `{"error":"signing failed"}`, http.StatusInternalServerError)
		return
	}
	// Adjust v value for Ethereum (27/28)
	sig[64] += 27

	signerAddr := crypto.PubkeyToAddress(h.PrivateKey.PublicKey)

	// ── Step 4: Respond ─────────────────────────────────────────────────
	resp := ActionResponse{
		Severity:               verdict.Severity,
		RulesTriggered:         verdict.RulesTriggered,
		OpsPauseDuration:       verdict.OpsPauseDuration,
		TransfersPauseDuration: verdict.TransfersPauseDuration,
		FeedID:                 hex.EncodeToString(instruction.FeedID[:]),
		FeedValue:              verdict.FeedValue.String(),
		AnchorValue:            verdict.AnchorValue.String(),
		BlockRangeStart:        verdict.BlockRangeStart,
		BlockRangeEnd:          verdict.BlockRangeEnd,
		EncodedInstruction:     "0x" + hex.EncodeToString(encodedInstruction),
		Signature:              "0x" + hex.EncodeToString(sig),
		SignerAddress:          signerAddr.Hex(),
		Timestamp:              time.Now().Unix(),
		Message:                verdict.Message,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// ZukoInstruction mirrors the Solidity struct for ABI encoding.
type ZukoInstruction struct {
	Severity               uint8
	RulesTriggered         uint8
	OpsPauseDuration       uint32
	TransfersPauseDuration uint32
	FeedID                 [32]byte
	FeedValue              *big.Int
	AnchorValue            *big.Int
	BlockRangeStart        uint64
	BlockRangeEnd          uint64
	FdcAttestationRef      [32]byte
	Nonce                  uint64
	ChainID                uint32
}

func buildInstruction(v *rules.ZukoVerdict, req ActionRequest) ZukoInstruction {
	var feedID32 [32]byte
	copy(feedID32[:], v.FeedID[:])

	return ZukoInstruction{
		Severity:               v.Severity,
		RulesTriggered:         v.RulesTriggered,
		OpsPauseDuration:       v.OpsPauseDuration,
		TransfersPauseDuration: v.TransfersPauseDuration,
		FeedID:                 feedID32,
		FeedValue:              v.FeedValue,
		AnchorValue:            v.AnchorValue,
		BlockRangeStart:        v.BlockRangeStart,
		BlockRangeEnd:          v.BlockRangeEnd,
		FdcAttestationRef:      v.FDCAttestationRef,
		Nonce:                  req.Nonce,
		ChainID:                req.ChainID,
	}
}

// encodeInstruction ABI-encodes the instruction to match Solidity abi.decode().
// This is a simplified encoding — in production, use go-ethereum's abi.Arguments.Pack().
func encodeInstruction(inst ZukoInstruction) []byte {
	// Pack fields as 32-byte words (Solidity ABI encoding)
	buf := make([]byte, 0, 12*32)
	buf = append(buf, padLeft([]byte{inst.Severity}, 32)...)
	buf = append(buf, padLeft([]byte{inst.RulesTriggered}, 32)...)
	buf = append(buf, padLeft(uint32ToBytes(inst.OpsPauseDuration), 32)...)
	buf = append(buf, padLeft(uint32ToBytes(inst.TransfersPauseDuration), 32)...)
	buf = append(buf, padLeft(inst.FeedID[:], 32)...)
	buf = append(buf, padLeft(inst.FeedValue.Bytes(), 32)...)
	buf = append(buf, padLeft(inst.AnchorValue.Bytes(), 32)...)
	buf = append(buf, padLeft(uint64ToBytes(inst.BlockRangeStart), 32)...)
	buf = append(buf, padLeft(uint64ToBytes(inst.BlockRangeEnd), 32)...)
	buf = append(buf, padLeft(inst.FdcAttestationRef[:], 32)...)
	buf = append(buf, padLeft(uint64ToBytes(inst.Nonce), 32)...)
	buf = append(buf, padLeft(uint32ToBytes(inst.ChainID), 32)...)
	return buf
}

func padLeft(b []byte, size int) []byte {
	if len(b) >= size {
		return b[:size]
	}
	padded := make([]byte, size)
	copy(padded[size-len(b):], b)
	return padded
}

func uint32ToBytes(v uint32) []byte {
	return []byte{byte(v >> 24), byte(v >> 16), byte(v >> 8), byte(v)}
}

func uint64ToBytes(v uint64) []byte {
	return []byte{
		byte(v >> 56), byte(v >> 48), byte(v >> 40), byte(v >> 32),
		byte(v >> 24), byte(v >> 16), byte(v >> 8), byte(v),
	}
}
