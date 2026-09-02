import * as React from 'react';

export interface ReportActionsProps {
  /** Normally a single `secondary` `Button`. */
  children?: React.ReactNode;
}

/**
 * Right-aligns a form's action row, 16px below the field it follows.
 *
 * Used after `ReportTextarea` and the branding form's `Field`.
 */
export function ReportActions({ children }: ReportActionsProps) {
  return <div className="report-actions">{children}</div>;
}
