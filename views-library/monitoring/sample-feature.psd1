@{
  FormatVersion = '1.1'
  Views = @{
    sample_event_outbox_metrics = @{
      Owner    = 'blackcat-monitoring'
      Tags     = @('monitoring','ops')
      Requires = @('event_outbox')
      create = @'
CREATE OR REPLACE VIEW vw_sample_event_outbox_metrics AS
SELECT
  DATE(created_at) AS day,
  COUNT(*) AS queued,
  SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) AS sent,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
FROM event_outbox
GROUP BY DATE(created_at)
ORDER BY day DESC;
'@
    }
  }
}
