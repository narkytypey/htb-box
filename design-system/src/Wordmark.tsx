import * as React from 'react';

export interface WordmarkProps {
  /** Word to set in the condensed display face. Defaults to `Donerup`. */
  children?: React.ReactNode;
  /** Switch the ink to `--white` for use on the black bar and hero. */
  onDark?: boolean;
}

/**
 * The Donerup wordmark: Barlow Condensed 900, uppercase, slightly tracked out.
 *
 * Pair it with `Mark` inside a `BrandLockup` rather than placing it alone -
 * the lockup owns the 9px gap between the two.
 */
export function Wordmark({ children = 'Donerup', onDark = false }: WordmarkProps) {
  return <span className={onDark ? 'wordmark on-dark' : 'wordmark'}>{children}</span>;
}
