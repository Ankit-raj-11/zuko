package main

import (
	"crypto/ecdsa"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/ethereum/go-ethereum/crypto"

	"github.com/ankit-raj-11/zuko/packages/rule-engine/internal/enclave"
	"github.com/ankit-raj-11/zuko/packages/rule-engine/internal/rules"
)

func main() {
	fmt.Println("[Zuko Enclave] TEE Rule Engine v1.0 starting...")

	// Load signing key from environment or generate ephemeral key for dev
	var privateKey *ecdsa.PrivateKey
	var err error

	keyHex := os.Getenv("TEE_SIGNING_KEY")
	if keyHex != "" {
		privateKey, err = crypto.HexToECDSA(keyHex)
		if err != nil {
			log.Fatalf("[FATAL] Invalid TEE_SIGNING_KEY: %v", err)
		}
		fmt.Println("[Zuko Enclave] Loaded signing key from TEE_SIGNING_KEY env var")
	} else {
		privateKey, err = crypto.GenerateKey()
		if err != nil {
			log.Fatalf("[FATAL] Failed to generate ephemeral key: %v", err)
		}
		addr := crypto.PubkeyToAddress(privateKey.PublicKey)
		fmt.Printf("[Zuko Enclave] Generated ephemeral signing key: %s\n", addr.Hex())
		fmt.Println("[Zuko Enclave] WARNING: Set TEE_SIGNING_KEY for production use")
	}

	// Initialize all 6 detection rules
	r1 := rules.NewFTSORule(2.0, 0.015)
	r2 := rules.NewCRRule()
	r3 := rules.NewRedeemRule()
	r4 := rules.NewVaultRule()
	r5 := rules.NewLiqPayRule()
	r6 := rules.NewSelfDealRule()

	engine := rules.NewEngine(r1, r2, r3, r4, r5, r6)

	// Chain ID: Coston2 = 114
	chainID := uint32(114)

	handler := enclave.NewHandler(engine, privateKey, chainID)

	// Health check endpoint
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		signerAddr := crypto.PubkeyToAddress(privateKey.PublicKey)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"ok","signer":"%s","chainId":%d}`, signerAddr.Hex(), chainID)
	})

	// POST /action — the 4-step TEE rule evaluation pipeline
	http.Handle("/action", handler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := fmt.Sprintf("0.0.0.0:%s", port)
	fmt.Printf("[Zuko Enclave] Ready on POST %s/action\n", addr)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("[FATAL] Server failed: %v", err)
	}
}
