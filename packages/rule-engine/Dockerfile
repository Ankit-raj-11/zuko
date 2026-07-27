FROM golang:1.22-alpine AS builder

ARG SOURCE_DATE_EPOCH=0
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go build -trimpath -ldflags="-s -w" -o /zuko-rule-engine ./cmd/enclave/main.go

FROM scratch
COPY --from=builder /zuko-rule-engine /zuko-rule-engine
ENTRYPOINT ["/zuko-rule-engine"]
