import * as React from 'react';

export interface WelcomeBlockProps {
  /** Small orange eyebrow chip above the heading. Omit to hide it. */
  tag?: React.ReactNode;
  /** The heading line itself, e.g. `Welcome, j.arslan`. */
  children?: React.ReactNode;
}

/**
 * The dashboard's landing statement: an orange `welcome-tag` chip over a
 * fluid condensed heading that scales from 34px to 50px with the viewport.
 *
 * It is the one full-bleed block on the signed-in side - drop it straight
 * under the `PortalBar` with no `ContentPad` around it.
 */
export function WelcomeBlock({ tag, children }: WelcomeBlockProps) {
  return (
    <div className="welcome-block">
      {tag ? <span className="welcome-tag">{tag}</span> : null}
      <p className="welcome">{children}</p>
    </div>
  );
}
