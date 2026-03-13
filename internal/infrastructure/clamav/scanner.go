package clamav

import (
	"bufio"
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strings"
)

type Scanner struct {
	address string
	network string
}

func NewScanner(address string) *Scanner {
	trimmed := strings.TrimSpace(address)
	if trimmed == "" {
		return &Scanner{}
	}

	network := "unix"
	value := trimmed
	if strings.HasPrefix(trimmed, "tcp://") {
		network = "tcp"
		value = strings.TrimPrefix(trimmed, "tcp://")
	}

	return &Scanner{
		address: value,
		network: network,
	}
}

func (s *Scanner) ScanReader(ctx context.Context, r io.Reader) (bool, string, error) {
	if s.address == "" {
		return true, "", nil
	}

	conn, err := (&net.Dialer{}).DialContext(ctx, s.network, s.address)
	if err != nil {
		return false, "", fmt.Errorf("dial clamd: %w", err)
	}
	defer conn.Close()

	if _, err := io.WriteString(conn, "zINSTREAM\x00"); err != nil {
		return false, "", fmt.Errorf("start clamd instream: %w", err)
	}

	buf := make([]byte, 64*1024)
	sizeBuf := make([]byte, 4)
	for {
		n, readErr := r.Read(buf)
		if n > 0 {
			binary.BigEndian.PutUint32(sizeBuf, uint32(n))
			if _, err := conn.Write(sizeBuf); err != nil {
				return false, "", fmt.Errorf("write clamd chunk size: %w", err)
			}
			if _, err := conn.Write(buf[:n]); err != nil {
				return false, "", fmt.Errorf("write clamd chunk body: %w", err)
			}
		}
		if readErr == nil {
			continue
		}
		if readErr == io.EOF {
			break
		}

		return false, "", fmt.Errorf("read input for clamd: %w", readErr)
	}

	binary.BigEndian.PutUint32(sizeBuf, 0)
	if _, err := conn.Write(sizeBuf); err != nil {
		return false, "", fmt.Errorf("finish clamd instream: %w", err)
	}

	response, err := bufio.NewReader(conn).ReadString('\x00')
	if err != nil {
		return false, "", fmt.Errorf("read clamd response: %w", err)
	}

	message := strings.TrimSuffix(strings.TrimSpace(response), "\x00")
	if strings.HasSuffix(message, "OK") {
		return true, "", nil
	}
	if idx := strings.LastIndex(message, " FOUND"); idx >= 0 {
		threat := strings.TrimSpace(message)
		if colon := strings.Index(threat, ":"); colon >= 0 {
			threat = strings.TrimSpace(threat[colon+1 : idx])
		}
		return false, threat, nil
	}

	return false, "", fmt.Errorf("clamd error: %s", message)
}
