import * as React from 'react';
import { BrandLockup } from './BrandLockup';

export interface LoginHeroProps {
  /** Word beside the mark. Defaults to `Donerup`. */
  label?: React.ReactNode;
}

/**
 * The black masthead above the sign-in card, closed by the orange diagonal cut.
 *
 * The diagonal is a clip-path wedge anchored to the hero's bottom edge; the
 * 90px of bottom padding exists so the `LoginStage` below can pull its card up
 * over the cut with a negative margin. Always pair the two.
 */
export function LoginHero({ label }: LoginHeroProps) {
  return (
    <div className="login-hero">
      <BrandLockup onDark label={label} />
      <div className="diagonal" />
    </div>
  );
}
