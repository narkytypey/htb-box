import * as React from 'react';

export interface ReportTextareaProps {
  /** Form field name. Defaults to `template`. */
  name?: string;
  placeholder?: string;
  defaultValue?: string;
  /** Visible rows before the vertical resize handle is needed. */
  rows?: number;
}

/**
 * The monospace editor used for store report templates.
 *
 * Same border and focus treatment as `Field`, but set in `--mono` at 13px/1.6
 * with a 160px floor and vertical-only resizing - it holds template source,
 * not prose.
 */
export function ReportTextarea({ name = 'template', placeholder, defaultValue, rows }: ReportTextareaProps) {
  return (
    <textarea
      className="report"
      name={name}
      placeholder={placeholder}
      defaultValue={defaultValue}
      rows={rows}
    />
  );
}
