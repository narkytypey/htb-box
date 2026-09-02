import * as React from 'react';
import { Button } from '@donerup/ui';

export const Primary = () => (
  <div style={{ maxWidth: 320 }}>
    <Button>Sign in</Button>
  </div>
);

export const Secondary = () => <Button variant="secondary">Render report</Button>;

export const SecondaryActions = () => (
  <div style={{ display: 'flex', gap: 12 }}>
    <Button variant="secondary">Preview logo</Button>
    <Button variant="secondary">Render report</Button>
  </div>
);
