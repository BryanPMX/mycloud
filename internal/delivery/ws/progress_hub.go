package ws

import (
	"bufio"
	"context"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
)

const (
	websocketGUID         = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	websocketTextFrame    = 0x1
	websocketCloseFrame   = 0x8
	websocketPingFrame    = 0x9
	websocketPongFrame    = 0xA
	progressSendBufferCap = 16
	progressPingInterval  = 30 * time.Second
)

type ProgressHub struct {
	subscriber domain.MediaProgressSubscriber

	mu      sync.RWMutex
	clients map[uuid.UUID]map[*progressClient]struct{}
}

type progressClient struct {
	hub    *ProgressHub
	userID uuid.UUID
	socket *websocketConn
	send   chan websocketFrame
	done   chan struct{}

	closeOnce sync.Once
}

type websocketConn struct {
	net.Conn
	reader *bufio.Reader
	writer *bufio.Writer
}

type websocketFrame struct {
	opcode  byte
	payload []byte
}

type progressMessage struct {
	Type      string             `json:"type"`
	MediaID   string             `json:"media_id"`
	Status    string             `json:"status,omitempty"`
	Reason    string             `json:"reason,omitempty"`
	ThumbURLs *progressThumbURLs `json:"thumb_urls,omitempty"`
}

type progressThumbURLs struct {
	Small  *string `json:"small,omitempty"`
	Medium *string `json:"medium,omitempty"`
	Large  *string `json:"large,omitempty"`
	Poster *string `json:"poster,omitempty"`
}

func NewProgressHub(subscriber domain.MediaProgressSubscriber) *ProgressHub {
	return &ProgressHub{
		subscriber: subscriber,
		clients:    make(map[uuid.UUID]map[*progressClient]struct{}),
	}
}

func (h *ProgressHub) Run(ctx context.Context) error {
	if h.subscriber == nil {
		<-ctx.Done()
		return ctx.Err()
	}

	return h.subscriber.SubscribeMediaProgress(ctx, h.broadcast)
}

func (h *ProgressHub) Handle(c *gin.Context) {
	userID, ok := middleware.UserIDFromContext(c)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
			"error": "unauthorized",
			"code":  "UNAUTHORIZED",
		})
		return
	}

	socket, err := upgradeWebSocket(c.Writer, c.Request)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{
			"error": "invalid websocket upgrade request",
			"code":  "INVALID_WEBSOCKET_REQUEST",
		})
		return
	}

	client := &progressClient{
		hub:    h,
		userID: userID,
		socket: socket,
		send:   make(chan websocketFrame, progressSendBufferCap),
		done:   make(chan struct{}),
	}
	h.register(client)
	client.run()
}

func (h *ProgressHub) register(client *progressClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	group := h.clients[client.userID]
	if group == nil {
		group = make(map[*progressClient]struct{})
		h.clients[client.userID] = group
	}
	group[client] = struct{}{}
}

func (h *ProgressHub) unregister(client *progressClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	group := h.clients[client.userID]
	if group == nil {
		return
	}
	delete(group, client)
	if len(group) == 0 {
		delete(h.clients, client.userID)
	}
}

func (h *ProgressHub) broadcast(event domain.MediaProgressEvent) {
	if event.OwnerID == uuid.Nil || event.MediaID == uuid.Nil {
		return
	}

	payload, err := marshalProgressMessage(event)
	if err != nil {
		return
	}

	h.mu.RLock()
	group := h.clients[event.OwnerID]
	clients := make([]*progressClient, 0, len(group))
	for client := range group {
		clients = append(clients, client)
	}
	h.mu.RUnlock()

	for _, client := range clients {
		client.enqueue(websocketFrame{
			opcode:  websocketTextFrame,
			payload: payload,
		})
	}
}

func (c *progressClient) run() {
	go c.writeLoop()
	c.readLoop()
	c.close()
}

func (c *progressClient) writeLoop() {
	ticker := time.NewTicker(progressPingInterval)
	defer ticker.Stop()
	defer c.close()

	for {
		select {
		case <-c.done:
			return
		case frame := <-c.send:
			if err := c.socket.writeFrame(frame.opcode, frame.payload); err != nil {
				return
			}
		case <-ticker.C:
			if err := c.socket.writeFrame(websocketPingFrame, nil); err != nil {
				return
			}
		}
	}
}

func (c *progressClient) readLoop() {
	defer c.close()

	for {
		opcode, payload, err := c.socket.readFrame()
		if err != nil {
			return
		}

		switch opcode {
		case websocketPingFrame:
			if !c.enqueue(websocketFrame{opcode: websocketPongFrame, payload: payload}) {
				return
			}
		case websocketCloseFrame:
			_ = c.socket.writeFrame(websocketCloseFrame, nil)
			return
		}
	}
}

func (c *progressClient) enqueue(frame websocketFrame) bool {
	select {
	case <-c.done:
		return false
	default:
	}

	frame.payload = append([]byte(nil), frame.payload...)
	select {
	case c.send <- frame:
		return true
	default:
		c.close()
		return false
	}
}

func (c *progressClient) close() {
	c.closeOnce.Do(func() {
		close(c.done)
		c.hub.unregister(c)
		if c.socket != nil {
			_ = c.socket.Close()
		}
	})
}

func marshalProgressMessage(event domain.MediaProgressEvent) ([]byte, error) {
	message := progressMessage{
		Type:    string(event.Type),
		MediaID: event.MediaID.String(),
		Status:  event.Status,
		Reason:  event.Reason,
	}

	if thumbs := toThumbURLs(event.ThumbURLs); thumbs != nil {
		message.ThumbURLs = thumbs
	}

	return json.Marshal(message)
}

func toThumbURLs(keys domain.ThumbKeys) *progressThumbURLs {
	urls := progressThumbURLs{
		Small:  stringPtr(keys.Small),
		Medium: stringPtr(keys.Medium),
		Large:  stringPtr(keys.Large),
		Poster: stringPtr(keys.Poster),
	}
	if urls.Small == nil && urls.Medium == nil && urls.Large == nil && urls.Poster == nil {
		return nil
	}

	return &urls
}

func upgradeWebSocket(writer http.ResponseWriter, request *http.Request) (*websocketConn, error) {
	if request.Method != http.MethodGet {
		return nil, errors.New("websocket upgrades require GET")
	}
	if !headerContainsToken(request.Header, "Connection", "upgrade") {
		return nil, errors.New("missing connection upgrade header")
	}
	if !strings.EqualFold(strings.TrimSpace(request.Header.Get("Upgrade")), "websocket") {
		return nil, errors.New("missing websocket upgrade header")
	}
	if strings.TrimSpace(request.Header.Get("Sec-WebSocket-Version")) != "13" {
		return nil, errors.New("unsupported websocket version")
	}

	key := strings.TrimSpace(request.Header.Get("Sec-WebSocket-Key"))
	if key == "" {
		return nil, errors.New("missing websocket key")
	}

	hijacker, ok := writer.(http.Hijacker)
	if !ok {
		return nil, errors.New("response writer does not support hijacking")
	}

	conn, rw, err := hijacker.Hijack()
	if err != nil {
		return nil, fmt.Errorf("hijack websocket connection: %w", err)
	}

	accept := computeAcceptKey(key)
	if _, err := rw.WriteString("HTTP/1.1 101 Switching Protocols\r\n"); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if _, err := rw.WriteString("Upgrade: websocket\r\n"); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if _, err := rw.WriteString("Connection: Upgrade\r\n"); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if _, err := rw.WriteString("Sec-WebSocket-Accept: " + accept + "\r\n\r\n"); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if err := rw.Flush(); err != nil {
		_ = conn.Close()
		return nil, err
	}

	return &websocketConn{
		Conn:   conn,
		reader: rw.Reader,
		writer: rw.Writer,
	}, nil
}

func computeAcceptKey(key string) string {
	sum := sha1.Sum([]byte(strings.TrimSpace(key) + websocketGUID))
	return base64.StdEncoding.EncodeToString(sum[:])
}

func headerContainsToken(header http.Header, key, token string) bool {
	for _, value := range header.Values(key) {
		for _, item := range strings.Split(value, ",") {
			if strings.EqualFold(strings.TrimSpace(item), token) {
				return true
			}
		}
	}

	return false
}

func (c *websocketConn) readFrame() (byte, []byte, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(c.reader, header); err != nil {
		return 0, nil, err
	}

	opcode := header[0] & 0x0F
	masked := header[1]&0x80 != 0
	if !masked {
		return 0, nil, errors.New("client websocket frames must be masked")
	}

	payloadLen, err := readPayloadLength(c.reader, header[1]&0x7F)
	if err != nil {
		return 0, nil, err
	}

	maskKey := make([]byte, 4)
	if _, err := io.ReadFull(c.reader, maskKey); err != nil {
		return 0, nil, err
	}

	payload := make([]byte, payloadLen)
	if _, err := io.ReadFull(c.reader, payload); err != nil {
		return 0, nil, err
	}
	for i := range payload {
		payload[i] ^= maskKey[i%4]
	}

	return opcode, payload, nil
}

func (c *websocketConn) writeFrame(opcode byte, payload []byte) error {
	var header []byte
	size := len(payload)
	switch {
	case size < 126:
		header = []byte{0x80 | opcode, byte(size)}
	case size <= 65535:
		header = make([]byte, 4)
		header[0] = 0x80 | opcode
		header[1] = 126
		binary.BigEndian.PutUint16(header[2:], uint16(size))
	default:
		header = make([]byte, 10)
		header[0] = 0x80 | opcode
		header[1] = 127
		binary.BigEndian.PutUint64(header[2:], uint64(size))
	}

	if _, err := c.writer.Write(header); err != nil {
		return err
	}
	if size > 0 {
		if _, err := c.writer.Write(payload); err != nil {
			return err
		}
	}

	return c.writer.Flush()
}

func readPayloadLength(reader *bufio.Reader, code byte) (int, error) {
	switch code {
	case 126:
		buf := make([]byte, 2)
		if _, err := io.ReadFull(reader, buf); err != nil {
			return 0, err
		}
		return int(binary.BigEndian.Uint16(buf)), nil
	case 127:
		buf := make([]byte, 8)
		if _, err := io.ReadFull(reader, buf); err != nil {
			return 0, err
		}
		length := binary.BigEndian.Uint64(buf)
		if length > uint64(^uint(0)>>1) {
			return 0, errors.New("websocket payload too large")
		}
		return int(length), nil
	default:
		return int(code), nil
	}
}

func stringPtr(value string) *string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	copyValue := value
	return &copyValue
}
