import * as React from 'react';

export interface FineprintProps {
  children?: React.ReactNode;
}

/**
 * Centred 11.5px grey legal/help text, width-matched to the sign-in `Card`.
 *
 * Sits under the card inside `LoginStage` and carries the directory and
 * service-desk notices.
 */
export function Fineprint({ children }: FineprintProps) {
  return <footer className="fineprint">{children}</footer>;
}
