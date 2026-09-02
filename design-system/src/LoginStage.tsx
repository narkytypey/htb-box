import * as React from 'react';

export interface LoginStageProps {
  /** The `Card`, and optionally a `Fineprint` beneath it. */
  children?: React.ReactNode;
}

/**
 * Centres the sign-in card and lifts it 64px up over the `LoginHero`'s
 * orange diagonal.
 *
 * Only meaningful directly after a `LoginHero` - on its own the negative
 * top margin crops the card against whatever sits above it.
 */
export function LoginStage({ children }: LoginStageProps) {
  return (
    <div className="login-stage">
      <div>{children}</div>
    </div>
  );
}
