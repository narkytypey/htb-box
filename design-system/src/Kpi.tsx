import * as React from 'react';

export interface KpiProps {
  /** Uppercase grey caption, e.g. `Covers today`. */
  label: React.ReactNode;
  /** The figure itself, set 30px in the condensed display face. */
  value: React.ReactNode;
}

/**
 * A single store-operations metric: uppercase grey label over a large
 * condensed figure, on the off-white fill behind a 3px orange left rule.
 *
 * Always place these inside a `KpiStrip` - the strip owns the 14px gap and
 * the wrapping behaviour.
 */
export function Kpi({ label, value }: KpiProps) {
  return (
    <div className="kpi">
      <span className="kpi-label">{label}</span>
      <span className="kpi-value">{value}</span>
    </div>
  );
}
