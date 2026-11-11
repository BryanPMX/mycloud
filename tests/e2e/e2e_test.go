//go:build e2e

package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const api = "http://127.0.0.1:58039/api/v1"

type account struct{ id, email, token, refresh string }

func call(t *testing.T, method, path, token string, body any, want int) map[string]any {
	t.Helper()
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequest(method, api+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	client := &http.Client{Timeout: 15 * time.Second}
	response, err := client.Do(req)
	if err != nil {
		t.Fatal("API request failed")
	}
	defer response.Body.Close()
	if response.StatusCode != want {
		t.Fatalf("%s %s status=%d want=%d", method, path, response.StatusCode, want)
	}
	var result map[string]any
	if want != 204 {
		if err := json.NewDecoder(response.Body).Decode(&result); err != nil && err != io.EOF {
			t.Fatal(err)
		}
	}
	return result
}
func seed(t *testing.T, db *pgxpool.Pool, role string) account {
	t.Helper()
	id := uuid.NewString()
	email := id + "@validation.invalid"
	hash, err := bcrypt.GenerateFromPassword([]byte("validation-password-unique"), 12)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(context.Background(), `INSERT INTO users(id,email,display_name,password_hash,role,quota_bytes) VALUES($1,$2,'Validation family member',$3,$4,1073741824)`, id, email, string(hash), role)
	if err != nil {
		t.Fatal(err)
	}
	payload := call(t, "POST", "/auth/login", "", map[string]any{"email": email, "password": "validation-password-unique"}, 200)
	return account{id: id, email: email, token: payload["access_token"].(string), refresh: payload["refresh_token"].(string)}
}
func upload(t *testing.T, owner account, name, mime string, data []byte) string {
	t.Helper()
	init := call(t, "POST", "/media/upload/init", owner.token, map[string]any{"filename": name, "mime_type": mime, "size_bytes": len(data)}, 201)
	id := init["media_id"].(string)
	uploadID := init["upload_id"].(string)
	signed := call(t, "POST", "/media/upload/"+id+"/part-url", owner.token, map[string]any{"upload_id": uploadID, "part_number": 1}, 200)
	req, err := http.NewRequest("PUT", signed["url"].(string), bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	response, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		t.Fatal("signed upload failed")
	}
	io.Copy(io.Discard, response.Body)
	response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatal("object upload rejected")
	}
	etag := response.Header.Get("ETag")
	call(t, "POST", "/media/upload/"+id+"/complete", owner.token, map[string]any{"upload_id": uploadID, "parts": []any{map[string]any{"part_number": 1, "etag": etag}}}, 200)
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		item := call(t, "GET", "/media/"+id, owner.token, nil, 200)
		if item["status"] == "ready" {
			return id
		}
		if item["status"] == "failed" {
			t.Fatal("worker rejected valid media")
		}
		time.Sleep(250 * time.Millisecond)
	}
	t.Fatal("worker did not finish processing valid media")
	return ""
}
func TestPrivateFamilyCloudEndToEnd(t *testing.T) {
	if os.Getenv("MYCLOUD_E2E") != "isolated-local-stack" {
		t.Skip("explicit local e2e acknowledgement required")
	}
	raw := os.Getenv("MYCLOUD_TEST_DATABASE_URL")
	cfg, err := pgxpool.ParseConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ConnConfig.Database != "mycloud_validation" || cfg.ConnConfig.Host != "127.0.0.1" || cfg.ConnConfig.Port != 55439 {
		t.Fatal("e2e requires isolated validation database")
	}
	db, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	// This database/host/port and acknowledgement were checked above. Reset only
	// generated validation fixtures so the restore rehearsal contains real objects.
	if _, err = db.Exec(context.Background(), `TRUNCATE users RESTART IDENTITY CASCADE`); err != nil {
		t.Fatal(err)
	}
	owner, member, outsider := seed(t, db, "admin"), seed(t, db, "member"), seed(t, db, "admin")
	frame := image.NewRGBA(image.Rect(0, 0, 160, 120))
	for y := 0; y < 120; y++ {
		for x := 0; x < 160; x++ {
			frame.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 100, A: 255})
		}
	}
	var photo bytes.Buffer
	if err = png.Encode(&photo, frame); err != nil {
		t.Fatal(err)
	}
	imageID := upload(t, owner, "family.png", "image/png", photo.Bytes())
	call(t, "GET", "/media/"+imageID, member.token, nil, 404)
	call(t, "GET", "/media/"+imageID+"/url", outsider.token, nil, 404)
	signed := call(t, "GET", "/media/"+imageID+"/url", owner.token, nil, 200)
	response, err := http.Get(signed["url"].(string))
	if err != nil {
		t.Fatal(err)
	}
	original, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if !bytes.Equal(original, photo.Bytes()) {
		t.Fatal("original bytes changed")
	}
	unsigned, _ := url.Parse(signed["url"].(string))
	unsigned.RawQuery = ""
	response, err = http.Get(unsigned.String())
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 403 {
		t.Fatal("bucket permits anonymous reads")
	}
	thumb := call(t, "GET", "/media/"+imageID+"/thumb", owner.token, nil, 200)
	response, err = http.Get(thumb["url"].(string))
	if err != nil {
		t.Fatal(err)
	}
	header, _ := io.ReadAll(io.LimitReader(response.Body, 16))
	response.Body.Close()
	if len(header) < 12 || string(header[8:12]) != "WEBP" {
		t.Fatal("thumbnail was not generated")
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Fatal("ffmpeg required for the video acceptance test")
	}
	videoPath := filepath.Join(t.TempDir(), "family.mp4")
	if err = exec.Command(ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x48:d=0.2", "-c:v", "libx264", "-pix_fmt", "yuv420p", videoPath).Run(); err != nil {
		t.Fatal("video fixture creation failed")
	}
	video, err := os.ReadFile(videoPath)
	if err != nil {
		t.Fatal(err)
	}
	videoID := upload(t, owner, "family.mp4", "video/mp4", video)
	if fixture := os.Getenv("MYCLOUD_TEST_HEIC_FIXTURE"); fixture != "" {
		data, err := os.ReadFile(fixture)
		if err != nil {
			t.Fatal(err)
		}
		upload(t, owner, "iphone.heic", "image/heic", data)
	}
	call(t, "DELETE", "/media/"+imageID, outsider.token, nil, 404)

	family := call(t, "POST", "/families", owner.token, map[string]any{"name": "E2E family"}, 201)["id"].(string)
	invitation := call(t, "POST", "/families/"+family+"/invitations", owner.token, map[string]any{"email": member.email}, 201)["token"].(string)
	call(t, "POST", "/families/invitations/accept", outsider.token, map[string]any{"token": invitation}, 401)
	call(t, "POST", "/families/invitations/accept", member.token, map[string]any{"token": invitation}, 200)
	post := call(t, "POST", "/families/"+family+"/posts", owner.token, map[string]any{"caption": "A private moment", "media_ids": []string{imageID, videoID}}, 201)["id"].(string)
	call(t, "GET", "/families/"+family+"/posts", outsider.token, nil, 404)
	page := call(t, "GET", "/families/"+family+"/posts", member.token, nil, 200)
	if len(page["posts"].([]any)) != 1 {
		t.Fatal("family feed missing shared post")
	}
	call(t, "GET", "/media/"+videoID+"/url", member.token, nil, 200)
	call(t, "DELETE", "/families/"+family+"/posts/"+post, member.token, nil, 404)

	album := call(t, "POST", "/albums", owner.token, map[string]any{"name": "Scoped family album"}, 201)["id"].(string)
	call(t, "POST", "/albums/"+album+"/media", owner.token, map[string]any{"media_ids": []string{videoID}}, 200)
	share := call(t, "POST", "/albums/"+album+"/shares", owner.token, map[string]any{"family_id": family, "permission": "view"}, 201)["id"].(string)
	call(t, "GET", "/albums/"+album, member.token, nil, 200)
	call(t, "GET", "/albums/"+album, outsider.token, nil, 404)
	call(t, "DELETE", "/families/"+family+"/posts/"+post, owner.token, nil, 204)
	call(t, "GET", "/media/"+imageID, owner.token, nil, 200)
	call(t, "GET", "/media/"+imageID+"/url", member.token, nil, 404)
	call(t, "GET", "/media/"+videoID+"/url", member.token, nil, 200)
	call(t, "DELETE", "/albums/"+album+"/shares/"+share, owner.token, nil, 204)
	call(t, "GET", "/media/"+videoID+"/url", member.token, nil, 404)
	call(t, "DELETE", "/media/"+imageID, owner.token, nil, 204)
	call(t, "GET", "/media/"+imageID+"/url", owner.token, nil, 404)
	call(t, "POST", "/media/"+imageID+"/restore", owner.token, nil, 204)
	call(t, "GET", "/media/"+imageID+"/url", owner.token, nil, 200)
	call(t, "DELETE", "/families/"+family+"/members/"+member.id, owner.token, nil, 204)
	call(t, "GET", "/families/"+family+"/posts", member.token, nil, 404)
	deletedUser := seed(t, db, "member")
	call(t, "POST", "/users/me/delete", deletedUser.token, map[string]any{"password": "wrong", "confirmation": "DELETE"}, 401)
	call(t, "POST", "/users/me/delete", deletedUser.token, map[string]any{"password": "validation-password-unique", "confirmation": "DELETE"}, 202)
	call(t, "GET", "/users/me", deletedUser.token, nil, 401)
	call(t, "POST", "/users/me/password", owner.token, map[string]any{"current_password": "wrong-current", "new_password": "replacement-validation-password"}, 403)
	call(t, "POST", "/users/me/password", owner.token, map[string]any{"current_password": "validation-password-unique", "new_password": "replacement-validation-password"}, 204)
	call(t, "GET", "/users/me", owner.token, nil, 401)
	call(t, "POST", "/auth/refresh", "", map[string]any{"refresh_token": owner.refresh}, 401)
	newSession := call(t, "POST", "/auth/login", "", map[string]any{"email": owner.email, "password": "replacement-validation-password"}, 200)
	call(t, "GET", "/users/me", newSession["access_token"].(string), nil, 200)
	response, err = http.Get("http://127.0.0.1:59049/metrics")
	if err != nil {
		t.Fatal(err)
	}
	metrics, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if !strings.Contains(string(metrics), "mycloud_http_requests_total") || strings.Contains(string(metrics), owner.id) {
		t.Fatal("metrics missing or contain private identifiers")
	}
	response, err = http.Get("http://127.0.0.1:58039/metrics")
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 404 {
		t.Fatal("metrics exposed on public API listener")
	}
}
