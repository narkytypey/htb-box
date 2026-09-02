import * as React from 'react';

export interface KpiStripProps {
  /** A row of `Kpi` elements. */
  children?: React.ReactNode;
}

/**
 * Wrapping flex row of `Kpi` tiles - the dashboard's headline figures.
 *
 * Tiles keep a 150px floor and wrap onto a second line rather than
 * compressing, so the strip takes four metrics comfortably at desktop width.
 */
export function KpiStrip({ children }: KpiStripProps) {
  return <div className="kpi-strip">{children}</div>;
}
