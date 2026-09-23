export interface Metric {
  label: string;
  value: string;
  helper: string;
}

interface MetricCardProps {
  metric: Metric;
}

export function MetricCard({ metric }: MetricCardProps) {
  return (
    <article className="metric-card">
      <span>{metric.label}</span>
      <strong>{metric.value}</strong>
      <small>{metric.helper}</small>
    </article>
  );
}
