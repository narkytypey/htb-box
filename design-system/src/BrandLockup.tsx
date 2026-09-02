import * as React from 'react';
import { Mark } from './Mark';
import { Wordmark } from './Wordmark';

export interface BrandLockupProps {
  /** Word set beside the mark. Defaults to `Donerup`. */
  label?: React.ReactNode;
  /** Use the white wordmark, for the black `PortalBar` and `LoginHero`. */
  onDark?: boolean;
}

/**
 * Mark plus wordmark, locked to the stylesheet's 9px gap (renders `.mark-row`).
 *
 * This is the only sanctioned way to show the two brand elements together;
 * it appears in the top-left of every portal screen - always on black, always
 * with `onDark`. `Mark` needs a dark ground to read, so on a light surface use
 * `Wordmark` on its own rather than this lockup.
 */
export function BrandLockup({ label, onDark = false }: BrandLockupProps) {
  return (
    <div className="mark-row">
      <Mark />
      <Wordmark onDark={onDark}>{label}</Wordmark>
    </div>
  );
}
