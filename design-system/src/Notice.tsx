import * as React from 'react';

export interface NoticeProps {
  children?: React.ReactNode;
}

/**
 * Standing informational panel - off-white fill behind a 3px grey left rule.
 *
 * Deliberately grey, not orange: it carries operational advisories that are
 * not errors and need no action. Open with a bold lead-in
 * (`<strong>IT Operations notice.</strong>`) as the portal does.
 */
export function Notice({ children }: NoticeProps) {
  return <div className="notice">{children}</div>;
}
