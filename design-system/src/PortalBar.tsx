import * as React from 'react';
import { BrandLockup } from './BrandLockup';

export interface PortalBarProps {
  /** Right-hand slot - normally a `PortalNav`. */
  children?: React.ReactNode;
  /** Word beside the mark. Defaults to `Donerup`. */
  label?: React.ReactNode;
}

/**
 * The black chrome bar that tops every signed-in portal screen.
 *
 * It always carries the `BrandLockup` on the left (already set `onDark`) and
 * takes a `PortalNav` as its child on the right. Put it directly at the top of
 * the page with no wrapper - it supplies its own 16px/28px padding.
 */
export function PortalBar({ children, label }: PortalBarProps) {
  return (
    <div className="portal-bar">
      <BrandLockup onDark label={label} />
      {children}
    </div>
  );
}
