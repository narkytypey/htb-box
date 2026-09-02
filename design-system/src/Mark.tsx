import * as React from 'react';

export interface MarkProps {
  /** Square edge length in pixels. Defaults to the stylesheet's 26px `.mark` size. */
  size?: number;
  /** Extra class names appended after `mark`. */
  className?: string;
}

/**
 * The Donerup brand mark - a vertical spit crossed by three stacked skewers.
 *
 * Requires a dark ground. The two outer skewers are filled `--white`, so on
 * the white page background they disappear and the mark reads as two
 * disconnected orange fragments. Every use in the portal is inside the black
 * `PortalBar` or `LoginHero`; put it on `--black` or leave it out.
 */
export function Mark({ size, className }: MarkProps) {
  const style = size ? { width: size, height: size } : undefined;
  return (
    <svg
      className={className ? `mark ${className}` : 'mark'}
      style={style}
      viewBox="0 0 32 32"
      aria-hidden="true"
    >
      <line x1="16" y1="2" x2="16" y2="30" stroke="var(--orange)" strokeWidth="2.4" />
      <rect x="9" y="6" width="14" height="4.6" rx="1.5" fill="var(--white)" />
      <rect x="8" y="13" width="16" height="4.6" rx="1.5" fill="var(--orange)" />
      <rect x="9" y="20" width="14" height="4.6" rx="1.5" fill="var(--white)" />
    </svg>
  );
}
