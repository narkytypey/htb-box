import * as React from 'react';
import { Wordmark } from '@donerup/ui';

export const OnLight = () => <Wordmark />;

export const OnDark = () => (
  <div style={{ background: 'var(--black)', padding: '18px 22px' }}>
    <Wordmark onDark />
  </div>
);
