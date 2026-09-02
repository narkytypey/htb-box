import * as React from 'react';

export interface FieldHelpProps {
  children?: React.ReactNode;
}

/**
 * Grey 13px helper paragraph explaining an input's accepted values.
 *
 * Normally passed to `Field` via its `help` prop rather than placed by hand;
 * it is also used standalone on the 403 page to explain why a screen is
 * unavailable.
 */
export function FieldHelp({ children }: FieldHelpProps) {
  return <p className="field-help">{children}</p>;
}
