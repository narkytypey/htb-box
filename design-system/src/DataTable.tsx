import * as React from 'react';

export interface DataTableColumn {
  /** Key looked up in each row object. */
  key: string;
  /** Uppercase grey column heading. */
  label: React.ReactNode;
}

export interface DataTableProps {
  columns: DataTableColumn[];
  /** One object per row, keyed by the columns' `key`. */
  rows: Array<Record<string, React.ReactNode>>;
}

/**
 * The portal's operational table: uppercase grey headings over a 2px black
 * rule, rows separated by a hairline tint.
 *
 * Used for site rosters and submitted-report lists. It is full-bleed inside
 * `ContentPad` - give it a `PanelTitle` above rather than a caption.
 */
export function DataTable({ columns, rows }: DataTableProps) {
  return (
    <table className="data-table">
      <thead>
        <tr>
          {columns.map((c) => (
            <th key={c.key}>{c.label}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row, i) => (
          <tr key={i}>
            {columns.map((c) => (
              <td key={c.key}>{row[c.key]}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
