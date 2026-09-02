import * as React from 'react';

export interface ContentPadProps {
  children?: React.ReactNode;
}

/**
 * Standard page gutter for portal screens below the `PortalBar`
 * (40px top, 32px sides, 48px bottom).
 *
 * Use it for tool screens - the report builder and branding forms. The
 * dashboard uses the taller `WelcomeBlock` instead.
 */
export function ContentPad({ children }: ContentPadProps) {
  return <div className="content-pad">{children}</div>;
}
