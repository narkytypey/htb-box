import * as React from 'react';

export interface ButtonProps {
  /**
   * `primary` fills the container width - the sign-in call to action.
   * `secondary` shrinks to its content for inline form actions.
   */
  variant?: 'primary' | 'secondary';
  /** Native button behaviour. Defaults to `submit`, matching the portal's forms. */
  type?: 'submit' | 'button' | 'reset';
  disabled?: boolean;
  onClick?: React.MouseEventHandler<HTMLButtonElement>;
  children?: React.ReactNode;
}

/**
 * The Donerup action button: orange fill, white condensed uppercase label,
 * 2px black border, darkening to `--orange-dim` on hover.
 *
 * There is exactly one colour - the system has no neutral or destructive
 * button. `variant` changes width only, never colour.
 */
export function Button({
  variant = 'primary',
  type = 'submit',
  disabled,
  onClick,
  children,
}: ButtonProps) {
  return (
    <button
      className={variant === 'secondary' ? 'btn secondary' : 'btn'}
      type={type}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}
