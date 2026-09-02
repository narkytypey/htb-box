import * as React from 'react';
import { Field } from '@donerup/ui';

export const Credentials = () => (
  <div style={{ maxWidth: 360 }}>
    <Field id="username" label="Username" />
    <Field id="password" label="Password" type="password" />
  </div>
);

export const WithPlaceholder = () => (
  <div style={{ maxWidth: 360 }}>
    <Field id="logo_url" label="Logo URL" placeholder="https://cdn.example.com/logo.png" />
  </div>
);

export const WithHelp = () => (
  <div style={{ maxWidth: 420 }}>
    <Field
      id="logo_url"
      label="Logo URL"
      placeholder="https://cdn.example.com/logo.png"
      help="Paste a direct link to the asset. PNG or SVG, 320×80 or larger, transparent background preferred. The file is fetched once and checked before it is used as report letterhead."
    />
  </div>
);

export const Filled = () => (
  <div style={{ maxWidth: 360 }}>
    <Field id="site" label="Site code" defaultValue="DNR-022" />
  </div>
);
