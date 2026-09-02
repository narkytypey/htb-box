import * as React from 'react';

export interface BuildTagProps {
  children?: React.ReactNode;
}

/**
 * Small grey build/version footnote, 12px, sitting under the sign-in card.
 *
 * Carries the portal build number, the maintenance window and the copyright
 * line. Secondary-text family alongside `Fineprint` and the `Card` subtitle -
 * all three use `--grey`.
 */
export function BuildTag({ children }: BuildTagProps) {
  return <p className="build-tag">{children}</p>;
}
