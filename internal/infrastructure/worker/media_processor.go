package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/yourorg/mycloud/internal/domain"
)

const thumbnailContentType = "image/webp"

type FFMpegMediaProcessor struct {
	storage    domain.MediaProcessingStorage
	keyBuilder domain.MediaKeyBuilder
}

func NewFFMpegMediaProcessor(storage domain.MediaProcessingStorage, keyBuilder domain.MediaKeyBuilder) *FFMpegMediaProcessor {
	return &FFMpegMediaProcessor{
		storage:    storage,
		keyBuilder: keyBuilder,
	}
}

func (p *FFMpegMediaProcessor) Process(ctx context.Context, media *domain.Media) (domain.MediaProcessingResult, error) {
	if p == nil || p.storage == nil || p.keyBuilder == nil || media == nil {
		return domain.MediaProcessingResult{}, domain.ErrInvalidInput
	}

	workDir, err := os.MkdirTemp("", "mycloud-media-*")
	if err != nil {
		return domain.MediaProcessingResult{}, fmt.Errorf("create media work dir: %w", err)
	}
	defer os.RemoveAll(workDir)

	inputPath, err := p.downloadOriginal(ctx, workDir, media.OriginalKey)
	if err != nil {
		return domain.MediaProcessingResult{}, err
	}

	probeOutput, err := probeMedia(ctx, inputPath)
	if err != nil {
		return domain.MediaProcessingResult{}, err
	}
	probeDetails := buildProbeDetails(probeOutput)

	thumbKeys := p.keyBuilder.BuildThumbKeys(media.ID, media.MimeType)
	if err := p.generateThumbnails(ctx, inputPath, workDir, media, probeDetails, thumbKeys); err != nil {
		return domain.MediaProcessingResult{}, err
	}

	return domain.MediaProcessingResult{
		Width:        probeDetails.Width,
		Height:       probeDetails.Height,
		DurationSecs: probeDetails.DurationSecs,
		TakenAt:      probeDetails.TakenAt,
		ThumbKeys:    thumbKeys,
		Metadata:     probeDetails.Metadata,
	}, nil
}

func (p *FFMpegMediaProcessor) downloadOriginal(ctx context.Context, workDir, objectKey string) (string, error) {
	reader, err := p.storage.OpenOriginal(ctx, objectKey)
	if err != nil {
		return "", err
	}
	defer reader.Close()

	ext := filepath.Ext(strings.TrimSpace(objectKey))
	if ext == "" {
		ext = ".bin"
	}
	path := filepath.Join(workDir, "source"+ext)
	file, err := os.Create(path)
	if err != nil {
		return "", fmt.Errorf("create original temp file: %w", err)
	}

	if _, err := io.Copy(file, reader); err != nil {
		file.Close()
		return "", fmt.Errorf("write original temp file: %w", err)
	}
	if err := file.Close(); err != nil {
		return "", fmt.Errorf("close original temp file: %w", err)
	}

	return path, nil
}

func (p *FFMpegMediaProcessor) generateThumbnails(
	ctx context.Context,
	inputPath string,
	workDir string,
	media *domain.Media,
	probe probeDetails,
	keys domain.ThumbKeys,
) error {
	seekSeconds := chooseSeekOffset(probe.DurationSecs)
	targets := []thumbnailTarget{
		{OutputKey: keys.Small, MaxDimension: 320, OutputName: "small.webp"},
		{OutputKey: keys.Medium, MaxDimension: 800, OutputName: "medium.webp"},
		{OutputKey: keys.Large, MaxDimension: 1920, OutputName: "large.webp"},
	}
	if keys.Poster != "" {
		targets = append(targets, thumbnailTarget{OutputKey: keys.Poster, MaxDimension: 1280, OutputName: "poster.webp"})
	}

	for _, target := range targets {
		if strings.TrimSpace(target.OutputKey) == "" {
			continue
		}

		outputPath := filepath.Join(workDir, target.OutputName)
		if err := renderThumbnail(ctx, inputPath, outputPath, target.MaxDimension, isVideoMIME(media.MimeType), seekSeconds); err != nil {
			return err
		}
		if err := p.uploadThumbnail(ctx, target.OutputKey, outputPath); err != nil {
			return err
		}
	}

	return nil
}

func (p *FFMpegMediaProcessor) uploadThumbnail(ctx context.Context, key, path string) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open generated thumbnail: %w", err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat generated thumbnail: %w", err)
	}

	if err := p.storage.UploadThumbnail(ctx, key, thumbnailContentType, file, info.Size()); err != nil {
		return err
	}

	return nil
}

type thumbnailTarget struct {
	OutputKey    string
	OutputName   string
	MaxDimension int
}

func renderThumbnail(ctx context.Context, inputPath, outputPath string, maxDimension int, isVideo bool, seekSeconds float64) error {
	args := []string{"-hide_banner", "-loglevel", "error", "-y"}
	if isVideo && seekSeconds > 0 {
		args = append(args, "-ss", formatFFmpegSeconds(seekSeconds))
	}
	args = append(args, "-i", inputPath)
	args = append(args,
		"-vf", buildScaleFilter(maxDimension),
		"-frames:v", "1",
		"-vcodec", "libwebp",
		"-q:v", "82",
		outputPath,
	)

	output, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("render thumbnail: %w: %s", err, strings.TrimSpace(string(output)))
	}

	return nil
}

func buildScaleFilter(maxDimension int) string {
	return fmt.Sprintf(
		"scale=w='min(%d,iw)':h='min(%d,ih)':force_original_aspect_ratio=decrease,pad='ceil(iw/2)*2':'ceil(ih/2)*2'",
		maxDimension,
		maxDimension,
	)
}

func formatFFmpegSeconds(value float64) string {
	return strconv.FormatFloat(value, 'f', 3, 64)
}

func chooseSeekOffset(duration float64) float64 {
	if duration <= 0 {
		return 0
	}

	return math.Min(1, duration/3)
}

type ffprobeOutput struct {
	Streams []ffprobeStream `json:"streams"`
	Format  ffprobeFormat   `json:"format"`
}

type ffprobeStream struct {
	CodecType string            `json:"codec_type"`
	CodecName string            `json:"codec_name"`
	Width     int               `json:"width"`
	Height    int               `json:"height"`
	Duration  string            `json:"duration"`
	Tags      map[string]string `json:"tags"`
	SideData  []ffprobeSideData `json:"side_data_list"`
}

type ffprobeSideData struct {
	Rotation int `json:"rotation"`
}

type ffprobeFormat struct {
	FormatName string            `json:"format_name"`
	Duration   string            `json:"duration"`
	BitRate    string            `json:"bit_rate"`
	Size       string            `json:"size"`
	Tags       map[string]string `json:"tags"`
}

type probeDetails struct {
	Width        int
	Height       int
	DurationSecs float64
	TakenAt      *time.Time
	Metadata     map[string]any
}

func probeMedia(ctx context.Context, inputPath string) (ffprobeOutput, error) {
	args := []string{
		"-v", "error",
		"-print_format", "json",
		"-show_streams",
		"-show_format",
		inputPath,
	}

	output, err := exec.CommandContext(ctx, "ffprobe", args...).CombinedOutput()
	if err != nil {
		return ffprobeOutput{}, fmt.Errorf("probe media: %w: %s", err, strings.TrimSpace(string(output)))
	}

	var parsed ffprobeOutput
	if err := json.Unmarshal(output, &parsed); err != nil {
		return ffprobeOutput{}, fmt.Errorf("decode ffprobe output: %w", err)
	}

	return parsed, nil
}

func buildProbeDetails(output ffprobeOutput) probeDetails {
	primary := pickPrimaryStream(output.Streams)
	duration := parseOptionalFloat(output.Format.Duration)
	if duration <= 0 {
		duration = parseOptionalFloat(primary.Duration)
	}

	takenAt, source := extractTakenAt(output.Format.Tags, primary.Tags)
	rotation := 0
	for _, item := range primary.SideData {
		if item.Rotation != 0 {
			rotation = item.Rotation
			break
		}
	}

	metadata := map[string]any{
		"extracted": map[string]any{
			"format_name":   strings.TrimSpace(output.Format.FormatName),
			"codec_type":    strings.TrimSpace(primary.CodecType),
			"codec_name":    strings.TrimSpace(primary.CodecName),
			"duration_secs": duration,
			"bit_rate":      parseOptionalInt64(output.Format.BitRate),
			"size_bytes":    parseOptionalInt64(output.Format.Size),
			"width":         primary.Width,
			"height":        primary.Height,
		},
	}
	if rotation != 0 {
		metadata["rotation"] = rotation
	}
	if len(output.Format.Tags) > 0 {
		metadata["format_tags"] = stringMapToAny(output.Format.Tags)
	}
	if len(primary.Tags) > 0 {
		metadata["stream_tags"] = stringMapToAny(primary.Tags)
	}
	if takenAt != nil {
		metadata["taken_at_source"] = source
	}

	return probeDetails{
		Width:        primary.Width,
		Height:       primary.Height,
		DurationSecs: duration,
		TakenAt:      takenAt,
		Metadata:     metadata,
	}
}

func pickPrimaryStream(streams []ffprobeStream) ffprobeStream {
	for _, stream := range streams {
		if strings.EqualFold(strings.TrimSpace(stream.CodecType), "video") {
			return stream
		}
	}
	if len(streams) > 0 {
		return streams[0]
	}
	return ffprobeStream{}
}

func parseOptionalFloat(value string) float64 {
	parsed, _ := strconv.ParseFloat(strings.TrimSpace(value), 64)
	return parsed
}

func parseOptionalInt64(value string) int64 {
	parsed, _ := strconv.ParseInt(strings.TrimSpace(value), 10, 64)
	return parsed
}

func stringMapToAny(value map[string]string) map[string]any {
	result := make(map[string]any, len(value))
	for key, item := range value {
		if trimmed := strings.TrimSpace(item); trimmed != "" {
			result[key] = trimmed
		}
	}
	return result
}

func extractTakenAt(maps ...map[string]string) (*time.Time, string) {
	keys := []string{
		"creation_time",
		"com.apple.quicktime.creationdate",
		"date_time_original",
		"datetimeoriginal",
		"date_time",
		"datetime",
		"created",
		"date",
	}

	for _, values := range maps {
		lowered := map[string]string{}
		for key, value := range values {
			lowered[strings.ToLower(strings.TrimSpace(key))] = strings.TrimSpace(value)
		}
		for _, key := range keys {
			if value := lowered[key]; value != "" {
				if parsed, ok := parseTimestamp(value); ok {
					return &parsed, key
				}
			}
		}
	}

	return nil, ""
}

func parseTimestamp(value string) (time.Time, bool) {
	candidate := strings.TrimSpace(value)
	if candidate == "" {
		return time.Time{}, false
	}

	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02 15:04:05Z07:00",
		"2006-01-02T15:04:05Z07:00",
		"2006-01-02 15:04:05",
		"2006-01-02T15:04:05",
		"2006-01-02T15:04:05-0700",
		"2006:01:02 15:04:05",
		"2006:01:02 15:04:05Z07:00",
		"2006:01:02 15:04:05-0700",
	}

	for _, layout := range layouts {
		if parsed, err := time.Parse(layout, candidate); err == nil {
			return parsed.UTC(), true
		}
	}

	return time.Time{}, false
}

func isVideoMIME(mimeType string) bool {
	return strings.HasPrefix(strings.ToLower(strings.TrimSpace(mimeType)), "video/")
}
