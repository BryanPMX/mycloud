package observability

import (
	"context"
	"errors"
	"github.com/prometheus/client_golang/prometheus"
	"log/slog"
	"net/http"
	"time"
)

// ServePrivate listens on a distinct container port. Never proxy this port publicly.
func ServePrivate(ctx context.Context, addr string, metrics *Metrics, ready func(context.Context) error) {
	metrics.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "mycloud_ready", Help: "One when dependencies are ready; zero otherwise."}, func() float64 {
		probe, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if ready != nil && ready(probe) != nil {
			return 0
		}
		return 1
	}))
	mux := http.NewServeMux()
	mux.Handle("/metrics", metrics.Handler())
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("/health/ready", func(w http.ResponseWriter, r *http.Request) {
		probe, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		if ready != nil && ready(probe) != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	server := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 30 * time.Second}
	go func() {
		<-ctx.Done()
		stop, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(stop)
	}()
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("private_diagnostics_failed")
	}
}
