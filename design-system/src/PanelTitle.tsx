import * as React from 'react';

export interface PanelTitleProps {
  children?: React.ReactNode;
}

/**
 * Section heading for tool screens: small condensed uppercase type behind a
 * 5px orange rule on the left.
 *
 * This is the portal's only section divider - it labels the report editor and
 * the branding form. Use it instead of an `h3`.
 */
export function PanelTitle({ children }: PanelTitleProps) {
  return <div className="panel-title">{children}</div>;
}
