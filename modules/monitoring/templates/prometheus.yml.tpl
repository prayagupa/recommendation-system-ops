global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
    project: "${name_prefix}"

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Scrape configuration
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: recs-serving
    metrics_path: /monitoring/prometheus/metrics
    static_configs:
      - targets:
%{ for target in scrape_targets ~}
          - "${target}"
%{ endfor ~}

  - job_name: redis-exporter
    static_configs:
      - targets: ["${name_prefix}-redis-exporter:9121"]
