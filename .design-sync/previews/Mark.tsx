import * as React from 'react';
import { Mark } from '@donerup/ui';

const dark: React.CSSProperties = {
  background: 'var(--black)',
  padding: '22px 26px',
  display: 'flex',
  alignItems: 'flex-end',
  gap: 22,
};

export const Default = () => (
  <div style={dark}>
    <Mark />
  </div>
);

export const Sizes = () => (
  <div style={dark}>
    <Mark />
    <Mark size={40} />
    <Mark size={64} />
  </div>
);

export const InTheBar = () => (
  <div
    style={{
      background: 'var(--black)',
      padding: '16px 28px',
      display: 'flex',
      alignItems: 'center',
      gap: 9,
    }}
  >
    <Mark />
    <span className="wordmark on-dark">Donerup</span>
  </div>
);
