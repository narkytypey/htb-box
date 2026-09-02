import * as React from 'react';

export interface CardProps {
  /** Condensed uppercase heading, rendered as the card's `h2`. */
  title?: React.ReactNode;
  /** Grey supporting line under the title. */
  subtitle?: React.ReactNode;
  /** Card body - typically `Field`s and a `Button`. */
  children?: React.ReactNode;
}

/**
 * The signature Donerup surface: a 360px white panel with a 2px black border
 * and a hard 5px orange drop shadow - no blur, no radius.
 *
 * That offset shadow is the brand's most recognisable device. Keep it: a
 * softened or removed shadow reads as a different design system.
 */
export function Card({ title, subtitle, children }: CardProps) {
  return (
    <div className="card">
      {title ? <h2>{title}</h2> : null}
      {subtitle ? <p className="sub">{subtitle}</p> : null}
      {children}
    </div>
  );
}
