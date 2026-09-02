import * as React from 'react';
import { FieldHelp } from './FieldHelp';

export interface FieldProps {
  /** Ties the label to the input; also used as the input's `name` when `name` is unset. */
  id: string;
  /** Condensed uppercase label text. */
  label: React.ReactNode;
  /** Form field name. Defaults to `id`. */
  name?: string;
  /** Input type. Defaults to `text`. */
  type?: 'text' | 'password' | 'email' | 'url' | 'number';
  placeholder?: string;
  defaultValue?: string;
  /** Grey helper paragraph rendered under the input as a `FieldHelp`. */
  help?: React.ReactNode;
}

/**
 * A labelled text input - the portal's only form field.
 *
 * The input sits on the off-white `--off` fill inside a 2px black border and
 * takes a 3px orange focus ring. Stack `Field`s directly; each supplies its
 * own 15px bottom margin. Pass `help` for inputs whose accepted values need
 * explaining, as the branding form's logo URL does.
 */
export function Field({ id, label, name, type = 'text', placeholder, defaultValue, help }: FieldProps) {
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <input
        id={id}
        name={name ?? id}
        type={type}
        placeholder={placeholder}
        defaultValue={defaultValue}
      />
      {help ? <FieldHelp>{help}</FieldHelp> : null}
    </div>
  );
}
