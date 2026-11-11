package observability

import (
	"context"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	goredis "github.com/redis/go-redis/v9"
	"net/http"
	"time"
)

type Metrics struct {
	Registry *prometheus.Registry
	Requests *prometheus.CounterVec
	Duration *prometheus.HistogramVec
	Jobs     *prometheus.CounterVec
	Uploads  *prometheus.CounterVec
}

func New(db *pgxpool.Pool, redis *goredis.Client) *Metrics {
	m := &Metrics{
		Registry: prometheus.NewRegistry(),
		Requests: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "mycloud_http_requests_total", Help: "HTTP requests by route and status class."}, []string{"method", "route", "status_class"}),
		Duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: "mycloud_http_request_duration_seconds", Help: "HTTP duration.", Buckets: prometheus.DefBuckets}, []string{"method", "route"}),
		Jobs:     prometheus.NewCounterVec(prometheus.CounterOpts{Name: "mycloud_media_jobs_total", Help: "Worker job outcomes."}, []string{"type", "outcome"}),
		Uploads:  prometheus.NewCounterVec(prometheus.CounterOpts{Name: "mycloud_upload_attempts_total", Help: "Upload initialization outcomes."}, []string{"outcome"}),
	}
	m.Registry.MustRegister(m.Requests, m.Duration, m.Jobs, m.Uploads, collectors.NewGoCollector(), collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
	if db != nil {
		m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "mycloud_db_connections_in_use", Help: "Acquired PostgreSQL connections."}, func() float64 { return float64(db.Stat().AcquiredConns()) }))
		m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "mycloud_db_connections_max", Help: "Maximum PostgreSQL connections."}, func() float64 { return float64(db.Stat().MaxConns()) }))
		for name, query := range map[string]string{
			"mycloud_storage_used_bytes": "SELECT COALESCE(sum(storage_used),0) FROM users",
			"mycloud_jobs_pending":       "SELECT count(*) FROM jobs WHERE status IN ('queued','running')",
			"mycloud_jobs_exhausted":     "SELECT count(*) FROM jobs WHERE status='failed' AND attempts>=3",
			"mycloud_deletions_pending":  "SELECT count(*) FROM media_deletions",
		} {
			m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: name, Help: "Aggregate service state; -1 means query unavailable."}, func() float64 {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				var value float64
				if err := db.QueryRow(ctx, query).Scan(&value); err != nil {
					return -1
				}
				return value
			}))
		}
	}
	if redis != nil {
		m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "mycloud_queue_depth", Help: "Redis dispatch hints; -1 means Redis unavailable."}, func() float64 {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			n, err := redis.LLen(ctx, "jobs:queue").Result()
			if err != nil {
				return -1
			}
			return float64(n)
		}))
	}
	return m
}
func (m *Metrics) Handler() http.Handler {
	return promhttp.HandlerFor(m.Registry, promhttp.HandlerOpts{})
}
func (m *Metrics) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		route := c.FullPath()
		if route == "" {
			route = "unmatched"
		}
		method := c.Request.Method
		switch method {
		case "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS":
		default:
			method = "OTHER"
		}
		status := "5xx"
		switch c.Writer.Status() / 100 {
		case 1:
			status = "1xx"
		case 2:
			status = "2xx"
		case 3:
			status = "3xx"
		case 4:
			status = "4xx"
		}
		m.Requests.WithLabelValues(method, route, status).Inc()
		m.Duration.WithLabelValues(method, route).Observe(time.Since(start).Seconds())
		if route == "/api/v1/media/upload/init" {
			outcome := "failure"
			if c.Writer.Status() < 400 {
				outcome = "accepted"
			}
			m.Uploads.WithLabelValues(outcome).Inc()
		}
	}
}
