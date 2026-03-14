package worker

import (
	"testing"
	"time"
)

func TestBuildProbeDetailsExtractsVideoMetadata(t *testing.T) {
	t.Parallel()

	details := buildProbeDetails(ffprobeOutput{
		Streams: []ffprobeStream{
			{
				CodecType: "video",
				CodecName: "h264",
				Width:     1920,
				Height:    1080,
				Duration:  "12.500000",
				Tags: map[string]string{
					"creation_time": "2026-03-13T10:15:30Z",
				},
				SideData: []ffprobeSideData{{Rotation: 90}},
			},
		},
		Format: ffprobeFormat{
			FormatName: "mov,mp4,m4a,3gp,3g2,mj2",
			Duration:   "12.500000",
			BitRate:    "4500000",
			Size:       "7100000",
			Tags: map[string]string{
				"major_brand": "mp42",
			},
		},
	})

	if got, want := details.Width, 1920; got != want {
		t.Fatalf("Width = %d, want %d", got, want)
	}
	if got, want := details.Height, 1080; got != want {
		t.Fatalf("Height = %d, want %d", got, want)
	}
	if got, want := details.DurationSecs, 12.5; got != want {
		t.Fatalf("DurationSecs = %v, want %v", got, want)
	}
	if details.TakenAt == nil {
		t.Fatal("TakenAt = nil, want parsed timestamp")
	}
	if got, want := details.TakenAt.UTC(), time.Date(2026, time.March, 13, 10, 15, 30, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("TakenAt = %v, want %v", got, want)
	}

	extracted, ok := details.Metadata["extracted"].(map[string]any)
	if !ok {
		t.Fatal("Metadata.extracted missing")
	}
	if got, want := extracted["codec_name"], "h264"; got != want {
		t.Fatalf("Metadata.extracted.codec_name = %v, want %q", got, want)
	}
	if got, want := details.Metadata["rotation"], 90; got != want {
		t.Fatalf("Metadata.rotation = %v, want %d", got, want)
	}
}

func TestParseTimestampSupportsExifFormat(t *testing.T) {
	t.Parallel()

	parsed, ok := parseTimestamp("2026:03:14 08:45:12")
	if !ok {
		t.Fatal("parseTimestamp() = false, want true")
	}
	if got, want := parsed.UTC(), time.Date(2026, time.March, 14, 8, 45, 12, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("parseTimestamp() = %v, want %v", got, want)
	}
}

func TestChooseSeekOffsetUsesEarlyFrameForShortVideos(t *testing.T) {
	t.Parallel()

	if got, want := chooseSeekOffset(0.9), 0.3; got != want {
		t.Fatalf("chooseSeekOffset() = %v, want %v", got, want)
	}
	if got, want := chooseSeekOffset(12.0), 1.0; got != want {
		t.Fatalf("chooseSeekOffset() = %v, want %v", got, want)
	}
}
