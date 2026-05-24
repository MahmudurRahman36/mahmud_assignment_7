module.exports = {
  apps: [{
    name: 'bmi-app-exporter',
    script: './exporter.js',
    cwd: '/home/ubuntu/bmi-health-tracker/monitoring/exporters/bmi-app-exporter',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '200M',
    env: {
      NODE_ENV: 'production',
      EXPORTER_PORT: 9091
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true,
    merge_logs: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
